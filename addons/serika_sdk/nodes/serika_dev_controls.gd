@tool
@icon("res://addons/serika_sdk/icons/spawn_point.svg")
class_name SerikaDevControls
extends Control

## In-editor and in-game developer overlay for testing Serika worlds. Shows diagnostics,
## spawn point gizmos, and quick actions (reload world, validate, force spawn).

@export_group("Display")
## Toggle the overlay at runtime.
@export var visible_by_default: bool = true
## Show frame time, draw calls, and mirror render cost.
@export var show_diagnostics: bool = true

@export_group("Actions")
## Key to toggle the overlay (only in play mode). Default: F10.
@export var toggle_key: Key = KEY_F10
## Reload the current world.
@export var reload_key: Key = KEY_F5

var _label: Label
var _reload_timer: float = 0.0

func _ready() -> void:
	visible = visible_by_default
	_label = Label.new()
	_label.set_anchors_and_offsets_preset(Control.PRESET_TOP_LEFT)
	_label.position = Vector2(12, 12)
	_label.add_theme_font_size_override("font_size", 14)
	add_child(_label)

func _process(delta: float) -> void:
	if not visible:
		return

	var text := "Serika Dev Controls\n"
	if show_diagnostics:
		text += "FPS: %d\n" % Engine.get_frames_per_second()
		text += "Draw calls: %d\n" % RenderingServer.get_rendering_info(RenderingServer.RENDERING_INFO_DRAW_CALLS_IN_FRAME)
		text += "Video mem: %.1f MB\n" % (RenderingServer.get_rendering_info(RenderingServer.RENDERING_INFO_VIDEO_MEM_USED) / 1048576.0)

	var player := get_viewport().get_camera_3d()
	if player:
		text += "Pos: %.2f, %.2f, %.2f\n" % [player.global_position.x, player.global_position.y, player.global_position.z]

	_label.text = text

	_reload_timer += delta
	if _reload_timer > 0.5 and Input.is_key_pressed(reload_key):
		_reload_timer = 0.0
		_reload_world()

func _input(event: InputEvent) -> void:
	if event is InputEventKey and event.keycode == toggle_key and event.pressed and not event.echo:
		visible = not visible

func _reload_world() -> void:
	var loader := _find_loader()
	if loader:
		loader._load_world()

func _find_loader() -> SerikaWorldLoader:
	var nodes := get_tree().get_nodes_in_group("serika_world_loader")
	if nodes.size() > 0:
		return nodes[0] as SerikaWorldLoader
	# Fallback search.
	for n in get_tree().root.find_children("*", "SerikaWorldLoader", true, false):
		return n as SerikaWorldLoader
	return null
