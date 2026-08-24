@tool
@icon("res://addons/serika_sdk/icons/pickup.svg")
class_name SerikaPhysicsProp
extends RigidBody3D

## A networked physics prop that any player can pick up, move, and throw.
##
## Uses Godot's RigidBody3D for local physics. When a player grabs the prop, it switches
## to kinematic mode and broadcasts its transform via the relay's ObjectSync channel.
## Ownership is implicit: whoever last sent an ObjectSync for this prop's id owns it.
##
## Place this node in the world scene, assign a mesh as a child, and set the net_id.
## The game client's PhysicsProp (C#) mirrors this behaviour at runtime.

## Stable network id (0-65535). Must be unique within the world.
@export_range(0, 65535, 1) var net_id: int = 0

## Display name shown in the interaction prompt.
@export var prop_name: String = "Pick up"

## Interaction range in metres.
@export_range(0.5, 10.0, 0.1) var interaction_range: float = 2.0

## If true, the prop syncs over the network. Single-player worlds can leave this off.
@export var networked: bool = true

## Snap back to its origin when released.
@export var return_on_release: bool = false

## Seconds before an untouched, moved prop returns home. 0 = never.
@export_range(0.0, 120.0, 0.5) var return_delay: float = 5.0

func _get_configuration_warnings() -> PackedStringArray:
	var warnings: PackedStringArray = []
	if net_id == 0:
		warnings.append("net_id is 0 — set a unique id for network sync.")
	if get_child_count() == 0:
		warnings.append("No children — add a MeshInstance3D and CollisionShape3D as children.")
	return warnings
