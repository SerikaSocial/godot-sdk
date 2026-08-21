@tool
@icon("res://addons/serika_sdk/icons/pickup.svg")
class_name SerikaPickup
extends Area3D

## A grabbable / interactable object anchor. Ownership transfers to whoever grabs it,
## following the relay's object-ownership model. Declarative — no behaviour here.

## Stable id unique within the world. Used by the netcode to sync ownership of this object.
@export var pickup_id: String = ""

## Snap back to its origin when released.
@export var return_on_release: bool = true

## Seconds before an untouched, moved pickup returns home. 0 = never.
@export_range(0.0, 120.0, 0.5) var return_delay: float = 5.0

func _get_configuration_warnings() -> PackedStringArray:
	var warnings: PackedStringArray = []
	if pickup_id.strip_edges().is_empty():
		warnings.append("pickup_id is empty — needed to sync ownership across clients.")
	return warnings
