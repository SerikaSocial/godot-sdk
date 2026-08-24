@tool
class_name SerikaFile
extends RefCounted

## Read/write .serikaworld and .serikavatar container files.
##
## Both formats are ZIP archives with a mandatory manifest.json header:
##
##   manifest.json          — metadata (name, version, author, description, custom data)
##   scene.tscn             — the Godot scene (world or avatar rig)
##   <arbitrary assets>     — textures, meshes, etc. referenced by the scene
##
## The manifest is a JSON object:
##   {
##     "format": "serikaworld" | "serikavatar",
##     "format_version": 1,
##     "name": "My World",
##     "version": "1.0.0",
##     "author": "creator name",
##     "description": "optional description",
##     "godot_version": "4.7",
##     "capacity": 32,           -- worlds only
##     "tags": ["hangout"],       -- worlds only
##     "allow_invite_portals": false,  -- worlds only, requires trust ≥5
##     "custom": {}               -- arbitrary creator-defined key/value pairs
##   }
##
## The SDK uploader exports these, the validator checks them, and the game client
## (or assetd build farm) loads them.

const FORMAT_WORLD := "serikaworld"
const FORMAT_AVATAR := "serikavatar"
const FORMAT_VERSION := 1
const MANIFEST_PATH := "manifest.json"

const EXT_WORLD := ".serikaworld"
const EXT_AVATAR := ".serikavatar"

class Manifest:
	var format: String
	var format_version: int
	var name: String
	var version: String
	var author: String
	var description: String
	var godot_version: String
	var capacity: int
	var tags: PackedStringArray
	var custom: Dictionary
	# World-only: allow users to spawn invite portals (requires trust ≥5, off by default).
	var allow_invite_portals: bool

	static func from_dict(d: Dictionary) -> Manifest:
		var m := Manifest.new()
		m.format = String(d.get("format", ""))
		m.format_version = int(d.get("format_version", 0))
		m.name = String(d.get("name", ""))
		m.version = String(d.get("version", "1.0.0"))
		m.author = String(d.get("author", ""))
		m.description = String(d.get("description", ""))
		m.godot_version = String(d.get("godot_version", "4.7"))
		m.capacity = int(d.get("capacity", 32))
		var tags_arr: Array = d.get("tags", [])
		m.tags = PackedStringArray(tags_arr)
		m.custom = d.get("custom", {})
		m.allow_invite_portals = bool(d.get("allow_invite_portals", false))
		return m

	func to_dict() -> Dictionary:
		var d := {
			"format": format,
			"format_version": SerikaFile.FORMAT_VERSION,
			"name": name,
			"version": version,
			"author": author,
			"description": description,
			"godot_version": godot_version,
			"custom": custom,
		}
		if format == SerikaFile.FORMAT_WORLD:
			d["capacity"] = capacity
			d["tags"] = tags
			d["allow_invite_portals"] = allow_invite_portals
		return d

	func to_json() -> String:
		return JSON.stringify(to_dict(), "  ")

## Write a .serikaworld or .serikavatar file from a source directory + manifest.
## Returns true on success.
static func write(out_path: String, source_dir: String, manifest: Manifest) -> bool:
	var dir_abs := ProjectSettings.globalize_path(source_dir)
	var writer := ZIPPacker.new()
	if writer.open(out_path) != OK:
		push_error("SerikaFile: could not open '%s' for writing" % out_path)
		return false

	# Manifest first so readers can peek at it without scanning the whole archive.
	var manifest_bytes := manifest.to_json().to_utf8_buffer()
	writer.start_file(MANIFEST_PATH)
	writer.write_file(manifest_bytes)
	writer.close_file()

	var count := _zip_dir(writer, dir_abs, "")
	writer.close()
	print("[SerikaFile] wrote %s (%d files + manifest)" % [out_path, count])
	return count >= 0

## Read the manifest from a .serikaworld or .serikavatar file without extracting.
## Returns null on failure.
static func read_manifest(path: String) -> Manifest:
	var reader := ZIPReader.new()
	if reader.open(path) != OK:
		push_error("SerikaFile: could not open '%s'" % path)
		return null
	var files := reader.get_files()
	if not files.has(MANIFEST_PATH):
		push_error("SerikaFile: no manifest.json in '%s'" % path)
		reader.close()
		return null
	var bytes := reader.read_file(MANIFEST_PATH)
	reader.close()
	var text := bytes.get_string_from_utf8()
	var parsed = JSON.parse_string(text)
	if typeof(parsed) != TYPE_DICTIONARY:
		push_error("SerikaFile: manifest.json is not valid JSON")
		return null
	return Manifest.from_dict(parsed)

## Extract all files from a .serikaworld or .serikavatar to a directory.
## Returns the list of extracted file paths, or empty on failure.
static func extract(path: String, dest_dir: String) -> PackedStringArray:
	var reader := ZIPReader.new()
	if reader.open(path) != OK:
		push_error("SerikaFile: could not open '%s'" % path)
		return PackedStringArray()

	var dest_abs := ProjectSettings.globalize_path(dest_dir)
	DirAccess.make_dir_recursive_absolute(dest_abs)

	var files := reader.get_files()
	var extracted: PackedStringArray = []
	for f in files:
		if f == MANIFEST_PATH:
			continue
		var out_path := dest_abs.path_join(f)
		var subdir := out_path.get_base_dir()
		DirAccess.make_dir_recursive_absolute(subdir)
		var bytes := reader.read_file(f)
		var fa := FileAccess.open(out_path, FileAccess.WRITE)
		if fa == null:
			push_error("SerikaFile: could not write '%s'" % out_path)
			continue
		fa.store_buffer(bytes)
		fa.close()
		extracted.append(f)
	reader.close()
	print("[SerikaFile] extracted %d files from %s" % [extracted.size(), path])
	return extracted

## Detect the format from a file extension. Returns FORMAT_WORLD, FORMAT_AVATAR, or "".
static func detect_format(path: String) -> String:
	var ext := path.get_extension().to_lower()
	match ext:
		"serikaworld":
			return FORMAT_WORLD
		"serikavatar":
			return FORMAT_AVATAR
		"":
			return ""
	return ""

## Create a default manifest for a world.
static func make_world_manifest(world_name: String, creator: String = "") -> Manifest:
	var m := Manifest.new()
	m.format = FORMAT_WORLD
	m.format_version = FORMAT_VERSION
	m.name = world_name
	m.version = "1.0.0"
	m.author = creator
	m.description = ""
	m.godot_version = "4.7"
	m.capacity = 32
	m.tags = PackedStringArray()
	m.custom = {}
	return m

## Create a default manifest for an avatar.
static func make_avatar_manifest(avatar_name: String, creator: String = "") -> Manifest:
	var m := Manifest.new()
	m.format = FORMAT_AVATAR
	m.format_version = FORMAT_VERSION
	m.name = avatar_name
	m.version = "1.0.0"
	m.author = creator
	m.description = ""
	m.godot_version = "4.7"
	m.capacity = 0
	m.tags = PackedStringArray()
	m.custom = {}
	return m

static func _zip_dir(writer: ZIPPacker, abs_dir: String, rel_prefix: String) -> int:
	var count := 0
	var d := DirAccess.open(abs_dir)
	if d == null:
		return 0
	d.list_dir_begin()
	var name := d.get_next()
	while name != "":
		if name.begins_with(".") or name == "node_modules":
			name = d.get_next()
			continue
		var abs_child := abs_dir.path_join(name)
		var rel_child := name if rel_prefix.is_empty() else rel_prefix.path_join(name)
		if d.current_is_dir():
			count += _zip_dir(writer, abs_child, rel_child)
		else:
			var bytes := FileAccess.get_file_as_bytes(abs_child)
			writer.start_file(rel_child)
			writer.write_file(bytes)
			writer.close_file()
			count += 1
		name = d.get_next()
	d.list_dir_end()
	return count
