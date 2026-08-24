@tool
@icon("res://addons/serika_sdk/icons/mirror.svg")
class_name SerikaMirror
extends Node3D

## A planar-reflection mirror. Renders the world reflected across this node’s local +Z plane.
## The surface is a QuadMesh facing +Z with a frame behind it. Place the mirror slightly in
## front of any wall (a few centimetres gap) so the reflected camera can clip the wall away.

@export_group("Mirror Surface")
## Width of the mirror in metres.
@export var width: float = 1.4
## Height of the mirror in metres.
@export var height: float = 2.2

@export_group("Reflection Quality")
## Render target size in pixels.
@export_enum("256:256", "512:512", "1024:1024", "2048:2048", "4096:4096") var resolution: int = 2
## Only render reflections when a player is within this distance (metres). 0 = always.
@export_range(0.0, 100.0, 0.5) var activation_distance: float = 12.0
## Render other players in the mirror (off = only reflect the local player, much cheaper).
@export var reflect_others: bool = true

@export_group("Correction")
## Tint the reflection.
@export_color_no_alpha var reflection_tint: Color = Color(0.9, 0.97, 0.94)
## Flip the reflection image horizontally if it appears reversed.
@export var flip_horizontal: bool = true
## Flip the reflection image vertically if it appears upside-down.
@export var flip_vertical: bool = false

@export_group("Performance")
## Minimum near-clip distance when the mirror is very close. Usually leave at 0.05.
@export_range(0.001, 0.5, 0.001) var min_near: float = 0.05

var _viewport: SubViewport
var _mirror_cam: Camera3D
var _surface: MeshInstance3D
var _frame: MeshInstance3D
var _shader: Shader = null

func _ready() -> void:
	if Engine.is_editor_hint():
		_update_editor_preview()
		return
	_build_mirror()

func _enter_tree() -> void:
	if Engine.is_editor_hint():
		_update_editor_preview()

func _exit_tree() -> void:
	if _viewport:
		_viewport.queue_free()
		_viewport = null

func _get_configuration_warnings() -> PackedStringArray:
	var warnings: PackedStringArray = []
	if resolution == 4 and reflect_others:
		warnings.append("2048 + reflect_others is very expensive; consider 1024 for social spaces.")
	return warnings

func _update_editor_preview() -> void:
	for c in get_children():
		c.queue_free()
	var f := MeshInstance3D.new()
	f.name = "FramePreview"
	f.mesh = BoxMesh.new()
	f.mesh.size = Vector3(width + 0.16, height + 0.16, 0.08)
	f.position = Vector3(0, height * 0.5, -0.04)
	f.material_override = StandardMaterial3D.new()
	f.material_override.albedo_color = Color(0.35, 0.26, 0.16)
	add_child(f)
	var g := MeshInstance3D.new()
	g.name = "GlassPreview"
	g.mesh = QuadMesh.new()
	g.mesh.size = Vector2(width, height)
	g.position = Vector3(0, height * 0.5, 0)
	g.material_override = StandardMaterial3D.new()
	g.material_override.albedo_color = Color(0.9, 0.97, 0.94, 0.6)
	g.material_override.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	add_child(g)

func _build_mirror() -> void:
	_frame = MeshInstance3D.new()
	_frame.name = "Frame"
	_frame.mesh = BoxMesh.new()
	_frame.mesh.size = Vector3(width + 0.16, height + 0.16, 0.08)
	_frame.position = Vector3(0, height * 0.5, -0.04)
	_frame.material_override = StandardMaterial3D.new()
	_frame.material_override.albedo_color = Color(0.35, 0.26, 0.16)
	_frame.material_override.metallic = 0.5
	_frame.material_override.roughness = 0.35
	add_child(_frame)

	var tex_size: int
	match resolution:
		0: tex_size = 256
		1: tex_size = 512
		2: tex_size = 1024
		3: tex_size = 2048
		4: tex_size = 4096
		_: tex_size = 1024

	_viewport = SubViewport.new()
	_viewport.name = "MirrorViewport"
	_viewport.size = Vector2i(tex_size, tex_size)
	_viewport.render_target_update_mode = SubViewport.UPDATE_DISABLED
	_viewport.render_target_clear_mode = SubViewport.CLEAR_ALWAYS
	_viewport.own_world_3d = false
	add_child(_viewport)

	_mirror_cam = Camera3D.new()
	_mirror_cam.name = "MirrorCamera"
	_mirror_cam.current = true
	_mirror_cam.top_level = true
	_viewport.add_child(_mirror_cam)

	_surface = MeshInstance3D.new()
	_surface.name = "Glass"
	_surface.mesh = QuadMesh.new()
	_surface.mesh.size = Vector2(width, height)
	_surface.position = Vector3(0, height * 0.5, 0)
	add_child(_surface)

	_shader = load("res://addons/serika_sdk/Shaders/mirror.gdshader") as Shader
	if _shader == null:
		_surface.material_override = StandardMaterial3D.new()
		_surface.material_override.albedo_color = Color.BLACK
		return

	var mat := ShaderMaterial.new()
	mat.shader = _shader
	mat.set_shader_parameter("color", reflection_tint)
	mat.set_shader_parameter("mirror_texture", _viewport.get_texture())
	mat.set_shader_parameter("flip_x", flip_horizontal)
	mat.set_shader_parameter("flip_y", flip_vertical)
	_surface.material_override = mat

	# Collision wall so the player can't walk through the mirror.
	var collider := StaticBody3D.new()
	collider.position = Vector3(0, height * 0.5, 0)
	var col_shape := CollisionShape3D.new()
	col_shape.shape = BoxShape3D.new()
	col_shape.shape.size = Vector3(width, height, 0.04)
	collider.add_child(col_shape)
	add_child(collider)

func _process(_delta: float) -> void:
	if _viewport == null or _mirror_cam == null:
		return
	var viewer := get_viewport().get_camera_3d()
	if viewer == null:
		return

	if _viewport.world_3d == null or _viewport.world_3d != get_viewport().world_3d:
		_viewport.world_3d = get_viewport().world_3d

	var plane_pos := _surface.global_position
	var viewer_pos := viewer.global_position
	if viewer_pos.distance_to(plane_pos) > activation_distance and activation_distance > 0:
		_viewport.render_target_update_mode = SubViewport.UPDATE_DISABLED
		return

	var normal := _surface.global_basis.z.normalized()
	var mirror_transform := _get_mirror_transform(normal, plane_pos)

	_mirror_cam.global_transform = mirror_transform * viewer.global_transform

	# The reflection matrix produces a left-handed coordinate system.
	# Flip the camera's right (X) axis to restore right-handedness.
	var b := _mirror_cam.global_basis
	b.x = -b.x
	_mirror_cam.global_basis = b

	var camera_to_mirror_offset := plane_pos - _mirror_cam.global_position
	var dist := abs(normal.dot(camera_to_mirror_offset))
	var near := maxf(0.01, dist - 0.02)

	# Asymmetric frustum offset so the mirror fills the viewport with correct perspective.
	var cam_to_mirror_local := _mirror_cam.global_basis.inverse() * camera_to_mirror_offset
	var frustum_offset := Vector2(-cam_to_mirror_local.x, -cam_to_mirror_local.y)
	_mirror_cam.set_frustum(width, frustum_offset, near, viewer.far)

	_viewport.render_target_update_mode = SubViewport.UPDATE_ALWAYS

func _get_mirror_transform(normal: Vector3, offset: Vector3) -> Transform3D:
	var nx := normal.x
	var ny := normal.y
	var nz := normal.z
	var bx := Vector3(1, 0, 0) - 2.0 * Vector3(nx * nx, nx * ny, nx * nz)
	var by := Vector3(0, 1, 0) - 2.0 * Vector3(ny * nx, ny * ny, ny * nz)
	var bz := Vector3(0, 0, 1) - 2.0 * Vector3(nz * nx, nz * ny, nz * nz)
	var origin := 2.0 * normal.dot(offset) * normal
	return Transform3D(bx, by, bz, origin)
