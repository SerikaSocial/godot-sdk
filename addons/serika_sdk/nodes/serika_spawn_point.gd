@tool
@icon("res://addons/serika_sdk/icons/spawn_point.svg")
class_name SerikaSpawnPoint
extends Marker3D

## A place a player can spawn or respawn. Every world needs at least one.
## Purely declarative data — no behaviour. The scene builder reads these at build time.

## Optional group. Empty means "any player". Used for team/role spawns.
@export var spawn_group: String = ""

## Higher weight = more likely to be chosen when several spawns are eligible.
@export_range(0.0, 10.0, 0.1) var weight: float = 1.0

## If true this is the default fallback spawn when no group matches.
@export var is_default: bool = true

func _get_configuration_warnings() -> PackedStringArray:
	var warnings: PackedStringArray = []
	if weight <= 0.0:
		warnings.append("weight is 0 — this spawn point will never be chosen.")
	return warnings
