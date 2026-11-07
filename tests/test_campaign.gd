## Headless tests for the campaign: mission data, mission
## start modifiers, and the destroy-the-hall win condition.
## Run with:
##   godot --headless --path . -s res://tests/test_campaign.gd
## Prints PASS n/n or FAIL ... and quits with exit code 0/1.
extends SceneTree

var _passed: int = 0
var _failed: int = 0
var _phase: int = 0
var _main: Node2D = null
var _m3: Node2D = null


func _init() -> void:
	var packed: PackedScene = load("res://scenes/main.tscn")
	_check(packed != null, "main scene loads")
	_main = packed.instantiate()
	root.add_child(_main)


func _process(_delta: float) -> bool:
	if _phase == 0:
		_phase = 1
		_run_phase_1()
		# Mission 3 needs its own scene; its _ready runs next frame.
		var packed: PackedScene = load("res://scenes/main.tscn")
		_m3 = packed.instantiate()
		root.add_child(_m3)
		# MainLoop._process returning true quits the loop, so
		# return false here to get a second frame.
		return false
	if _phase == 1:
		_phase = 2
		_run_phase_2()
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


func _run_phase_1() -> void:
	# Mission data.
	_check_eq(RTSCampaign.missions().size(), 3, "campaign has 3 missions")
	_check_eq(String(RTSCampaign.mission(0).get("win", "")), "destroy_all", "mission 1 is destroy-all")
	_check_eq(String(RTSCampaign.mission(1).get("win", "")), "destroy_hall", "mission 2 is destroy-the-hall")
	_check_eq(float(RTSCampaign.mission(2).get("ai_attack_interval", 0.0)), 50.0, "mission 3 attacks every 50s")
	_check_eq(int(RTSCampaign.mission(1).get("starting_gold", 0)), 200, "mission 2 starts with 200 gold")
	_check_eq(RTSCampaign.mission(99), {}, "out-of-range mission is empty")
	# Mission 2 start: half gold, AI interval applied.
	_main._start_campaign(1)
	_check_eq(_main.game_mode, "campaign", "campaign mode set")
	_check_eq(_main.mission_index, 1, "mission index 1")
	_check_eq(int((_main.res["human"] as Dictionary).get("gold", 0)), 200, "mission 2 starts with 200 gold")
	_check_eq(_main.ai_attack_interval, 90.0, "mission 2 AI interval is 90s")
	_check(_main.started, "campaign mission starts the game")
	# Destroying only the Orc Great Hall wins mission 2.
	var hall: RTSBuilding = null
	for b in _main.buildings:
		if b.faction == "orc" and b.kind == "great_hall":
			hall = b
	_check(hall != null, "orc great hall exists")
	_main._damage_building(hall, 99999)
	_main._check_end()
	_check(_main.game_over, "mission 2 ends when the hall falls")
	_check(_main.victory, "destroying the hall wins mission 2")
	# Progress: winning mission 2 unlocks mission 3 (saved).
	_check(RTSCampaign.load_unlocked() >= 3, "winning mission 2 unlocks mission 3")


func _run_phase_2() -> void:
	# Mission 3 start: extra barracks + grunts.
	_m3._start_campaign(2)
	_check_eq(_m3.ai_attack_interval, 50.0, "mission 3 AI interval is 50s")
	var barracks := 0
	var grunts := 0
	for b in _m3.buildings:
		if b.faction == "orc" and b.kind == "barracks":
			barracks += 1
	for u in _m3.units:
		if u.faction == "orc" and u.kind == "grunt":
			grunts += 1
	_check_eq(barracks, 1, "mission 3 orcs start with a barracks")
	_check_eq(grunts, 2, "mission 3 orcs start with 2 grunts")
