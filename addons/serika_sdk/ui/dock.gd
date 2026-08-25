@tool
extends Control

## Serika SDK — the creator dashboard dock.
##
## A full tabbed interface for world and avatar creators:
##   • World  — metadata editor, validation, packaging, publishing, thumbnail capture
##   • Avatar — packaging and publishing for avatar rigs
##   • Browse — live world list from the API, with stats and one-click download
##   • Settings — API endpoint, session token, project info
##   • Help   — quick reference for all Serika authoring nodes
##
## Built entirely in code (no .tscn) so the addon remains a pure-script drop-in.

const PURPLE := Color(0.541, 0.392, 0.835, 1)
const PURPLE_DIM := Color(0.35, 0.25, 0.55, 1)
const PURPLE_HI := Color(0.7, 0.55, 0.95, 1)
const BG_DARK := Color(0.06, 0.04, 0.10, 1)
const BG_ROW := Color(0.14, 0.10, 0.20, 1)
const TEXT_DIM := Color(0.55, 0.50, 0.65, 1)
const TEXT_HI := Color(0.90, 0.85, 0.95, 1)
const OK_GREEN := Color(0.30, 0.85, 0.45, 1)
const ERR_RED := Color(0.90, 0.30, 0.35, 1)
const WARN_ORANGE := Color(0.95, 0.70, 0.30, 1)

var plugin: EditorPlugin

var _uploader: SerikaUploader
var _http: HTTPRequest
var _tab_bar: TabBar
var _pages: Dictionary = {}
var _current_page: String = "world"
var _output: RichTextLabel
var _world_meta: Dictionary = {}
var _status_label: Label
var _progress_bar: ProgressBar

var _name_edit: LineEdit
var _desc_edit: TextEdit
var _tags_edit: LineEdit
var _capacity_spin: SpinBox
var _world_id_label: Label
var _thumb_preview: TextureRect
var _thumb_path: String = ""

var _api_edit: LineEdit
var _token_edit: LineEdit

func _init() -> void:
	name = "SerikaSDK"
	custom_minimum_size = Vector2(340, 0)

func _ready() -> void:
	if Engine.is_editor_hint():
		_load_world_meta()
	_build_ui()

func _build_ui() -> void:
	var root := VBoxContainer.new()
	root.size_flags_vertical = Control.SIZE_EXPAND_FILL
	root.add_theme_constant_override("separation", 0)
	add_child(root)

	root.add_child(_make_header())

	_tab_bar = TabBar.new()
	_tab_bar.tab_count = 5
	_tab_bar.set_tab_title(0, "World")
	_tab_bar.set_tab_title(1, "Avatar")
	_tab_bar.set_tab_title(2, "Browse")
	_tab_bar.set_tab_title(3, "Settings")
	_tab_bar.set_tab_title(4, "Help")
	_tab_bar.tab_changed.connect(_on_tab_changed)
	_tab_bar.add_theme_font_size_override("font_size", 12)
	root.add_child(_tab_bar)

	var pages_vbox := VBoxContainer.new()
	pages_vbox.size_flags_vertical = Control.SIZE_EXPAND_FILL
	pages_vbox.add_theme_constant_override("separation", 0)
	root.add_child(pages_vbox)

	_pages["world"] = _build_world_page()
	_pages["avatar"] = _build_avatar_page()
	_pages["browse"] = _build_browse_page()
	_pages["settings"] = _build_settings_page()
	_pages["help"] = _build_help_page()

	for key in _pages:
		var page: Control = _pages[key]
		page.visible = (key == _current_page)
		pages_vbox.add_child(page)

	root.add_child(_make_status_bar())
	root.add_child(HSeparator.new())

	_output = RichTextLabel.new()
	_output.fit_content = true
	_output.selection_enabled = true
	_output.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_output.custom_minimum_size = Vector2(0, 100)
	_output.add_theme_font_size_override("normal_font_size", 11)
	root.add_child(_output)

	_log("[color=%s]Serika SDK ready.[/color]" % _c(PURPLE_HI))

func _make_header() -> Control:
	var bar := PanelContainer.new()
	bar.custom_minimum_size = Vector2(0, 36)
	var style := StyleBoxFlat.new()
	style.bg_color = BG_DARK
	style.content_margin_left = 10
	style.content_margin_top = 4
	style.content_margin_right = 10
	style.content_margin_bottom = 4
	bar.add_theme_stylebox_override("panel", style)

	var hbox := HBoxContainer.new()
	hbox.add_theme_constant_override("separation", 8)
	bar.add_child(hbox)

	var icon := Label.new()
	icon.text = "S"
	icon.add_theme_font_size_override("font_size", 18)
	icon.add_theme_color_override("font_color", PURPLE_HI)
	hbox.add_child(icon)

	var title := Label.new()
	title.text = "Serika SDK"
	title.add_theme_font_size_override("font_size", 15)
	title.add_theme_color_override("font_color", TEXT_HI)
	hbox.add_child(title)

	var spacer := Control.new()
	spacer.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	hbox.add_child(spacer)

	var ver := Label.new()
	ver.text = "v1.0.0"
	ver.add_theme_font_size_override("font_size", 10)
	ver.add_theme_color_override("font_color", TEXT_DIM)
	hbox.add_child(ver)

	return bar

func _make_status_bar() -> Control:
	var vbox := VBoxContainer.new()
	vbox.add_theme_constant_override("separation", 2)

	_progress_bar = ProgressBar.new()
	_progress_bar.visible = false
	_progress_bar.min_value = 0
	_progress_bar.max_value = 100
	_progress_bar.custom_minimum_size = Vector2(0, 4)
	vbox.add_child(_progress_bar)

	var hbox := HBoxContainer.new()
	hbox.add_theme_constant_override("separation", 6)
	vbox.add_child(hbox)

	var dot := Label.new()
	dot.text = "*"
	dot.add_theme_font_size_override("font_size", 10)
	dot.add_theme_color_override("font_color", OK_GREEN)
	hbox.add_child(dot)

	_status_label = Label.new()
	_status_label.text = "Ready"
	_status_label.add_theme_font_size_override("font_size", 10)
	_status_label.add_theme_color_override("font_color", TEXT_DIM)
	_status_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	hbox.add_child(_status_label)

	return vbox

func _build_world_page() -> Control:
	var scroll := ScrollContainer.new()
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	var vbox := VBoxContainer.new()
	vbox.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	vbox.add_theme_constant_override("separation", 8)
	scroll.add_child(vbox)

	vbox.add_child(_make_section_title("World Info"))

	var info_grid := GridContainer.new()
	info_grid.columns = 2
	info_grid.add_theme_constant_override("h_separation", 8)
	info_grid.add_theme_constant_override("v_separation", 4)
	vbox.add_child(info_grid)

	_name_edit = LineEdit.new()
	_name_edit.placeholder_text = "World name"
	_name_edit.text = _world_meta.get("name", "")
	_name_edit.text_changed.connect(func(t): _world_meta["name"] = t)
	info_grid.add_child(_make_label("Name"))
	info_grid.add_child(_name_edit)

	_capacity_spin = SpinBox.new()
	_capacity_spin.min_value = 1
	_capacity_spin.max_value = 200
	_capacity_spin.value = int(_world_meta.get("capacity", 32))
	_capacity_spin.value_changed.connect(func(v): _world_meta["capacity"] = v)
	info_grid.add_child(_make_label("Capacity"))
	info_grid.add_child(_capacity_spin)

	_tags_edit = LineEdit.new()
	_tags_edit.placeholder_text = "hangout, social, cozy"
	_tags_edit.text = ",".join(_world_meta.get("tags", []))
	_tags_edit.text_changed.connect(func(t): _world_meta["tags"] = t.split(","))
	info_grid.add_child(_make_label("Tags"))
	info_grid.add_child(_tags_edit)

	_world_id_label = Label.new()
	_world_id_label.text = _world_meta.get("worldId", "(new world)")
	_world_id_label.add_theme_color_override("font_color", TEXT_DIM)
	_world_id_label.add_theme_font_size_override("font_size", 10)
	info_grid.add_child(_make_label("World ID"))
	info_grid.add_child(_world_id_label)

	vbox.add_child(_make_label("Description"))
	_desc_edit = TextEdit.new()
	_desc_edit.custom_minimum_size = Vector2(0, 60)
	_desc_edit.text = _world_meta.get("description", "")
	_desc_edit.text_changed.connect(func(): _world_meta["description"] = _desc_edit.text)
	vbox.add_child(_desc_edit)

	vbox.add_child(_make_section_title("Thumbnail"))
	var thumb_row := HBoxContainer.new()
	thumb_row.add_theme_constant_override("separation", 8)
	vbox.add_child(thumb_row)

	_thumb_preview = TextureRect.new()
	_thumb_preview.custom_minimum_size = Vector2(96, 54)
	_thumb_preview.expand_mode = TextureRect.EXPAND_FIT_WIDTH_PROPORTIONAL
	_thumb_preview.stretch_mode = TextureRect.STRETCH_SCALE
	thumb_row.add_child(_thumb_preview)

	var thumb_btns := VBoxContainer.new()
	thumb_btns.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	thumb_btns.add_theme_constant_override("separation", 4)
	thumb_row.add_child(thumb_btns)

	thumb_btns.add_child(_make_button("Capture from viewport", _on_capture_thumb))
	thumb_btns.add_child(_make_button("Browse...", _on_browse_thumb))

	vbox.add_child(_make_section_title("Actions"))
	vbox.add_child(_make_button("Validate world", _on_validate_world, true))
	vbox.add_child(_make_button("Package .serikaworld", _on_package_world))
	vbox.add_child(_make_button("Publish to server", _on_publish_world, true))
	vbox.add_child(_make_button("Import .serikaworld...", _on_import_world))

	vbox.add_child(_make_section_title("Spawn Points"))
	vbox.add_child(_make_button("Add spawn point at origin", _on_add_spawn))

	return scroll

func _build_avatar_page() -> Control:
	var scroll := ScrollContainer.new()
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	var vbox := VBoxContainer.new()
	vbox.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	vbox.add_theme_constant_override("separation", 8)
	scroll.add_child(vbox)

	vbox.add_child(_make_section_title("Avatar Actions"))
	vbox.add_child(_make_button("Validate avatar", _on_validate_avatar, true))
	vbox.add_child(_make_button("Package .serikavatar", _on_package_avatar))
	vbox.add_child(_make_button("Publish avatar", _on_publish_avatar, true))
	vbox.add_child(_make_button("Import .serikavatar...", _on_import_avatar))

	vbox.add_child(_make_section_title("Avatar Tips"))
	var tips := Label.new()
	tips.text = "- Root node must be Node3D\n- Name the root after your avatar\n- Include a SerikaSpawnPoint for the spawn pose\n- Keep textures <= 4096px\n- Embed all textures in the scene"
	tips.add_theme_color_override("font_color", TEXT_DIM)
	tips.add_theme_font_size_override("font_size", 11)
	vbox.add_child(tips)

	return scroll

func _build_browse_page() -> Control:
	var vbox := VBoxContainer.new()
	vbox.size_flags_vertical = Control.SIZE_EXPAND_FILL
	vbox.add_theme_constant_override("separation", 8)

	var refresh_row := HBoxContainer.new()
	vbox.add_child(refresh_row)
	refresh_row.add_child(_make_button("Refresh", _on_browse_refresh))
	var spacer := Control.new()
	spacer.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	refresh_row.add_child(spacer)

	var scroll := ScrollContainer.new()
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	vbox.add_child(scroll)

	var list := VBoxContainer.new()
	list.name = "WorldList"
	list.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	list.add_theme_constant_override("separation", 4)
	scroll.add_child(list)

	_pages["_browse_list"] = list

	_on_browse_refresh()

	return vbox

func _build_settings_page() -> Control:
	var scroll := ScrollContainer.new()
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	var vbox := VBoxContainer.new()
	vbox.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	vbox.add_theme_constant_override("separation", 8)
	scroll.add_child(vbox)

	vbox.add_child(_make_section_title("Connection"))

	vbox.add_child(_make_label("API Base URL"))
	_api_edit = LineEdit.new()
	_api_edit.text = SerikaSdk.api_base()
	_api_edit.text_changed.connect(func(t):
		ProjectSettings.set_setting(SerikaSdk.SETTING_API_BASE, t.strip_edges())
		ProjectSettings.save())
	vbox.add_child(_api_edit)

	vbox.add_child(_make_label("Session Token"))
	_token_edit = LineEdit.new()
	_token_edit.text = SerikaSdk.session_token()
	_token_edit.secret = true
	_token_edit.text_changed.connect(func(t):
		ProjectSettings.set_setting(SerikaSdk.SETTING_TOKEN, t.strip_edges())
		ProjectSettings.save())
	vbox.add_child(_token_edit)

	vbox.add_child(_make_button("Test connection", _on_test_connection))

	vbox.add_child(_make_section_title("Project"))
	var proj_label := Label.new()
	proj_label.text = "Project: %s" % ProjectSettings.get_setting("application/config/name", "Untitled")
	proj_label.add_theme_color_override("font_color", TEXT_DIM)
	proj_label.add_theme_font_size_override("font_size", 11)
	vbox.add_child(proj_label)

	vbox.add_child(_make_section_title("World Metadata"))
	vbox.add_child(_make_button("Save world-meta.json", _on_save_meta))
	vbox.add_child(_make_button("Reload world-meta.json", _on_reload_meta))

	return scroll

func _build_help_page() -> Control:
	var scroll := ScrollContainer.new()
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	var vbox := VBoxContainer.new()
	vbox.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	vbox.add_theme_constant_override("separation", 6)
	scroll.add_child(vbox)

	vbox.add_child(_make_section_title("Authoring Nodes"))

	var nodes := [
		["SerikaSpawnPoint", "Marker3D", "Where players appear when joining the world. Set is_default on exactly one."],
		["SerikaPortal", "Area3D", "A teleport to another world. Players walk in and are transported."],
		["SerikaPickup", "Area3D", "A grabbable prop. Players pick it up and carry it around."],
		["SerikaAudioZone", "Area3D", "Plays audio when a player enters the area. Good for ambient sounds."],
		["SerikaMirror", "Node3D", "A real-time reflection mirror. Place against a wall."],
		["SerikaVideoPlayer", "MeshInstance3D", "A video screen. Supports YouTube IDs and stream URLs."],
		["SerikaWorldLoader", "Node", "Loads another world at runtime. Used for sub-areas."],
		["SerikaDevControls", "Control", "In-editor dev controls for testing. Stripped on publish."],
	]

	for node_info in nodes:
		var row := VBoxContainer.new()
		row.add_theme_constant_override("separation", 1)
		vbox.add_child(row)

		var title := Label.new()
		title.text = "  %s  (%s)" % [node_info[0], node_info[1]]
		title.add_theme_color_override("font_color", PURPLE_HI)
		title.add_theme_font_size_override("font_size", 12)
		row.add_child(title)

		var desc := Label.new()
		desc.text = "  " + node_info[2]
		desc.add_theme_color_override("font_color", TEXT_DIM)
		desc.add_theme_font_size_override("font_size", 10)
		desc.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		row.add_child(desc)

	vbox.add_child(_make_section_title("Workflow"))
	var steps := [
		"1. Build your world using Godot nodes + Serika authoring nodes",
		"2. Add at least one SerikaSpawnPoint",
		"3. Click Validate to check against server rules",
		"4. Fill in World Info (name, description, tags, capacity)",
		"5. Click Publish to upload to the server",
		"6. Your world goes live after review (or instantly if auto-approved)",
	]
	for s in steps:
		var l := Label.new()
		l.text = s
		l.add_theme_color_override("font_color", TEXT_DIM)
		l.add_theme_font_size_override("font_size", 11)
		vbox.add_child(l)

	vbox.add_child(_make_section_title("Validation Rules"))
	var rules := [
		"Max 20,000 nodes, 3M triangles, 24 realtime lights",
		"Max 512 materials, 4096px textures, 128 audio streams",
		"No scripts (GDScript/C#) - use SerikaScript for behaviour",
		"No custom shaders (until a shader validator is ready)",
		"No Camera3D, AnimationPlayer, HTTPRequest, or network nodes",
		"At least one SerikaSpawnPoint is required",
	]
	for r in rules:
		var l := Label.new()
		l.text = "- " + r
		l.add_theme_color_override("font_color", TEXT_DIM)
		l.add_theme_font_size_override("font_size", 10)
		vbox.add_child(l)

	return scroll

func _make_section_title(text: String) -> Label:
	var l := Label.new()
	l.text = text
	l.add_theme_font_size_override("font_size", 13)
	l.add_theme_color_override("font_color", PURPLE_HI)
	return l

func _make_label(text: String) -> Label:
	var l := Label.new()
	l.text = text
	l.add_theme_color_override("font_color", TEXT_DIM)
	l.add_theme_font_size_override("font_size", 11)
	return l

func _make_button(text: String, cb: Callable, primary: bool = false) -> Button:
	var b := Button.new()
	b.text = text
	b.pressed.connect(cb)
	b.add_theme_font_size_override("font_size", 12)
	if primary:
		b.add_theme_color_override("font_color", PURPLE_HI)
	return b

func _c(color: Color) -> String:
	return "#%02x%02x%02x%02x" % [int(color.r * 255), int(color.g * 255), int(color.b * 255), int(color.a * 255)]

func _set_status(text: String, color: Color = TEXT_DIM) -> void:
	if _status_label:
		_status_label.text = text
		_status_label.add_theme_color_override("font_color", color)

func _show_progress(visible: bool, value: float = 0.0) -> void:
	if _progress_bar:
		_progress_bar.visible = visible
		_progress_bar.value = value

func _log(msg: String) -> void:
	if _output:
		_output.append_text(msg + "\n")
	print("[Serika SDK] ", msg)

func _on_tab_changed(tab: int) -> void:
	var keys := ["world", "avatar", "browse", "settings", "help"]
	_current_page = keys[tab]
	for key in _pages:
		if _pages[key] is Control:
			_pages[key].visible = (key == _current_page)

func _edited_root() -> Node:
	if plugin == null:
		return null
	return plugin.get_editor_interface().get_edited_scene_root()

func _on_validate_world() -> void:
	var root := _edited_root()
	if root == null:
		_log("[color=%s]No scene open.[/color]" % _c(WARN_ORANGE))
		return
	_set_status("Validating...", PURPLE_HI)
	var report := SerikaValidator.new().validate(root)
	var color := OK_GREEN if report.ok() else ERR_RED
	_log("[color=%s]%s[/color]" % [_c(color), report.to_text()])
	_set_status("Validation %s" % ("PASS" if report.ok() else "FAIL"), color)

func _on_package_world() -> void:
	var root := _edited_root()
	if root == null:
		_log("[color=%s]No scene open.[/color]" % _c(WARN_ORANGE))
		return
	var scene_path := root.scene_file_path
	var source_dir := scene_path.get_base_dir() if scene_path != "" else "res://"
	var name := _name_edit.text.strip_edges()
	if name.is_empty():
		name = root.name
	if _uploader == null:
		_uploader = SerikaUploader.new()
		add_child(_uploader)
		_uploader.progress.connect(_on_upload_progress)
		_uploader.finished.connect(_on_upload_finished)
	_set_status("Packaging...", PURPLE_HI)
	_show_progress(true, 10)
	var path := _uploader.package_world(source_dir, name, "")
	if path != "":
		_log("[color=%s]Packaged -> %s[/color]" % [_c(OK_GREEN), path])
		_set_status("Packaged", OK_GREEN)
	else:
		_log("[color=%s]Packaging failed.[/color]" % _c(ERR_RED))
		_set_status("Packaging failed", ERR_RED)
	_show_progress(false)

func _on_publish_world() -> void:
	var root := _edited_root()
	if root == null:
		_log("[color=%s]No scene open.[/color]" % _c(WARN_ORANGE))
		return
	var token := SerikaSdk.session_token()
	if token.is_empty():
		_log("[color=%s]No session token. Set one in Settings.[/color]" % _c(ERR_RED))
		return
	var scene_path := root.scene_file_path
	var source_dir := scene_path.get_base_dir() if scene_path != "" else "res://"
	var name := _name_edit.text.strip_edges()
	if name.is_empty():
		name = root.name
	if _uploader == null:
		_uploader = SerikaUploader.new()
		add_child(_uploader)
		_uploader.progress.connect(_on_upload_progress)
		_uploader.finished.connect(_on_upload_finished)
	_set_status("Publishing...", PURPLE_HI)
	_show_progress(true, 5)
	_uploader.submit(root, name, source_dir)

func _on_upload_progress(msg: String) -> void:
	_log(msg)
	_set_status(msg, PURPLE_HI)
	if _progress_bar.visible and _progress_bar.value < 90:
		_progress_bar.value += 10

func _on_upload_finished(ok: bool, msg: String) -> void:
	var color := OK_GREEN if ok else ERR_RED
	_log("[color=%s]%s[/color]" % [_c(color), msg])
	_set_status(msg, color)
	_show_progress(false)

func _on_import_world() -> void:
	_show_import_dialog(SerikaFile.FORMAT_WORLD)

func _on_add_spawn() -> void:
	var root := _edited_root()
	if root == null:
		_log("[color=%s]No scene open.[/color]" % _c(WARN_ORANGE))
		return
	var spawn := SerikaSpawnPoint.new()
	spawn.name = "SpawnPoint"
	spawn.position = Vector3(0, 1, 0)
	spawn.is_default = true
	root.add_child(spawn)
	spawn.owner = root
	_log("[color=%s]Added spawn point at origin.[/color]" % _c(OK_GREEN))

func _on_capture_thumb() -> void:
	if plugin == null:
		return
	var vp := plugin.get_editor_interface().get_editor_main_screen().get_viewport()
	var img := vp.get_texture().get_image()
	if img == null:
		_log("[color=%s]Could not capture viewport.[/color]" % _c(ERR_RED))
		return
	var dir := "res://thumbnails"
	DirAccess.make_dir_recursive_absolute(dir)
	_thumb_path = "%s/thumb_%d.png" % [dir, Time.get_unix_time_from_system()]
	img.save_png(_thumb_path)
	var tex := ImageTexture.create_from_image(img)
	_thumb_preview.texture = tex
	_log("[color=%s]Thumbnail saved -> %s[/color]" % [_c(OK_GREEN), _thumb_path])

func _on_browse_thumb() -> void:
	var dialog := EditorFileDialog.new()
	dialog.file_mode = EditorFileDialog.FILE_MODE_OPEN_FILE
	dialog.filters = PackedStringArray(["*.png ; PNG Image", "*.jpg ; JPEG Image", "*.webp ; WebP Image"])
	dialog.access = EditorFileDialog.ACCESS_FILESYSTEM
	dialog.file_selected.connect(func(path):
		_thumb_path = path
		var img := Image.new()
		img.load(path)
		_thumb_preview.texture = ImageTexture.create_from_image(img))
	add_child(dialog)
	dialog.popup_centered(Vector2i(800, 600))

func _on_validate_avatar() -> void:
	_on_validate_world()

func _on_package_avatar() -> void:
	var root := _edited_root()
	if root == null:
		_log("[color=%s]No scene open.[/color]" % _c(WARN_ORANGE))
		return
	var scene_path := root.scene_file_path
	var source_dir := scene_path.get_base_dir() if scene_path != "" else "res://"
	if _uploader == null:
		_uploader = SerikaUploader.new()
		add_child(_uploader)
		_uploader.progress.connect(_on_upload_progress)
		_uploader.finished.connect(_on_upload_finished)
	_set_status("Packaging avatar...", PURPLE_HI)
	var path := _uploader.package_avatar(source_dir, root.name, "")
	if path != "":
		_log("[color=%s]Packaged -> %s[/color]" % [_c(OK_GREEN), path])
	else:
		_log("[color=%s]Packaging failed.[/color]" % _c(ERR_RED))
	_show_progress(false)

func _on_publish_avatar() -> void:
	var root := _edited_root()
	if root == null:
		_log("[color=%s]No scene open.[/color]" % _c(WARN_ORANGE))
		return
	var token := SerikaSdk.session_token()
	if token.is_empty():
		_log("[color=%s]No session token. Set one in Settings.[/color]" % _c(ERR_RED))
		return
	var scene_path := root.scene_file_path
	var source_dir := scene_path.get_base_dir() if scene_path != "" else "res://"
	if _uploader == null:
		_uploader = SerikaUploader.new()
		add_child(_uploader)
		_uploader.progress.connect(_on_upload_progress)
		_uploader.finished.connect(_on_upload_finished)
	_set_status("Publishing avatar...", PURPLE_HI)
	_show_progress(true, 5)
	_uploader.submit_avatar(root, root.name, source_dir)

func _on_import_avatar() -> void:
	_show_import_dialog(SerikaFile.FORMAT_AVATAR)

func _show_import_dialog(expected_format: String) -> void:
	var dialog := EditorFileDialog.new()
	dialog.file_mode = EditorFileDialog.FILE_MODE_OPEN_FILE
	if expected_format == SerikaFile.FORMAT_WORLD:
		dialog.filters = PackedStringArray(["*.serikaworld ; Serika World"])
	else:
		dialog.filters = PackedStringArray(["*.serikavatar ; Serika Avatar"])
	dialog.access = EditorFileDialog.ACCESS_FILESYSTEM
	dialog.file_selected.connect(func(path):
		_on_import_selected(path, expected_format))
	add_child(dialog)
	dialog.popup_centered(Vector2i(800, 600))

func _on_import_selected(path: String, _expected_format: String) -> void:
	var fmt := SerikaFile.detect_format(path)
	if fmt == "":
		_log("[color=%s]Unknown format: %s[/color]" % [_c(ERR_RED), path])
		return
	var manifest := SerikaFile.read_manifest(path)
	if manifest == null:
		_log("[color=%s]Could not read manifest from %s[/color]" % [_c(ERR_RED), path])
		return
	var dest := "res://imported/%s" % path.get_file().get_basename()
	SerikaFile.extract(path, dest)
	_log("[color=%s]Imported %s '%s' -> %s[/color]" % [_c(OK_GREEN), fmt, manifest.name, dest])

func _on_browse_refresh() -> void:
	var list: VBoxContainer = _pages.get("_browse_list", null)
	if list == null:
		return
	for child in list.get_children():
		child.queue_free()
	var loading := Label.new()
	loading.text = "Loading..."
	loading.add_theme_color_override("font_color", TEXT_DIM)
	list.add_child(loading)
	_fetch_world_list(list)

func _fetch_world_list(list: VBoxContainer) -> void:
	if _http == null:
		_http = HTTPRequest.new()
		add_child(_http)
	var api := SerikaSdk.api_base()
	var err := _http.request("%s/v1/worlds?limit=100" % api)
	if err != OK:
		_log("[color=%s]Could not start request (err %d).[/color]" % [_c(ERR_RED), err])
		return
	var result = await _http.request_completed
	var code: int = result[1]
	var body: PackedByteArray = result[3]
	for child in list.get_children():
		child.queue_free()
	if code != 200:
		var err_label := Label.new()
		err_label.text = "Failed to load (HTTP %d)" % code
		err_label.add_theme_color_override("font_color", ERR_RED)
		list.add_child(err_label)
		return
	var parsed = JSON.parse_string(body.get_string_from_utf8())
	if typeof(parsed) != TYPE_ARRAY:
		list.add_child(_make_label("Invalid response"))
		return
	_world_list_cache = parsed
	for w in parsed:
		list.add_child(_make_world_row(w))

func _make_world_row(w: Dictionary) -> Control:
	var panel := PanelContainer.new()
	var style := StyleBoxFlat.new()
	style.bg_color = BG_ROW
	style.content_margin_left = 8
	style.content_margin_top = 6
	style.content_margin_right = 8
	style.content_margin_bottom = 6
	style.border_width_left = 2
	style.border_color = PURPLE_DIM
	panel.add_theme_stylebox_override("panel", style)

	var vbox := VBoxContainer.new()
	vbox.add_theme_constant_override("separation", 2)
	panel.add_child(vbox)

	var name_row := HBoxContainer.new()
	vbox.add_child(name_row)

	var name := Label.new()
	name.text = String(w.get("name", "?"))
	name.add_theme_font_size_override("font_size", 12)
	name.add_theme_color_override("font_color", TEXT_HI)
	name.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	name_row.add_child(name)

	if bool(w.get("isBuiltin", false)):
		var badge := Label.new()
		badge.text = "BUILTIN"
		badge.add_theme_font_size_override("font_size", 9)
		badge.add_theme_color_override("font_color", PURPLE_HI)
		name_row.add_child(badge)

	var desc := Label.new()
	desc.text = String(w.get("description", "")).substr(0, 100)
	desc.add_theme_font_size_override("font_size", 10)
	desc.add_theme_color_override("font_color", TEXT_DIM)
	desc.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	vbox.add_child(desc)

	var stats := Label.new()
	stats.text = "Capacity: %d  |  Tags: %s" % [int(w.get("capacity", 0)), ",".join(w.get("tags", []))]
	stats.add_theme_font_size_override("font_size", 9)
	stats.add_theme_color_override("font_color", TEXT_DIM)
	vbox.add_child(stats)

	return panel

func _on_test_connection() -> void:
	if _http == null:
		_http = HTTPRequest.new()
		add_child(_http)
	var api := SerikaSdk.api_base()
	_set_status("Testing connection...", PURPLE_HI)
	var err := _http.request("%s/health" % api)
	if err != OK:
		_log("[color=%s]Could not start request.[/color]" % _c(ERR_RED))
		return
	var result = await _http.request_completed
	var code: int = result[1]
	if code == 200:
		_log("[color=%s]Connection OK - server is live.[/color]" % _c(OK_GREEN))
		_set_status("Connected", OK_GREEN)
	else:
		_log("[color=%s]Connection failed (HTTP %d).[/color]" % [_c(ERR_RED), code])
		_set_status("Connection failed", ERR_RED)

func _on_save_meta() -> void:
	var path := "res://world-meta.json"
	var f := FileAccess.open(path, FileAccess.WRITE)
	if f == null:
		_log("[color=%s]Could not write %s[/color]" % [_c(ERR_RED), path])
		return
	f.store_string(JSON.stringify(_world_meta, "  "))
	f.close()
	_log("[color=%s]Saved world metadata -> %s[/color]" % [_c(OK_GREEN), path])

func _on_reload_meta() -> void:
	_load_world_meta()
	_name_edit.text = _world_meta.get("name", "")
	_desc_edit.text = _world_meta.get("description", "")
	_tags_edit.text = ",".join(_world_meta.get("tags", []))
	_capacity_spin.value = int(_world_meta.get("capacity", 32))
	_world_id_label.text = _world_meta.get("worldId", "(new world)")
	_log("[color=%s]Reloaded world metadata.[/color]" % _c(OK_GREEN))

func _load_world_meta() -> void:
	var path := "res://world-meta.json"
	if FileAccess.file_exists(path):
		var text := FileAccess.get_file_as_string(path)
		var parsed = JSON.parse_string(text)
		if typeof(parsed) == TYPE_DICTIONARY:
			_world_meta = parsed
			return
	_world_meta = {"name": "", "description": "", "tags": [], "capacity": 32, "worldId": ""}
