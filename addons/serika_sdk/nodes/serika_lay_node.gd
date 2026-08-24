## LayNode — a block the player can lie down on (bed/couch). Press E to lie, E again to stand.
@tool
class_name SerikaLayNode
extends Area3D

@export var lay_label: String = "Lay"
@export var lay_offset: Vector3 = Vector3(0, 0.3, 0)
@export var lay_yaw: float = 0.0

var _occupied: bool = false


func _ready() -> void:
	if Engine.is_editor_hint():
		return
	var col := CollisionShape3D.new()
	col.shape = BoxShape3D.new()
	col.shape.size = Vector3(1.0, 0.6, 2.0)
	add_child(col)

	var marker := MeshInstance3D.new()
	marker.mesh = BoxMesh.new()
	marker.mesh.size = Vector3(0.9, 0.15, 1.8)
	marker.position = Vector3(0, 0.15, 0)
	var mat := StandardMaterial3D.new()
	mat.albedo_color = Color(0.3, 0.35, 0.5, 0.6)
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


func get_lay_position() -> Vector3:
	return global_position + lay_offset


func get_lay_rotation() -> float:
	return lay_yaw
