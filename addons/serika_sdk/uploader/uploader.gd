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

## Full submit: validate -> package .serikaworld -> multipart upload. Returns via `finished`.
func submit(world_root: Node, world_name: String, source_dir: String, meta: Dictionary = {}) -> void:
	await submit_typed(world_root, world_name, source_dir, SerikaFile.FORMAT_WORLD, meta)

## Submit an avatar: validate -> package .serikavatar -> multipart upload.
func submit_avatar(avatar_root: Node, avatar_name: String, source_dir: String) -> void:
	await submit_typed(avatar_root, avatar_name, source_dir, SerikaFile.FORMAT_AVATAR, {})

## Core submit path for both worlds and avatars.
func submit_typed(root: Node, asset_name: String, source_dir: String, format: String, meta: Dictionary) -> void:
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

	var bytes := FileAccess.get_file_as_bytes(tmp)
	if bytes.is_empty():
		emit_signal("finished", false, "Failed to read packaged file.")
		return

	if format == SerikaFile.FORMAT_WORLD:
		emit_signal("progress", "Uploading world (%.1f MB)…" % (bytes.size() / 1048576.0))
		var boundary := "serika_boundary_%d" % Time.get_unix_time_from_system()
		var body := _build_multipart(boundary, asset_name, meta, bytes, ext)
		var headers := [
			"Authorization: Bearer %s" % token,
			"Content-Type: multipart/form-data; boundary=%s" % boundary,
		]
		var err := _http.request_raw(base + "/v1/worlds/upload", headers, HTTPClient.METHOD_POST, body)
		if err != OK:
			emit_signal("finished", false, "HTTP request could not start (err %d)." % err)
			return
		var result = await _http.request_completed
		var code: int = result[1]
		var resp_body: PackedByteArray = result[3]
		var parsed = JSON.parse_string(resp_body.get_string_from_utf8())
		if code >= 200 and code < 300:
			var world_id := String(parsed.get("worldId", "")) if typeof(parsed) == TYPE_DICTIONARY else ""
			var published := bool(parsed.get("published", false)) if typeof(parsed) == TYPE_DICTIONARY else false
			var status_msg := "Uploaded '%s' (%.1f MB)" % [asset_name, bytes.size() / 1048576.0]
			if published:
				status_msg += " — published!"
			else:
				var rs := String(parsed.get("reviewStatusLabel", "")) if typeof(parsed) == TYPE_DICTIONARY else ""
				if not rs.is_empty():
					status_msg += " — review: %s" % rs
			if not world_id.is_empty():
				status_msg += " (world %s)" % world_id
			emit_signal("finished", true, status_msg)
		else:
			var err_msg := String(parsed.get("error", "")) if typeof(parsed) == TYPE_DICTIONARY else "HTTP %d" % code
			var detail := String(parsed.get("detail", "")) if typeof(parsed) == TYPE_DICTIONARY else ""
			var full_msg := "Upload failed: %s" % err_msg
			if not detail.is_empty():
				full_msg += " — %s" % detail
			emit_signal("finished", false, full_msg)
	else:
		# Avatar upload — same multipart approach
		emit_signal("progress", "Uploading avatar (%.1f MB)…" % (bytes.size() / 1048576.0))
		var boundary := "serika_boundary_%d" % Time.get_unix_time_from_system()
		var body := _build_multipart(boundary, asset_name, {}, bytes, ext)
		var headers := [
			"Authorization: Bearer %s" % token,
			"Content-Type: multipart/form-data; boundary=%s" % boundary,
		]
		var err := _http.request_raw(base + "/v1/avatars/upload", headers, HTTPClient.METHOD_POST, body)
		if err != OK:
			emit_signal("finished", false, "HTTP request could not start (err %d)." % err)
			return
		var result = await _http.request_completed
		var code: int = result[1]
		if code >= 200 and code < 300:
			emit_signal("finished", true, "Uploaded avatar '%s' (%.1f MB)." % [asset_name, bytes.size() / 1048576.0])
		else:
			var resp_body: PackedByteArray = result[3]
			var parsed = JSON.parse_string(resp_body.get_string_from_utf8())
			var err_msg := String(parsed.get("error", "")) if typeof(parsed) == TYPE_DICTIONARY else "HTTP %d" % code
			emit_signal("finished", false, "Avatar upload failed: %s" % err_msg)

## Build a multipart/form-data body with file + metadata fields.
func _build_multipart(boundary: String, name: String, meta: Dictionary, file_bytes: PackedByteArray, file_ext: String) -> PackedByteArray:
	var out := PackedByteArray()
	var b := ("--%s\r\n" % boundary).to_utf8_buffer()
	var end := ("--%s--\r\n" % boundary).to_utf8_buffer()

	# name field
	out.append_array(b)
	out.append_array(("Content-Disposition: form-data; name=\"name\"\r\n\r\n").to_utf8_buffer())
	out.append_array(("%s\r\n" % name).to_utf8_buffer())

	# description field
	if meta.has("description"):
		out.append_array(b)
		out.append_array(("Content-Disposition: form-data; name=\"description\"\r\n\r\n").to_utf8_buffer())
		out.append_array(("%s\r\n" % String(meta["description"])).to_utf8_buffer())

	# tags field
	if meta.has("tags"):
		var tags := ",".join(meta["tags"]) if typeof(meta["tags"]) == TYPE_ARRAY else String(meta["tags"])
		out.append_array(b)
		out.append_array(("Content-Disposition: form-data; name=\"tags\"\r\n\r\n").to_utf8_buffer())
		out.append_array(("%s\r\n" % tags).to_utf8_buffer())

	# file field
	var filename := "%s%s" % [name.replace(" ", "_").to_lower(), file_ext]
	out.append_array(b)
	out.append_array(("Content-Disposition: form-data; name=\"file\"; filename=\"%s\"\r\n" % filename).to_utf8_buffer())
	out.append_array("Content-Type: application/zip\r\n\r\n".to_utf8_buffer())
	out.append_array(file_bytes)
	out.append_array("\r\n".to_utf8_buffer())

	out.append_array(end)
	return out
