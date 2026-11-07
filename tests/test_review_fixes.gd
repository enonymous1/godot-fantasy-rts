## Headless tests for the staff-review pass (REVIEW.md, v0.3.0):
## fail-loud spawns, train/place validation, the multiplayer trust
## boundary, snapshot validation, and the Orc (client) player being
## able to select units and train. Run with:
##   godot --headless --path . -s res://tests/test_review_fixes.gd
## Prints PASS n/n or FAIL ... and quits with exit code 0/1.
extends SceneTree

var _passed: int = 0
var _failed: int = 0
var _checked: bool = false
var _main: Node2D = null


func _init() -> void:
	var packed: PackedScene = load("res://scenes/main.tscn")
	_check(packed != null, "main scene loads")
	_main = packed.instantiate()
	root.add_child(_main)


func _process(_delta: float) -> bool:
	if _checked:
		return true
	_checked = true
	_run_all()
	if _failed == 0:
		print("PASS " + str(_passed) + "/" + str(_passed))
		quit(0)
	else:
		print("FAIL " + str(_failed) + " of " + str(_passed + _failed) + " checks failed")
		quit(1)
	return true


func _check(condition: bool, test_name: String) -> void:
	if condition:
		_passed += 1
	else:
		_failed += 1
		print("FAIL: " + test_name)


func _check_eq(actual, expected, test_name: String) -> void:
	_check(actual == expected, test_name + " (got " + str(actual) + ", expected " + str(expected) + ")")


func _run_all() -> void:
	_main._start_single()
	# Unknown kinds fail loudly instead of silently spawning a
	# default-stat entity (REVIEW.md, finding 4).
	_check(_main._spawn_unit("human", "bogus", Vector2(500, 500)) == null, "unknown unit kind refuses to spawn")
	_check(_main._spawn_building("human", "bogus", Vector2(500, 500)) == null, "unknown building kind refuses to spawn")
	_check(_main._spawn_resource("bogus", Vector2(500, 500), 100) == null, "unknown resource kind refuses to spawn")
	# Train validation: a Town Hall trains workers only, and only
	# for its own faction (findings 3 and 4).
	var hall: RTSBuilding = null
	for b in _main.buildings:
		if b.faction == "human" and b.kind == "town_hall":
			hall = b
	_main._apply_train(hall.id, "grunt")
	_check_eq(hall.queue.size(), 0, "town hall cannot train a grunt")
	_main._apply_train(hall.id, "bogus")
	_check_eq(hall.queue.size(), 0, "unknown kind cannot be trained")
	_main._apply_train(hall.id, "peasant", "orc")
	_check_eq(hall.queue.size(), 0, "orc sender cannot train at a human hall")
	_main._apply_train(hall.id, "peasant", "human")
	_check_eq(hall.queue.size(), 1, "human sender trains a peasant at its own hall")
	# Order validation: a remote order only moves the sender's own
	# units (finding 3).
	var peasant: RTSUnit = null
	for u in _main.units:
		if u.faction == "human" and u.kind == "peasant":
			peasant = u
			break
	_main._apply_order({"type": "move", "unit_ids": [peasant.id], "x": 900.0, "y": 900.0}, "orc")
	_check_eq(peasant.state, "idle", "orc order does not move a human peasant")
	_main._apply_order({"type": "move", "unit_ids": [peasant.id], "x": 900.0, "y": 900.0}, "human")
	_check_eq(peasant.state, "move", "human order moves a human peasant")
	# Place validation: halls are not placeable (finding 3).
	var buildings_before: int = _main.buildings.size()
	_main._apply_place("town_hall", Vector2(500, 500), peasant.id)
	_check_eq(_main.buildings.size(), buildings_before, "a town hall cannot be placed by a worker")
	# Corrupt snapshot: bad entries are skipped, good ones land
	# (finding 5).
	var snap: Dictionary = _main._build_snapshot()
	(snap["units"] as Array).append("not a dictionary")
	(snap["units"] as Array).append({"id": 9999, "kind": "bogus", "faction": "human", "x": 0.0, "y": 0.0, "hp": 10})
	var units_before: int = _main.units.size()
	_main._apply_snapshot(snap)
	_check_eq(_main.units.size(), units_before, "corrupt snapshot entries are skipped, good units kept")
	# The Orc player can select their own units and train
	# (finding 2). Switch to the client faction and click an Orc.
	_main.my_faction = "orc"
	var peon: RTSUnit = _main._spawn_unit("orc", "peon", Vector2(600, 600))
	_main.drag_start_world = Vector2(600, 600)
	_main._finish_selection(Vector2(600, 600))
	_check(_main.selected_units.has(peon), "orc player can click-select an orc peon")
	_check_eq(_main.hud.command_box.get_child_count(), 3, "orc worker shows farm + barracks + stop buttons")
	# Orc barracks panel trains Orc kinds, not human ones.
	var barracks: RTSBuilding = _main._spawn_building("orc", "barracks", Vector2(700, 700))
	_main.selected_building = barracks
	barracks.selected = true
	_main._refresh_command_panel()
	_check_eq(_main.hud.command_box.get_child_count(), 2, "orc barracks shows two train buttons")
	_main.hud._on_command_pressed("train_melee")
	_check_eq(barracks.queue.size(), 1, "orc barracks queues a unit from the panel")
	_check_eq(String(barracks.queue[0]), "grunt", "orc barracks trains a grunt, not a footman")
