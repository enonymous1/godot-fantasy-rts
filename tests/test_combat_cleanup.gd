## Headless tests for the dangling-target fix (REVIEW.md, finding 1):
## when a unit, building, or resource dies, every other unit that
## was targeting it must forget it — otherwise the next frame reads
## .dead on a freed instance and the attacker/gatherer/builder
## stalls in its state forever.
##
## This has to be phase-based: queue_free only actually frees at a
## frame boundary, and the old headless harness called _process in
## a loop with no boundary, which is exactly why the bug was never
## caught. Phase 0 kills across the frame; phase 1 (next frame)
## proves the victims are really freed, then steps the sim and
## asserts the survivors recovered.
## Run with:
##   godot --headless --path . -s res://tests/test_combat_cleanup.gd
## Prints PASS n/n or FAIL ... and quits with exit code 0/1.
extends SceneTree

var _passed: int = 0
var _failed: int = 0
var _phase: int = 0
var _main: Node2D = null
var _footman: RTSUnit = null
var _peasant: RTSUnit = null
var _footman2: RTSUnit = null
var _grunt: RTSUnit = null
var _tree: RTSResource = null
var _farm: RTSBuilding = null


func _init() -> void:
	var packed: PackedScene = load("res://scenes/main.tscn")
	_check(packed != null, "main scene loads")
	_main = packed.instantiate()
	root.add_child(_main)


func _process(_delta: float) -> bool:
	if _phase == 0:
		_phase = 1
		_run_phase_0()
		return false
	if _phase == 1:
		_phase = 2
		_run_phase_1()
		if _failed == 0:
			print("PASS " + str(_passed) + "/" + str(_passed))
			quit(0)
		else:
			print("FAIL " + str(_failed) + " of " + str(_passed + _failed) + " checks failed")
			quit(1)
	return false


func _check(condition: bool, test_name: String) -> void:
	if condition:
		_passed += 1
	else:
		_failed += 1
		print("FAIL: " + test_name)


func _check_eq(actual, expected, test_name: String) -> void:
	_check(actual == expected, test_name + " (got " + str(actual) + ", expected " + str(expected) + ")")


func _run_phase_0() -> void:
	_main._start_single()
	# Attacker with a live target.
	_footman = _main._spawn_unit("human", "footman", Vector2(1000, 1000))
	_grunt = _main._spawn_unit("orc", "grunt", Vector2(1010, 1000))
	_footman.state = "attack"
	_footman.target_unit = _grunt
	# Gatherer walking to a tree.
	_peasant = _main._spawn_unit("human", "peasant", Vector2(900, 900))
	_tree = null
	for r in _main.resource_nodes:
		if r.kind == "tree" and r.amount > 0:
			_tree = r
			break
	_check(_tree != null, "a tree exists to gather")
	_peasant.state = "gather_to"
	_peasant.target_resource = _tree
	# Second attacker on an Orc farm.
	_footman2 = _main._spawn_unit("human", "footman", Vector2(1500, 500))
	_farm = null
	for b in _main.buildings:
		if b.faction == "orc" and b.kind == "pig_farm":
			_farm = b
			break
	_check(_farm != null, "orc pig farm exists")
	_footman2.state = "attack"
	_footman2.target_building = _farm
	# Kill all three targets.
	_main._damage_unit(_grunt, 999)
	_main._remove_resource(_tree)
	_main._damage_building(_farm, 99999)
	# References are cleared at kill time, not lazily.
	_check(not _main.units.has(_grunt), "dead grunt leaves the unit list")
	_check(_footman.target_unit == null, "attacker forgets a dead unit at kill time")
	_check(_peasant.target_resource == null, "gatherer forgets a removed tree at kill time")
	_check(_footman2.target_building == null, "attacker forgets a dead building at kill time")


func _run_phase_1() -> void:
	# The frame boundary flushed the queue_free calls: the
	# victims are really gone now. If any of these is still
	# valid, this test is vacuous — the bug would be masked.
	_check(not is_instance_valid(_grunt), "grunt node is actually freed after the frame")
	_check(not is_instance_valid(_tree), "tree node is actually freed after the frame")
	_check(not is_instance_valid(_farm), "farm node is actually freed after the frame")
	# Step the sim: the survivors must recover to idle instead of
	# erroring on a freed instance and stalling in their state.
	_main._process(0.1)
	_check_eq(_footman.state, "idle", "attacker goes idle after its target dies")
	_check_eq(_peasant.state, "idle", "gatherer goes idle after its tree is removed")
	_check_eq(_footman2.state, "idle", "attacker goes idle after its building dies")
	_check(_footman.target_unit == null, "attacker target stays clear after the sim step")
	_check(_peasant.target_resource == null, "gatherer target stays clear after the sim step")
	_check(_footman2.target_building == null, "building target stays clear after the sim step")
