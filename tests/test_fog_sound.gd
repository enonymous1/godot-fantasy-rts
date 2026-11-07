## Headless tests for fog of war and procedural sound.
## Run with:
##   godot --headless --path . -s res://tests/test_fog_sound.gd
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
	# Fog: a cell at the human base is visible, the orc base is not.
	_main._recompute_fog()
	_check(_main.is_visible_at(Vector2(320, 1250)), "human base is visible at start")
	_check(_main.is_explored(Vector2(320, 1250)), "human base is explored at start")
	_check(not _main.is_visible_at(Vector2(2080, 350)), "orc base is not visible at start")
	_check(not _main.is_explored(Vector2(2080, 350)), "orc base is not explored at start")
	# Enemy units are hidden until seen.
	var orc_visible := false
	for u in _main.units:
		if u.faction == "orc" and u.visible:
			orc_visible = true
	_check(not orc_visible, "orc units hidden by fog at start")
	# Toggling fog off reveals everything.
	_main.fog_enabled = false
	_main._recompute_fog()
	_check(_main.is_visible_at(Vector2(2080, 350)), "fog off reveals the orc base")
	orc_visible = false
	for u in _main.units:
		if u.faction == "orc" and u.visible:
			orc_visible = true
	_check(orc_visible, "orc units visible with fog off")
	_main.fog_enabled = true
	_main._recompute_fog()
	# Fog layer and minimap exist and are wired to the game.
	_check(_main.fog_layer != null and _main.fog_layer.game == _main, "fog layer wired to game")
	_check(_main.minimap != null and _main.minimap.game == _main, "minimap wired to game")
	# Minimap click moves the camera (top-left of the minimap = map origin).
	_main.minimap._move_camera_to(Vector2(100, 66))
	_check(_main.camera.position.distance_to(Vector2(1200, 800)) < 10.0, "minimap click centers camera on the middle of the map")
	# Sound: synthesis produces a real stream, mute toggles.
	var mgr := RTSSoundManager.new()
	root.add_child(mgr)
	var stream := mgr.make_tone(440.0, 0.1, 0.4)
	_check_eq(stream.mix_rate, 22050, "tone mix rate 22050")
	_check(stream.data.size() == 2205 * 2, "0.1s 16-bit tone has 4410 bytes of data")
	_check_eq(stream.format, AudioStreamWAV.FORMAT_16_BITS, "tone is 16-bit")
	_check(not mgr.muted, "sound starts unmuted")
	_check(mgr.toggle_mute(), "mute toggles on")
	_check(mgr.muted, "muted flag set")
	_check(not mgr.toggle_mute(), "mute toggles off")
	_check(_main.sound != null, "main has a sound manager")
