extends SceneTree

## Headless validator tests. Run with:
##   godot --headless --path godot-sdk --script res://tests/run_tests.gd
## Exits non-zero if any assertion fails, so it drops straight into CI.

var _failures := 0

func _init() -> void:
	_test_demo_world_passes()
	_test_missing_spawn_fails()
	_test_attached_script_fails()
	_test_forbidden_node_fails()
	_test_over_budget_fails()

	if _failures == 0:
		print("\nAll SDK validator tests passed.")
		quit(0)
	else:
		printerr("\n%d test(s) failed." % _failures)
		quit(1)

func _check(name: String, cond: bool) -> void:
	if cond:
		print("  ✓ ", name)
	else:
		printerr("  ✗ ", name)
		_failures += 1

func _test_demo_world_passes() -> void:
	print("demo world validates:")
	var scene := load("res://demo/world.tscn") as PackedScene
	var root := scene.instantiate()
	var report := SerikaValidator.new().validate(root)
	_check("demo world passes validation", report.ok())
	_check("demo world found >=1 spawn point", int(report.stats.get("spawn_points", 0)) >= 1)
	root.free()

func _test_missing_spawn_fails() -> void:
	print("world with no spawn point fails:")
	var root := Node3D.new()
	var mesh := MeshInstance3D.new()
	root.add_child(mesh)
	var report := SerikaValidator.new().validate(root)
	_check("no-spawn world is rejected", not report.ok())
	root.free()

func _test_attached_script_fails() -> void:
	print("node with attached script fails:")
	var root := Node3D.new()
	var spawn := SerikaSpawnPoint.new()
	root.add_child(spawn)
	var evil := Node3D.new()
	var s := GDScript.new()
	s.source_code = "extends Node3D\nfunc _ready():\n\tpass\n"
	s.reload()
	evil.set_script(s)
	root.add_child(evil)
	var report := SerikaValidator.new().validate(root)
	_check("attached script is rejected", not report.ok())
	root.free()

func _test_forbidden_node_fails() -> void:
	print("forbidden node type fails:")
	var root := Node3D.new()
	root.add_child(SerikaSpawnPoint.new())
	root.add_child(Camera3D.new()) # forbidden
	var report := SerikaValidator.new().validate(root)
	_check("Camera3D is rejected", not report.ok())
	root.free()

func _test_over_budget_fails() -> void:
	print("over-budget spawn count fails:")
	var root := Node3D.new()
	for i in range(70): # budget is 64
		root.add_child(SerikaSpawnPoint.new())
	var report := SerikaValidator.new().validate(root)
	_check("too many spawn points is rejected", not report.ok())
	root.free()
