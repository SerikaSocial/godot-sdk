@tool
@icon("res://addons/serika_sdk/icons/mirror.svg")
class_name SerikaMirror
extends MeshInstance3D

## A mirror surface. The client renders avatars reflected in it. Because mirrors are
## expensive, the SDK surfaces the cost knobs directly and the validator enforces limits.

## Resolution of the mirror render target.
@export_enum("512", "1024", "2048") var resolution: int = 1

## Only render reflections when a player is within this distance (metres). 0 = always.
@export_range(0.0, 50.0, 0.5) var activation_distance: float = 10.0

## Render other players in the mirror (off = only reflect the local player, much cheaper).
@export var reflect_others: bool = true

func _get_configuration_warnings() -> PackedStringArray:
	var warnings: PackedStringArray = []
	if mesh == null:
		warnings.append("Mirror has no mesh assigned — nothing to reflect onto.")
	if resolution == 2 and reflect_others:
		warnings.append("2048 + reflect_others is very expensive; consider 1024 for social spaces.")
	return warnings
