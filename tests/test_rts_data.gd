## Headless tests for RTSData (pure game data). Run with:
##   godot --headless --path . -s res://tests/test_rts_data.gd
## Prints PASS n/n or FAIL ... and quits with exit code 0/1.
extends SceneTree

var _passed: int = 0
var _failed: int = 0


func _init() -> void:
	_run_all()
	if _failed == 0:
		print("PASS " + str(_passed) + "/" + str(_passed))
		quit(0)
	else:
		print("FAIL " + str(_failed) + " of " + str(_passed + _failed) + " checks failed")
		quit(1)


func _check(condition: bool, test_name: String) -> void:
	if condition:
		_passed += 1
	else:
		_failed += 1
		print("FAIL: " + test_name)


func _check_eq(actual, expected, test_name: String) -> void:
	_check(actual == expected, test_name + " (got " + str(actual) + ", expected " + str(expected) + ")")


func _run_all() -> void:
	# Unit stats.
	_check_eq(int(RTSData.unit_stats("footman").get("hp", 0)), 60, "footman hp 60")
	_check_eq(int(RTSData.unit_stats("grunt").get("hp", 0)), 70, "grunt hp 70")
	_check_eq(int(RTSData.unit_stats("archer").get("hp", 0)), 35, "archer hp 35")
	_check(RTSData.unit_stats("archer").get("range", 0.0) > RTSData.unit_stats("footman").get("range", 0.0), "archer outranges footman")
	_check_eq(RTSData.unit_stats("nope"), {}, "unknown unit is empty dict")
	# Costs.
	_check_eq(int(RTSData.unit_cost("peasant").get("gold", 0)), 50, "peasant costs 50 gold")
	_check_eq(int(RTSData.unit_cost("footman").get("wood", 0)), 20, "footman costs 20 wood")
	_check_eq(int(RTSData.unit_cost("archer").get("supply", 0)), 1, "archer costs 1 supply")
	# Buildings.
	_check_eq(int(RTSData.building_stats("town_hall").get("hp", 0)), 1500, "town hall hp 1500")
	_check_eq(int(RTSData.building_stats("farm").get("supply", 0)), 4, "farm gives 4 supply")
	_check_eq(int(RTSData.building_cost("barracks").get("gold", 0)), 150, "barracks costs 150 gold")
	_check_eq(int(RTSData.building_cost("barracks").get("wood", 0)), 100, "barracks costs 100 wood")
	# Faction helpers.
	_check_eq(RTSData.worker_kind("human"), "peasant", "human worker is peasant")
	_check_eq(RTSData.worker_kind("orc"), "peon", "orc worker is peon")
	_check_eq(RTSData.hall_kind("orc"), "great_hall", "orc hall is great hall")
	_check_eq(RTSData.melee_kind("human"), "footman", "human melee is footman")
	_check_eq(RTSData.ranged_kind("orc"), "spearman", "orc ranged is spearman")
	_check(RTSData.is_worker("peon") and not RTSData.is_worker("grunt"), "is_worker only for workers")
	_check(RTSData.is_ranged("archer") and not RTSData.is_ranged("footman"), "is_ranged only for ranged")
	# Economy.
	var r := RTSData.starting_resources()
	_check_eq(int(r.get("gold", 0)), 400, "starting gold 400")
	_check_eq(int(r.get("wood", 0)), 200, "starting wood 200")
	_check(RTSData.can_afford(r, {"gold": 50, "wood": 0}), "can afford peasant at start")
	_check(not RTSData.can_afford(r, {"gold": 9999, "wood": 0}), "cannot afford 9999 gold")
	RTSData.pay(r, {"gold": 50, "wood": 20})
	_check_eq(int(r.get("gold", 0)), 350, "pay deducts gold")
	_check_eq(int(r.get("wood", 0)), 180, "pay deducts wood")
	# Supply from buildings.
	var fake_buildings: Array = [{"kind": "town_hall"}, {"kind": "farm"}, {"kind": "barracks"}]
	_check_eq(RTSData.supply_max(fake_buildings), 9, "hall 5 + farm 4 = 9 supply")
	_check_eq(RTSData.GOLD_CARRY, 10, "gold carry 10")
	_check_eq(RTSData.WOOD_CARRY, 10, "wood carry 10")
