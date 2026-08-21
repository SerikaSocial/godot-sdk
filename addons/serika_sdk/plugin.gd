@tool
extends EditorPlugin

## Serika SDK editor plugin. Registers the authoring nodes (via class_name, so they appear
## in Create Node) and adds a dock with Validate / Package / Upload actions plus a local
## test-harness launcher.

const Dock := preload("res://addons/serika_sdk/ui/dock.gd")

var _dock: Control

func _enter_tree() -> void:
	SerikaSdk.ensure_settings()

	# Custom types give the nodes their icons and a friendly entry in the Create dialog even
	# on editor versions that don't surface @icon for script classes.
	add_custom_type("SerikaSpawnPoint", "Marker3D",
		preload("res://addons/serika_sdk/nodes/serika_spawn_point.gd"),
		preload("res://addons/serika_sdk/icons/spawn_point.svg"))
	add_custom_type("SerikaPortal", "Area3D",
		preload("res://addons/serika_sdk/nodes/serika_portal.gd"),
		preload("res://addons/serika_sdk/icons/portal.svg"))
	add_custom_type("SerikaPickup", "Area3D",
		preload("res://addons/serika_sdk/nodes/serika_pickup.gd"),
		preload("res://addons/serika_sdk/icons/pickup.svg"))
	add_custom_type("SerikaAudioZone", "Area3D",
		preload("res://addons/serika_sdk/nodes/serika_audio_zone.gd"),
		preload("res://addons/serika_sdk/icons/audio_zone.svg"))
	add_custom_type("SerikaMirror", "MeshInstance3D",
		preload("res://addons/serika_sdk/nodes/serika_mirror.gd"),
		preload("res://addons/serika_sdk/icons/mirror.svg"))

	_dock = Dock.new()
	_dock.plugin = self
	add_control_to_dock(DOCK_SLOT_RIGHT_UL, _dock)

func _exit_tree() -> void:
	if _dock:
		remove_control_from_docks(_dock)
		_dock.queue_free()
		_dock = null
	remove_custom_type("SerikaSpawnPoint")
	remove_custom_type("SerikaPortal")
	remove_custom_type("SerikaPickup")
	remove_custom_type("SerikaAudioZone")
	remove_custom_type("SerikaMirror")
