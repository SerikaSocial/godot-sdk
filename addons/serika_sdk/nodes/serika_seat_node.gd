## SeatNode — a seat the player can sit on by pressing E when near.
## Place in a world scene. The player walks up, presses interact, and is seated.
@tool
class_name SerikaSeatNode
extends Area3D

@export var seat_label: String = "Seat"
@export var sit_offset: Vector3 = Vector3(0, 0.45, 0)
@export var sit_yaw: float = 0.0

var _occupied: bool = false


func _ready() -> void:
	if Engine.is_editor_hint():
		return
	var col := CollisionShape3D.new()
	col.shape = BoxShape3D.new()
	col.shape.size = Vector3(0.8, 0.8, 0.8)
	add_child(col)

	var marker := MeshInstance3D.new()
	marker.mesh = BoxMesh.new()
	marker.mesh.size = Vector3(0.5, 0.1, 0.5)
	marker.position = Vector3(0, 0.25, 0)
	var mat := StandardMaterial3D.new()
	mat.albedo_color = Color(0.4, 0.3, 0.5, 0.6)
	mat.roughness = 0.9
	marker.material_override = mat
	add_child(marker)


func try_occupy() -> bool:
	if _occupied:
		return false
	_occupied = true
	return true


func vacate() -> void:
	_occupied = false


func get_sit_position() -> Vector3:
	return global_position + sit_offset


func get_sit_rotation() -> float:
	return sit_yaw
