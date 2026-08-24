@tool
@icon("res://addons/serika_sdk/icons/portal.svg")
class_name SerikaWorldLoader
extends Node

## Loads a Serika world package or Godot scene from the CDN / disk and instantiates it.
## This is the runtime side of the SDK: creators use the validator/uploader, clients use this.

## World UUID to load. If empty, the loader tries to read from the parent world's metadata.
@export var world_id: String = ""

## Optional explicit URL. When empty the loader derives the URL from the configured API + world_id.
@export var download_url: String = ""

## Where the downloaded .skw/.tscn is cached locally (relative to user://).
@export var cache_dir: String = "user://worlds"

## If true, try the bundled dev path (project://3DWorlds) when the cache misses.
@export var allow_dev_path: bool = true

## Extension preference order for world assets.
@export var extensions: PackedStringArray = PackedStringArray(["skw", "tscn", "pck", "glb", "gltf"])

## Spawn point override. If zero, the loader searches for a SerikaSpawnPoint node.
@export var default_spawn: Vector3 = Vector3.ZERO

signal world_loaded(spawn: Vector3)
signal world_load_failed(error: String)

var _http: HTTPRequest
var _pending_path: String = ""

func _ready() -> void:
	if Engine.is_editor_hint():
		return
	if not world_id.is_empty() or not download_url.is_empty():
		_load_world()

## Public method to load a specific world by UUID.
func load_world(id: String, url: String = "") -> void:
	world_id = id
	if not url.is_empty():
		download_url = url
	_load_world()

func _load_world() -> void:
	# 1. Cached file.
	var cached := _find_cached_file()
	if cached != "":
		_instantiate(cached)
		return

	# 2. Dev path.
	if allow_dev_path:
		var dev := _find_dev_file()
		if dev != "":
			_instantiate(dev)
			return

	# 3. Download from URL / API.
	if download_url.is_empty():
		if world_id.is_empty():
			world_load_failed.emit("No world_id or download_url set")
			return
		download_url = _derive_url()

	if download_url.is_empty():
		world_load_failed.emit("Could not derive download URL")
		return

	_http = HTTPRequest.new()
	_http.request_completed.connect(_on_download_complete)
	add_child(_http)
	_http.request(download_url)

func _derive_url() -> String:
	var api := SerikaSdk.api_base()
	return "%s/v1/worlds/%s/download" % [api, world_id]

func _find_cached_file() -> String:
	for ext in extensions:
		var p := _cache_path(world_id, ext)
		if FileAccess.file_exists(p):
			return p
	return ""

func _find_dev_file() -> String:
	for ext in extensions:
		var p := "res://3DWorlds/SerikaWorlds/%s.%s" % [world_id, ext]
		if FileAccess.file_exists(p):
			return p
	return ""

func _cache_path(id: String, ext: String) -> String:
	var base := cache_dir
	if not base.ends_with("/"):
		base += "/"
	return base + id + "." + ext

func _on_download_complete(_result: int, code: int, _headers: PackedStringArray, body: PackedByteArray) -> void:
	if code != 200 or body.size() == 0:
		world_load_failed.emit("HTTP %d" % code)
		return

	DirAccess.make_dir_recursive_absolute(cache_dir)
	var path := _cache_path(world_id, "skw")
	var f := FileAccess.open(path, FileAccess.WRITE)
	if f == null:
		world_load_failed.emit("Could not write cache")
		return
	f.store_buffer(body)
	f.close()
	_instantiate(path)

func _instantiate(path: String) -> void:
	var ext := path.get_extension().to_lower()
	var root: Node = null

	match ext:
		"pck", "skw":
			if not ProjectSettings.load_resource_pack(path):
				world_load_failed.emit("Failed to load resource pack: %s" % path)
				return
			# Try default scene inside pack.
			root = _try_load_packed("res://%s.tscn" % world_id)
			if root == null:
				root = _try_load_packed("res://world.tscn")
		"tscn", "scn":
			root = _try_load_packed(path)
		"glb", "gltf":
			root = _load_gltf(path)
		_:
			world_load_failed.emit("Unknown extension: %s" % ext)
			return

	if root == null:
		world_load_failed.emit("Could not instantiate world from %s" % path)
		return

	root.name = "World[%s]" % world_id
	add_child(root)
	var spawn := _find_spawn(root)
	world_loaded.emit(spawn)

func _try_load_packed(path: String) -> Node:
	var packed := load(path) as PackedScene
	if packed == null:
		return null
	return packed.instantiate()

func _load_gltf(path: String) -> Node:
	var doc := GLTFDocument.new()
	var state := GLTFState.new()
	var err := doc.append_from_file(path, state)
	if err != OK:
		return null
	return doc.generate_scene(state)

func _find_spawn(root: Node) -> Vector3:
	var spawns := root.find_children("*", "SerikaSpawnPoint", false, false)
	for s in spawns:
		if s is Marker3D:
			return s.global_position
	# Fallback: any node with "spawn" in name.
	var nodes := root.find_children("*", "Node3D", false, false)
	for n in nodes:
		if "spawn" in n.name.to_lower() and n is Node3D:
			return n.global_position
	return default_spawn
