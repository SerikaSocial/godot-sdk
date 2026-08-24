## InteractionPoint — a generic interaction node. When the player is near and presses E,
## fires the `interacted` signal. Connect it to whatever logic you want (doors, sounds, etc).
@tool
class_name SerikaInteractionPoint
extends Area3D

signal interacted(interactor: Node3D)

@export var prompt: String = "Interact"
@export var interaction_range: float = 2.0


func _ready() -> void:
	if Engine.is_editor_hint():
		return
	var col := CollisionShape3D.new()
	col.shape = BoxShape3D.new()
	col.shape.size = Vector3(1, 1.5, 1)
	add_child(col)

	var marker := MeshInstance3D.new()
	marker.mesh = SphereMesh.new()
	marker.mesh.radius = 0.08
	marker.mesh.height = 0.16
	marker.position = Vector3(0, 1.0, 0)
	var mat := StandardMaterial3D.new()
	mat.emission = Color(0.6, 0.4, 0.9)
	mat.emission_energy_multiplier = 2.0
	mat.albedo_color = Color(0.6, 0.4, 0.9)
	marker.material_override = mat
	add_child(marker)


func trigger(interactor: Node3D) -> void:
	interacted.emit(interactor)
