@tool
extends VBoxContainer

## The Serika SDK dock. Built in code (no .tscn) so the addon is a pure-script drop-in.
## Validate the edited world against the shared rules, package it, and submit to the build
## farm — or launch a local test session.

var plugin: EditorPlugin

var _output: RichTextLabel
var _uploader: SerikaUploader

func _init() -> void:
	name = "Serika"
	custom_minimum_size = Vector2(240, 0)

func _ready() -> void:
	var title := Label.new()
	title.text = "Serika SDK"
	title.add_theme_font_size_override("font_size", 16)
	add_child(title)

	_add_button("Validate current scene", _on_validate)
	_add_button("Package + Upload world", _on_upload_world)
	_add_button("Package + Upload avatar", _on_upload_avatar)
	_add_button("Import .serikaworld/.serikavatar…", _on_import)
	_add_button("Test locally (bot session)", _on_test_local)

	add_child(HSeparator.new())

	_output = RichTextLabel.new()
	_output.fit_content = true
	_output.selection_enabled = true
	_output.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_output.custom_minimum_size = Vector2(0, 160)
	add_child(_output)

	_log("Ready. Open a world scene and click Validate.")

func _add_button(text: String, cb: Callable) -> void:
	var b := Button.new()
	b.text = text
	b.pressed.connect(cb)
	add_child(b)

func _edited_root() -> Node:
	if plugin == null:
		return null
	return plugin.get_editor_interface().get_edited_scene_root()

func _on_validate() -> void:
	var root := _edited_root()
	if root == null:
		_log("[color=orange]No scene open. Open your world scene first.[/color]")
		return
	var report := SerikaValidator.new().validate(root)
	var color := "green" if report.ok() else "red"
	_log("[color=%s]%s[/color]" % [color, report.to_text()])

func _on_upload_world() -> void:
	var root := _edited_root()
	if root == null:
		_log("[color=orange]No scene open.[/color]")
		return
	if _uploader == null:
		_uploader = SerikaUploader.new()
		add_child(_uploader)
		_uploader.progress.connect(func(m): _log(m))
		_uploader.finished.connect(func(ok, m):
			_log("[color=%s]%s[/color]" % ["green" if ok else "red", m]))
	var scene_path := root.scene_file_path
	var source_dir := scene_path.get_base_dir() if scene_path != "" else "res://"
	_log("Submitting world '%s'…" % root.name)
	_uploader.submit(root, root.name, source_dir)

func _on_upload_avatar() -> void:
	var root := _edited_root()
	if root == null:
		_log("[color=orange]No scene open.[/color]")
		return
	if _uploader == null:
		_uploader = SerikaUploader.new()
		add_child(_uploader)
		_uploader.progress.connect(func(m): _log(m))
		_uploader.finished.connect(func(ok, m):
			_log("[color=%s]%s[/color]" % ["green" if ok else "red", m]))
	var scene_path := root.scene_file_path
	var source_dir := scene_path.get_base_dir() if scene_path != "" else "res://"
	_log("Submitting avatar '%s'…" % root.name)
	_uploader.submit_avatar(root, root.name, source_dir)

func _on_import() -> void:
	var dialog := EditorFileDialog.new()
	dialog.file_mode = EditorFileDialog.FILE_MODE_OPEN_FILE
	dialog.filters = PackedStringArray(["*.serikaworld ; Serika World", "*.serikavatar ; Serika Avatar"])
	dialog.access = EditorFileDialog.ACCESS_FILESYSTEM
	dialog.file_selected.connect(_on_import_selected)
	add_child(dialog)
	dialog.popup_centered(Vector2i(800, 600))

func _on_import_selected(path: String) -> void:
	var fmt := SerikaFile.detect_format(path)
	if fmt == "":
		_log("[color=red]Unknown format: %s[/color]" % path)
		return
	var manifest := SerikaFile.read_manifest(path)
	if manifest == null:
		_log("[color=red]Could not read manifest from %s[/color]" % path)
		return
	var dest := "res://imported/%s" % path.get_file().get_basename()
	SerikaFile.extract(path, dest)
	_log("[color=green]Imported %s '%s' → %s[/color]" % [fmt, manifest.name, dest])

func _on_test_local() -> void:
	# Launches the game client pointed at a local relay with synthetic bots. In M1 this just
	# runs the current scene through the editor's play button; the bot harness lands with M2.
	if plugin:
		plugin.get_editor_interface().play_current_scene()
		_log("Launched local play session. (Bot clients arrive with M2's harness.)")

func _log(msg: String) -> void:
	if _output:
		_output.append_text(msg + "\n")
	print("[Serika SDK] ", msg)
