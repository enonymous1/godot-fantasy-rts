## A single RTS building. Visual only + state fields; the
## simulation (training queues, construction) lives in main.gd.
class_name RTSBuilding
extends Node2D

var id: int = 0 # Stable network id, assigned by main.gd on spawn.
var faction: String = "human"
var kind: String = "town_hall"
var hp: int = 1500
var max_hp: int = 1500
var queue: Array = [] # Array[String] of unit kinds to train
var queue_timer: float = 0.0
var rally_pos: Vector2 = Vector2.ZERO
var under_construction: bool = false
var build_progress: float = 0.0
var build_time: float = 20.0
var selected: bool = false
var dead: bool = false


func setup(p_faction: String, p_kind: String, pos: Vector2, p_under_construction: bool = false) -> void:
	faction = p_faction
	kind = p_kind
	position = pos
	rally_pos = pos + Vector2(90, 0)
	var st := RTSData.building_stats(kind)
	max_hp = int(st.get("hp", 400))
	hp = max_hp if not p_under_construction else 100
	build_time = float(st.get("build_time", 20.0))
	under_construction = p_under_construction
	build_progress = 0.0 if p_under_construction else build_time


func faction_color() -> Color:
	return Color(0.25, 0.5, 0.95) if faction == "human" else Color(0.45, 0.75, 0.25)


func size_px() -> Vector2:
	match kind:
		"town_hall", "great_hall":
			return Vector2(110, 90)
		"barracks":
			return Vector2(95, 75)
		"farm", "pig_farm":
			return Vector2(60, 50)
	return Vector2(70, 60)


func _process(_delta: float) -> void:
	queue_redraw()


func _draw() -> void:
	if dead:
		return
	var s := size_px()
	var rect := Rect2(-s.x / 2.0, -s.y / 2.0, s.x, s.y)
	# Selection ring.
	if selected:
		draw_rect(rect.grow(6.0), Color(0.2, 0.9, 0.2), false, 2.0)
	# Body.
	var body := Color(0.75, 0.68, 0.55)
	if kind == "barracks":
		body = Color(0.6, 0.55, 0.5)
	elif kind == "farm" or kind == "pig_farm":
		body = Color(0.85, 0.7, 0.45)
	draw_rect(rect, body)
	draw_rect(rect, Color(0.2, 0.2, 0.2), false, 2.0)
	# Roof.
	var roof := PackedVector2Array([
		Vector2(-s.x / 2.0 - 4, -s.y / 2.0),
		Vector2(0, -s.y / 2.0 - 22.0),
		Vector2(s.x / 2.0 + 4, -s.y / 2.0),
	])
	draw_colored_polygon(roof, faction_color())
	# Door.
	draw_rect(Rect2(-8, s.y / 2.0 - 22, 16, 22), Color(0.25, 0.18, 0.1))
	# Construction scaffolding.
	if under_construction:
		var frac := clampf(build_progress / maxf(build_time, 0.01), 0.0, 1.0)
		draw_rect(rect, Color(1, 1, 1, 0.35))
		draw_rect(Rect2(-s.x / 2.0, -s.y / 2.0 - 12, s.x * frac, 5.0), Color(1.0, 0.85, 0.2))
	# Health bar.
	if hp < max_hp:
		var w := s.x
		var frac2 := clampf(float(hp) / float(maxi(max_hp, 1)), 0.0, 1.0)
		draw_rect(Rect2(-w / 2.0, -s.y / 2.0 - 32.0, w, 5.0), Color(0.1, 0.1, 0.1))
		draw_rect(Rect2(-w / 2.0, -s.y / 2.0 - 32.0, w * frac2, 5.0), Color(0.2, 0.85, 0.25))
	# Training progress.
	if not queue.is_empty():
		draw_rect(Rect2(-s.x / 2.0, s.y / 2.0 + 6, s.x, 4.0), Color(0.1, 0.1, 0.1))
		var total := float(RTSData.unit_stats(String(queue[0])).get("train_time", 10.0))
		var frac3 := 1.0 - clampf(queue_timer / maxf(total, 0.01), 0.0, 1.0)
		draw_rect(Rect2(-s.x / 2.0, s.y / 2.0 + 6, s.x * frac3, 4.0), Color(0.3, 0.7, 1.0))
