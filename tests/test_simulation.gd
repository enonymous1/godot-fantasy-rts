## Headless 120-second simulation: orders the human peasants to
## gather, then steps the main scene's _process in 0.1s slices
## and checks the economy, AI build-up and combat actually run.
## Run with:
##   godot --headless --path . -s res://tests/test_simulation.gd
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


func _run_all() -> void:
	_main._start_single()
	# Order human peasants: two to the nearest gold mine, one to a tree.
	var mine: RTSResource = null
	var tree: RTSResource = null
	for r in _main.resource_nodes:
		if r.kind == "gold" and mine == null:
			mine = r
		if r.kind == "tree" and tree == null:
			tree = r
	var i := 0
	for u in _main.units:
		if u.faction == "human" and u.kind == "peasant":
			u.state = "gather_to"
			u.target_resource = mine if i < 2 else tree
			i += 1
	var start_gold: int = int((_main.res["human"] as Dictionary).get("gold", 0))
	# Step 120 simulated seconds.
	for step in 1200:
		_main._process(0.1)
		if _main.game_over:
			break
	var end_gold: int = int((_main.res["human"] as Dictionary).get("gold", 0))
	_check(end_gold > start_gold, "human gold grows from gathering (start %d, end %d)" % [start_gold, end_gold])
	var orc_buildings := 0
	var orc_barracks := false
	for b in _main.buildings:
		if b.faction == "orc" and not b.dead:
			orc_buildings += 1
			if b.kind == "barracks":
				orc_barracks = true
	_check(orc_buildings >= 3, "orc AI built up to %d buildings (hall + farm + barracks)" % orc_buildings)
	_check(orc_barracks, "orc AI built a barracks within 120s")
	var orc_units := 0
	for u in _main.units:
		if u.faction == "orc" and not u.dead:
			orc_units += 1
	_check(orc_units >= 4, "orc AI has %d units after 120s" % orc_units)
	_check(not _main.game_over, "game is not over after 120s of sim")
	# Combat: two footmen focusing one grunt should kill it over
	# time (a lone footman loses 1v1 — grunt has more HP/damage).
	var grunt: RTSUnit = _main._spawn_unit("orc", "grunt", Vector2(1010, 1000))
	for k in 2:
		var footman: RTSUnit = _main._spawn_unit("human", "footman", Vector2(1000 + k * 30, 1000))
		footman.state = "attack"
		footman.target_unit = grunt
	for step in 300:
		_main._process(0.1)
		if grunt.dead:
			break
	_check(grunt.dead, "two footmen kill a grunt in combat sim")
