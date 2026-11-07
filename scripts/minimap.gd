## Clickable minimap. Draws the whole world scaled down: gold
## mines, trees, buildings and units, plus a white rect for the
## camera viewport. Click / drag moves the camera. Enemy dots
## only show where the player's fog of war currently sees them.
class_name RTSMinimap
extends Control

var game: Node2D = null


# 10 Hz is plenty for a 200x133 overview: units move a few pixels
# per tick at this scale, and the old per-frame redraw rebuilt the
# whole minimap 60 times a second.
var _redraw_timer := 0.0


func _process(delta: float) -> void:
	_redraw_timer -= delta
	if _redraw_timer <= 0.0:
		_redraw_timer = 0.1
		queue_redraw()


func _gui_input(event: InputEvent) -> void:
	if game == null:
		return
	if event is InputEventMouseButton:
		var mb := event as InputEventMouseButton
		if mb.button_index == MOUSE_BUTTON_LEFT and mb.pressed:
			_move_camera_to(mb.position)
	elif event is InputEventMouseMotion:
		var mm := event as InputEventMouseMotion
		if mm.button_mask & MOUSE_BUTTON_MASK_LEFT:
			_move_camera_to(mm.position)


func _move_camera_to(local_pos: Vector2) -> void:
	var frac := (local_pos / size).clamp(Vector2.ZERO, Vector2.ONE)
	var world := Vector2(frac.x * RTSData.WORLD_SIZE.x, frac.y * RTSData.WORLD_SIZE.y)
	game.get("camera").position = world.clamp(Vector2.ZERO, RTSData.WORLD_SIZE)


func _draw() -> void:
	if game == null:
		return
	var s := size / RTSData.WORLD_SIZE
	draw_rect(Rect2(Vector2.ZERO, size), Color(0.2, 0.35, 0.18))
	draw_rect(Rect2(Vector2.ZERO, size), Color(0.6, 0.6, 0.6), false, 1.0)
	# Resources (gold if explored, trees if explored).
	for r in game.get("resource_nodes"):
		if bool(r.get("dead")):
			continue
		if not bool(game.call("is_explored", r.position)):
			continue
		var p := Vector2(r.position.x * s.x, r.position.y * s.y)
		var c := Color(1.0, 0.85, 0.2) if String(r.get("kind")) == "gold" else Color(0.25, 0.6, 0.25)
		draw_circle(p, 2.5, c)
	# Buildings.
	for b in game.get("buildings"):
		if bool(b.get("dead")):
			continue
		if String(b.get("faction")) != String(game.get("my_faction")) and not bool(game.call("is_visible_at", b.position)):
			continue
		var p := Vector2(b.position.x * s.x, b.position.y * s.y)
		var c := Color(0.25, 0.5, 0.95) if String(b.get("faction")) == "human" else Color(0.45, 0.75, 0.25)
		draw_rect(Rect2(p - Vector2(3, 3), Vector2(6, 6)), c)
	# Units.
	for u in game.get("units"):
		if bool(u.get("dead")):
			continue
		if String(u.get("faction")) != String(game.get("my_faction")) and not bool(game.call("is_visible_at", u.position)):
			continue
		var p := Vector2(u.position.x * s.x, u.position.y * s.y)
		var c := Color(0.4, 0.65, 1.0) if String(u.get("faction")) == "human" else Color(0.6, 0.9, 0.35)
		draw_circle(p, 2.0, c)
	# Camera viewport.
	var cam: Camera2D = game.get("camera")
	if cam != null:
		var vp := game.get_viewport_rect().size / cam.zoom
		var top_left := Vector2((cam.position.x - vp.x / 2.0) * s.x, (cam.position.y - vp.y / 2.0) * s.y)
		draw_rect(Rect2(top_left, Vector2(vp.x * s.x, vp.y * s.y)), Color(1, 1, 1), false, 1.0)
