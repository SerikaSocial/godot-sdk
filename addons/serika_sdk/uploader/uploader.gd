@tool
class_name SerikaUploader
extends Node

## Packages a world or avatar into a .serikaworld / .serikavatar container and submits it
## to the build farm. The container is a ZIP with manifest.json + scene + assets.
##
## The flow mirrors server/api's presigned-upload pattern:
##   1. validate the scene against the shared rules
##   2. package into a .serikaworld / .serikavatar file (ZIP + manifest.json)
##   3. ask the API for a presigned PUT URL
##   4. PUT the packaged bytes straight to storage (never through the API)
##   5. tell the API the upload landed so assetd can pick it up and validate server-side
##
## assetd (the sandboxed validator/build step) is M4; until its ingest endpoint exists the
## uploader packages + presigns and reports clearly what is not yet wired, rather than
## pretending to publish.

signal progress(message: String)
signal finished(success: bool, message: String)

var _http: HTTPRequest

func _ready() -> void:
	_http = HTTPRequest.new()
	add_child(_http)

## Package a world into a .serikaworld file. Returns the output path or empty on failure.
func package_world(source_dir: String, world_name: String, creator: String, out_path: String = "") -> String:
	if out_path.is_empty():
		out_path = "user://%s.serikaworld" % world_name.replace(" ", "_").to_lower()
	var manifest := SerikaFile.make_world_manifest(world_name, creator)
	if SerikaFile.write(out_path, source_dir, manifest):
		emit_signal("progress", "Packaged world → %s" % out_path)
		return out_path
	emit_signal("finished", false, "Failed to package world.")
	return ""

## Package an avatar into a .serikavatar file. Returns the output path or empty on failure.
func package_avatar(source_dir: String, avatar_name: String, creator: String, out_path: String = "") -> String:
	if out_path.is_empty():
		out_path = "user://%s.serikavatar" % avatar_name.replace(" ", "_").to_lower()
	var manifest := SerikaFile.make_avatar_manifest(avatar_name, creator)
	if SerikaFile.write(out_path, source_dir, manifest):
		emit_signal("progress", "Packaged avatar → %s" % out_path)
		return out_path
	emit_signal("finished", false, "Failed to package avatar.")
	return ""

## Legacy: package the given directory into a plain ZIP (no manifest). Kept for compatibility.
func package_source(source_dir: String, out_path: String) -> bool:
	var dir_abs := ProjectSettings.globalize_path(source_dir)
	var writer := ZIPPacker.new()
	if writer.open(out_path) != OK:
		emit_signal("finished", false, "Could not open %s for writing." % out_path)
		return false
	var count := _zip_dir(writer, dir_abs, "")
	writer.close()
	emit_signal("progress", "Packaged %d files → %s" % [count, out_path])
	return count > 0

func _zip_dir(writer: ZIPPacker, abs_dir: String, rel_prefix: String) -> int:
	var count := 0
	var d := DirAccess.open(abs_dir)
	if d == null:
		return 0
	d.list_dir_begin()
	var name := d.get_next()
	while name != "":
		if name.begins_with(".") or name == "node_modules":
			name = d.get_next()
			continue
		var abs_child := abs_dir.path_join(name)
		var rel_child := name if rel_prefix.is_empty() else rel_prefix.path_join(name)
		if d.current_is_dir():
			count += _zip_dir(writer, abs_child, rel_child)
		else:
			var bytes := FileAccess.get_file_as_bytes(abs_child)
			writer.start_file(rel_child)
			writer.write_file(bytes)
			writer.close_file()
			count += 1
		name = d.get_next()
	d.list_dir_end()
	return count

## Full submit: validate -> package .serikaworld -> presign -> PUT. Returns via `finished`.
func submit(world_root: Node, world_name: String, source_dir: String) -> void:
	await submit_typed(world_root, world_name, source_dir, SerikaFile.FORMAT_WORLD)

## Submit an avatar: validate -> package .serikavatar -> presign -> PUT.
func submit_avatar(avatar_root: Node, avatar_name: String, source_dir: String) -> void:
	await submit_typed(avatar_root, avatar_name, source_dir, SerikaFile.FORMAT_AVATAR)

## Core submit path for both worlds and avatars.
func submit_typed(root: Node, asset_name: String, source_dir: String, format: String) -> void:
	emit_signal("progress", "Validating…")
	var report := SerikaValidator.new().validate(root)
	if not report.ok():
		emit_signal("finished", false, "Validation failed:\n%s" % report.to_text())
		return

	# Package into .serikaworld or .serikavatar
	var ext := ".serikaworld" if format == SerikaFile.FORMAT_WORLD else ".serikavatar"
	var tmp := "user://%s_%d%s" % [asset_name.replace(" ", "_").to_lower(), Time.get_unix_time_from_system(), ext]
	var manifest := SerikaFile.make_world_manifest(asset_name) if format == SerikaFile.FORMAT_WORLD else SerikaFile.make_avatar_manifest(asset_name)
	if not SerikaFile.write(tmp, source_dir, manifest):
		emit_signal("finished", false, "Failed to package %s." % ext)
		return
	emit_signal("progress", "Packaged → %s" % tmp)

	var base := SerikaSdk.api_base()
	var token := SerikaSdk.session_token()
	if token.is_empty():
		emit_signal("finished", false,
			"No session token set. Set it in Project Settings → serika/sdk/session_token.")
		return

	emit_signal("progress", "Requesting upload URL…")
	var headers := [
		"Authorization: Bearer %s" % token,
		"Content-Type: application/json",
	]
	var kind := "world_source" if format == SerikaFile.FORMAT_WORLD else "avatar_source"
	var body := JSON.stringify({"kind": kind, "name": asset_name, "format": format})
	var err := _http.request(base + "/v1/assets/upload-url", headers, HTTPClient.METHOD_POST, body)
	if err != OK:
		emit_signal("finished", false, "HTTP request could not start (err %d)." % err)
		return
	var result = await _http.request_completed
	var code: int = result[1]
	var resp_body: PackedByteArray = result[3]
	var parsed = JSON.parse_string(resp_body.get_string_from_utf8())

	if code == 503:
		emit_signal("finished", false,
			"Server storage is not configured yet (B2 keys unset). Packaged locally at %s."
			% ProjectSettings.globalize_path(tmp))
		return
	if code < 200 or code >= 300 or typeof(parsed) != TYPE_DICTIONARY:
		emit_signal("finished", false, "Upload-URL request failed (HTTP %d)." % code)
		return

	var put_url := String(parsed.get("uploadUrl", ""))
	if put_url.is_empty():
		emit_signal("finished", false, "Server did not return an upload URL.")
		return

	emit_signal("progress", "Uploading package…")
	var bytes := FileAccess.get_file_as_bytes(tmp)
	err = _http.request_raw(put_url, ["Content-Type: application/zip"], HTTPClient.METHOD_PUT, bytes)
	if err != OK:
		emit_signal("finished", false, "PUT could not start (err %d)." % err)
		return
	result = await _http.request_completed
	code = result[1]
	if code >= 200 and code < 300:
		emit_signal("finished", true,
			"Uploaded '%s' (%s). assetd will validate and build it server-side (M4)." % [asset_name, ext])
	else:
		emit_signal("finished", false, "Upload PUT failed (HTTP %d)." % code)
