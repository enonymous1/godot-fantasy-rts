## Headless tests for multiplayer sync — without real networking.
## Two main scenes act as host and client: the host builds a
## snapshot, the client applies it, and orders round-trip
## through _apply_order. Run with:
##   godot --headless --path . -s res://tests/test_multiplayer_sync.gd
## Prints PASS n/n or FAIL ... and quits with exit code 0/1.
extends SceneTree

var _passed: int = 0
var _failed: int = 0
var _checked: bool = false
var _host: Node2D = null
var _client: Node2D = null


func _init() -> void:
	var packed: PackedScene = load("res://scenes/main.tscn")
	_check(packed != null, "main scene loads")
	_host = packed.instantiate()
	root.add_child(_host)
	_client = packed.instantiate()
	root.add_child(_client)


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
	_host._start_single()
	_host.game_mode = "host"
	_host.my_faction = "human"
	_client.game_mode = "client"
	_client.my_faction = "orc"
	_client.started = true
	_client.hud.menu_panel.visible = false
	# Entity ids are unique and stable across the deterministic map.
	var host_ids: Dictionary = {}
	for u in _host.units:
		_check(not host_ids.has(u.id), "host unit ids are unique")
		host_ids[u.id] = true
	for b in _host.buildings:
		_check(not host_ids.has(b.id), "building ids do not collide with unit ids")
		host_ids[b.id] = true
	for u in _host.units:
		_check(_client._unit_by_id(u.id) != null, "client has the same unit id %d as host" % u.id)
	for b in _host.buildings:
		_check(_client._building_by_id(b.id) != null, "client has the same building id %d as host" % b.id)
	# Snapshot round-trip: move a host unit, damage it, snapshot, apply.
	var footman: RTSUnit = _host._spawn_unit("human", "footman", Vector2(1000, 1000))
	footman.hp = 42
	var snap: Dictionary = _host._build_snapshot()
	_check_eq(int((snap["res"]["human"] as Dictionary).get("gold", 0)), 400, "snapshot carries human gold")
	_client._apply_snapshot(snap)
	var mirror: RTSUnit = _client._unit_by_id(footman.id)
	_check(mirror != null, "client spawns the footman from the snapshot")
	_check_eq(mirror.hp, 42, "client mirror has the host hp")
	_check(mirror.position.distance_to(Vector2(1000, 1000)) < 1.0, "client mirror has the host position")
	_check_eq(_client.units.size(), _host.units.size(), "client unit count matches host after snapshot")
	_check_eq(_client.buildings.size(), _host.buildings.size(), "client building count matches host after snapshot")
	# Orders: a move order applied on the host moves the unit.
	var peasant: RTSUnit = null
	for u in _host.units:
		if u.faction == "human" and u.kind == "peasant":
			peasant = u
			break
	_host._apply_order({"type": "move", "unit_ids": [peasant.id], "x": 900.0, "y": 900.0})
	_check_eq(peasant.state, "move", "move order sets the unit state")
	_check(peasant.target_pos.distance_to(Vector2(864, 900)) < 1.0, "move order applies formation offset to the first unit")
	# Gather order.
	var mine: RTSResource = null
	for r in _host.resource_nodes:
		if r.kind == "gold":
			mine = r
			break
	_host._apply_order({"type": "gather", "unit_ids": [peasant.id], "target_id": mine.id})
	_check_eq(peasant.state, "gather_to", "gather order sets gather_to")
	_check(peasant.target_resource == mine, "gather order targets the gold mine")
	# Train order through the host path.
	var hall: RTSBuilding = null
	for b in _host.buildings:
		if b.faction == "human" and b.kind == "town_hall":
			hall = b
	_host._apply_train(hall.id, "peasant")
	_check_eq(hall.queue.size(), 1, "train order queues a peasant on the host")
	# Game-over sync: host ends the game, client applies the winner.
	_host._end_game("human")
	_check(_host.game_over and _host.victory, "host ends the game as winner")
	var snap2: Dictionary = _host._build_snapshot()
	_check_eq(String(snap2.get("winner", "")), "human", "snapshot carries the winner")
	_client._apply_snapshot(snap2)
	_check(_client.game_over, "client ends the game from the snapshot")
	_check(not _client.victory, "client (orcs) loses when humans win")
