@tool
class_name SerikaValidator
extends RefCounted

## Validates a world scene against the SAME rule file server/assetd uses
## (res://addons/serika_sdk/rules/world_rules.json). If it passes here it passes on upload;
## if it fails here the creator learns why locally instead of after a round trip.
##
## This is a SECURITY-RELEVANT allowlist, not a linter. The default posture is DENY: an
## unknown node type is rejected, not warned about.

const RULES_PATH := "res://addons/serika_sdk/rules/world_rules.json"

class Report:
	var errors: Array[String] = []
	var warnings: Array[String] = []
	var stats := {}
	func ok() -> bool:
		return errors.is_empty()
	func to_text() -> String:
		var lines: Array[String] = []
		lines.append("Serika world validation — %s" % ("PASS" if ok() else "FAIL"))
		for k in stats:
			lines.append("  • %s: %s" % [k, str(stats[k])])
		for e in errors:
			lines.append("  ✗ ERROR: %s" % e)
		for w in warnings:
			lines.append("  ⚠ WARN:  %s" % w)
		return "\n".join(lines)

var _rules := {}

func _init() -> void:
	_rules = _load_rules()

func _load_rules() -> Dictionary:
	if not FileAccess.file_exists(RULES_PATH):
		push_error("Serika: world_rules.json missing at %s" % RULES_PATH)
		return {}
	var text := FileAccess.get_file_as_string(RULES_PATH)
	var parsed = JSON.parse_string(text)
	if typeof(parsed) != TYPE_DICTIONARY:
		push_error("Serika: world_rules.json is not valid JSON")
		return {}
	return parsed

## Validate a scene root. Pass the root node of the world.
func validate(root: Node) -> Report:
	var r := Report.new()
	if _rules.is_empty():
		r.errors.append("Rule file could not be loaded; cannot validate.")
		return r

	var allow: Array = _rules.get("node_allowlist", [])
	var forbidden: Array = _rules.get("forbidden_node_types", [])
	var forbidden_props: Array = _rules.get("forbidden_properties", [])
	var forbidden_res: Array = _rules.get("forbidden_resource_classes", [])
	var budgets: Dictionary = _rules.get("budgets", {})

	var node_count := 0
	var spawn_count := 0
	var portal_count := 0
	var light_count := 0
	var audio_count := 0
	var tri_count := 0

	var stack: Array[Node] = [root]
	while not stack.is_empty():
		var n: Node = stack.pop_back()
		node_count += 1

		# --- node type allowlist (deny by default) ---
		var cls := _effective_class(n)
		if forbidden.has(cls):
			r.errors.append("%s: forbidden node type '%s'." % [_path(root, n), cls])
		elif not allow.has(cls):
			r.errors.append("%s: node type '%s' is not on the allowlist." % [_path(root, n), cls])

		# The SDK's own authoring nodes (allowlisted Serika* types) legitimately carry a tool
		# script for editing, but they are declarative data: the scene builder replaces them
		# with the client's native equivalents at build time, so their script never ships.
		# A node whose class merely starts with "Serika" but is NOT allowlisted is already
		# rejected above, so this exemption can't be used to smuggle a script in.
		var is_authoring: bool = cls.begins_with("Serika") and allow.has(cls)

		if not is_authoring:
			# --- attached script is fatal ---
			if n.get_script() != null:
				r.errors.append("%s: has an attached script. Behaviour must come from SerikaScript." % _path(root, n))
			# --- forbidden properties / embedded script resources ---
			for prop in forbidden_props:
				if _has_property(n, prop) and n.get(prop) != null:
					r.errors.append("%s: property '%s' must be empty." % [_path(root, n), prop])
			_scan_resources_for_scripts(n, root, r, forbidden_res)

		# --- counters for budgets ---
		if n is SerikaSpawnPoint:
			spawn_count += 1
		if n is SerikaPortal:
			portal_count += 1
		if n is Light3D:
			light_count += 1
		if n is AudioStreamPlayer3D:
			audio_count += 1
		if n is MeshInstance3D and n.mesh != null:
			tri_count += _estimate_triangles(n.mesh)

		for child in n.get_children():
			stack.push_back(child)

	# --- budgets ---
	_check_budget(r, budgets, "max_nodes", node_count, "nodes")
	_check_budget(r, budgets, "max_spawn_points", spawn_count, "spawn points")
	_check_budget(r, budgets, "max_portals", portal_count, "portals")
	_check_budget(r, budgets, "max_lights_realtime", light_count, "realtime lights")
	_check_budget(r, budgets, "max_audio_streams", audio_count, "audio streams")
	_check_budget(r, budgets, "max_triangles", tri_count, "triangles (est.)")

	# --- required ---
	var required: Dictionary = _rules.get("required", {})
	if required.get("at_least_one_spawn_point", false) and spawn_count == 0:
		r.errors.append("World has no SerikaSpawnPoint — players would have nowhere to appear.")

	r.stats = {
		"nodes": node_count,
		"spawn_points": spawn_count,
		"portals": portal_count,
		"lights": light_count,
		"audio_streams": audio_count,
		"triangles_est": tri_count,
	}
	return r

# Godot reports a custom class_name via get_class() only for engine types; for script
# classes we resolve the global class name so 'SerikaSpawnPoint' etc. match the allowlist.
func _effective_class(n: Node) -> String:
	var scr = n.get_script()
	if scr is Script:
		var gname: String = String(scr.get_global_name())
		if gname != "" and gname.begins_with("Serika"):
			return gname
	return n.get_class()

func _has_property(n: Object, prop: String) -> bool:
	for p in n.get_property_list():
		if p.get("name", "") == prop:
			return true
	return false

func _scan_resources_for_scripts(n: Node, root: Node, r: Report, forbidden_res: Array) -> void:
	for p in n.get_property_list():
		if not (int(p.get("usage", 0)) & PROPERTY_USAGE_STORAGE):
			continue
		var val = n.get(p.get("name", ""))
		if val is Resource:
			var res_cls: String = val.get_class()
			if forbidden_res.has(res_cls):
				r.errors.append("%s: embeds a %s resource." % [_path(root, n), res_cls])

func _estimate_triangles(mesh: Mesh) -> int:
	var total := 0
	for i in range(mesh.get_surface_count()):
		var arrays := mesh.surface_get_arrays(i)
		if arrays.size() > Mesh.ARRAY_INDEX and arrays[Mesh.ARRAY_INDEX] != null:
			total += arrays[Mesh.ARRAY_INDEX].size() / 3
		elif arrays.size() > Mesh.ARRAY_VERTEX and arrays[Mesh.ARRAY_VERTEX] != null:
			total += arrays[Mesh.ARRAY_VERTEX].size() / 3
	return total

func _check_budget(r: Report, budgets: Dictionary, key: String, value: int, label: String) -> void:
	if not budgets.has(key):
		return
	var limit := int(budgets[key])
	if value > limit:
		r.errors.append("Over budget: %d %s exceeds max of %d." % [value, label, limit])

func _path(root: Node, n: Node) -> String:
	if n == root:
		return n.name
	return String(root.get_path_to(n))
