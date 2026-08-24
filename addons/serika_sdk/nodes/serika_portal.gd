@tool
@icon("res://addons/serika_sdk/icons/portal.svg")
class_name SerikaPortal
extends Area3D

## A trigger volume that moves the player to another world or to a marker in this world.
## Declarative only — the client interprets it; the world ships no code.

enum Kind { WORLD, LOCAL }

## Routing mode for WORLD portals.
enum WorldMode {
	## Open the full world browser (default).
	PICKER,
	## Jump directly to target_world_id. No picker UI.
	DIRECT,
	## Open the world browser filtered to curated_world_ids.
	CURATED,
	## User-spawned invite portal (world rules must allow spawning).
	INVITE,
}

## WORLD = jump to another world by id; LOCAL = teleport within this world.
@export var kind: Kind = Kind.WORLD

## Target world id (UUID) when kind == WORLD.
@export var target_world_id: String = ""

## NodePath to a Marker3D / SerikaSpawnPoint when kind == LOCAL.
@export var target_marker: NodePath

## Require a confirmation prompt before travelling (recommended for WORLD portals).
@export var confirm: bool = true

## Routing mode when kind == WORLD (controls how the client handles the portal).
@export var world_mode: WorldMode = WorldMode.PICKER

## Curated list of world IDs for CURATED mode. The world browser will only show these.
@export var curated_world_ids: PackedStringArray = PackedStringArray()

func _get_configuration_warnings() -> PackedStringArray:
	var warnings: PackedStringArray = []
	if kind == Kind.WORLD and target_world_id.strip_edges().is_empty() and world_mode == WorldMode.DIRECT:
		warnings.append("world_mode is DIRECT but target_world_id is empty.")
	if kind == Kind.WORLD and world_mode == WorldMode.CURATED and curated_world_ids.is_empty():
		warnings.append("world_mode is CURATED but curated_world_ids is empty.")
	if kind == Kind.LOCAL and target_marker.is_empty():
		warnings.append("kind is LOCAL but target_marker is not set.")
	return warnings
