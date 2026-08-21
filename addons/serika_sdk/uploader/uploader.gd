@tool
class_name SerikaUploader
extends Node

## Packages a world's SOURCE (not a built .pck — clients never load creator artifacts) and
## submits it to the build farm. The flow mirrors server/api's presigned-upload pattern:
##   1. ask the API for a presigned PUT URL for a src/ object
##   2. PUT the packaged bytes straight to storage (never through the API)
##   3. tell the API the upload landed so assetd can pick it up and validate server-side
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

## Package the given directory (absolute OS path or res://) into a tar.zst-style archive.
## Godot ships no zstd; we use its built-in ZIP writer, which the build farm accepts.
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

## Full submit: validate -> package -> presign -> PUT. Returns via the `finished` signal.
func submit(world_root: Node, world_name: String, source_dir: String) -> void:
	emit_signal("progress", "Validating…")
	var report := SerikaValidator.new().validate(world_root)
	if not report.ok():
		emit_signal("finished", false, "Validation failed:\n%s" % report.to_text())
		return

	var tmp := "user://serika_upload_%d.zip" % Time.get_unix_time_from_system()
	if not package_source(source_dir, tmp):
		return

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
	var body := JSON.stringify({"kind": "world_source", "name": world_name})
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
			"Uploaded '%s'. assetd will validate and build it server-side (M4)." % world_name)
	else:
		emit_signal("finished", false, "Upload PUT failed (HTTP %d)." % code)
