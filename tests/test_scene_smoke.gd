## Headless scene smoke test: instantiates the main scene and
## exercises spawning, ordering and combat helpers without
## rendering (headless has no rasterizer). Run with:
##   godot --headless --path . -s res://tests/test_scene_smoke.gd
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
	_check(_main.started, "game starts after picking Single Battle")
	_check(_main.get("units") != null and _main.units.size() == 6, "6 starting units (3 peasants + 3 peons)")
	_check(_main.get("buildings") != null and _main.buildings.size() == 4, "4 starting buildings (2 halls + 2 farms)")
	_check(_main.resource_nodes.size() >= 40, "gold mines + tree patches spawn")
	_check_eq(_main.supply_used("human"), 3, "human supply used 3 at start")
	_check_eq(_main.supply_max("human"), 9, "human supply max 9 at start")
	_check_eq(int((_main.res["human"] as Dictionary).get("gold", 0)), 400, "human starts with 400 gold")

	# Spawning + combat helpers.
	var footman: RTSUnit = _main._spawn_unit("human", "footman", Vector2(500, 500))
	_check_eq(footman.hp, 60, "spawned footman hp 60")
	var grunt: RTSUnit = _main._spawn_unit("orc", "grunt", Vector2(520, 500))
	_main._damage_unit(grunt, 10)
	_check_eq(grunt.hp, 60, "damage reduces hp")
	_main._damage_unit(grunt, 100)
	_check(grunt.dead, "lethal damage kills unit")
	_check(not _main.units.has(grunt), "dead unit removed from list")

	# Training queue: select the human town hall, train a peasant.
	var hall: RTSBuilding = null
	for b in _main.buildings:
		if b.faction == "human" and b.kind == "town_hall":
			hall = b
	_check(hall != null, "human town hall exists")
	_main.selected_building = hall
	var before_gold := int((_main.res["human"] as Dictionary).get("gold", 0))
	_main._train_unit("peasant")
	_check_eq(hall.queue.size(), 1, "peasant queued in town hall")
	_check_eq(int((_main.res["human"] as Dictionary).get("gold", 0)), before_gold - 50, "training pays 50 gold")
	# Fast-forward the queue.
	hall.queue_timer = 0.01
	var count_before: int = _main.units.size()
	_main._update_buildings(0.02)
	_check_eq(_main.units.size(), count_before + 1, "finished training spawns a unit")

	# Gathering: order a peasant to a gold mine and step the sim.
	var peasant: RTSUnit = null
	for u in _main.units:
		if u.faction == "human" and u.kind == "peasant":
			peasant = u
			break
	_check(peasant != null, "a human peasant exists")
	var mine: RTSResource = null
	for r in _main.resource_nodes:
		if r.kind == "gold":
			mine = r
			break
	peasant.state = "gather_to"
	peasant.target_resource = mine
	# Teleport next to the mine, then step gathering.
	peasant.position = mine.position + Vector2(30, 0)
	_main._update_units(0.1)
	_check_eq(peasant.state, "gathering", "peasant starts gathering at the mine")
	peasant.gather_timer = 0.01
	_main._update_units(0.02)
	_check(peasant.carry_amount == 10 and peasant.state == "return", "peasant carries 10 gold home")
