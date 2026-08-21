@tool
@icon("res://addons/serika_sdk/icons/audio_zone.svg")
class_name SerikaAudioZone
extends Area3D

## A volume that modifies voice/audio behaviour for players inside it — private chat
## rooms, quiet zones, reverb spaces. Declarative; the client enforces it.

## Voice heard by players outside the zone is attenuated by this factor (1 = private room).
@export_range(0.0, 1.0, 0.05) var outside_attenuation: float = 1.0

## Reverb preset applied to voices inside the zone.
@export_enum("None", "Room", "Hall", "Cave", "Outdoor") var reverb: int = 0

## If true, players in this zone only hear each other (isolated audio bubble).
@export var private: bool = false

func _get_configuration_warnings() -> PackedStringArray:
	var warnings: PackedStringArray = []
	var has_shape := false
	for child in get_children():
		if child is CollisionShape3D or child is CollisionPolygon3D:
			has_shape = true
			break
	if not has_shape:
		warnings.append("AudioZone has no CollisionShape3D — it covers no space.")
	return warnings
