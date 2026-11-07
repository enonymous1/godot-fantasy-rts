## A single RTS unit. Visual only + state fields; the simulation
## (movement, gathering, combat) lives in main.gd so the rules
## stay in one place. All art is procedural shapes.
class_name RTSUnit
extends Node2D

var id: int = 0 # Stable network id, assigned by main.gd on spawn.
var faction: String = "human"
var kind: String = "peasant"
var hp: int = 30
var max_hp: int = 30
var speed: float = 95.0
var damage: int = 3
var attack_range: float = 20.0
var attack_cooldown: float = 1.0
var sight: float = 200.0
var state: String = "idle" # idle / move / attack_move / gather_to / gathering / return / build / building / attack
var target_pos: Vector2 = Vector2.ZERO
var target_unit: RTSUnit = null
var target_building: RTSBuilding = null
var target_resource: RTSResource = null
var carry_type: String = ""
var carry_amount: int = 0
var gather_timer: float = 0.0
var attack_timer: float = 0.0
var selected: bool = false
var dead: bool = false


# Returns false for an unknown kind instead of silently building a
# default-stat unit: the caller (main.gd) rejects the spawn and logs
# it, so a bad kind is a loud error, not a mystery unit on the map.
func setup(p_faction: String, p_kind: String, pos: Vector2) -> bool:
	var st := RTSData.unit_stats(p_kind)
	if st.is_empty():
		push_error("RTSUnit.setup: unknown unit kind '%s'" % p_kind)
		return false
	faction = p_faction
	kind = p_kind
	position = pos
	max_hp = int(st.get("hp", 30))
	hp = max_hp
	speed = float(st.get("speed", 90.0))
	damage = int(st.get("damage", 3))
	attack_range = float(st.get("range", 20.0))
	attack_cooldown = float(st.get("cooldown", 1.0))
	sight = float(st.get("sight", 200.0))
	return true


func faction_color() -> Color:
	return Color(0.25, 0.5, 0.95) if faction == "human" else Color(0.45, 0.75, 0.25)


func body_color() -> Color:
	match kind:
		"peasant":
			return Color(0.85, 0.75, 0.55)
		"peon":
			return Color(0.35, 0.65, 0.25)
		"footman":
			return Color(0.55, 0.65, 0.85)
		"grunt":
			return Color(0.25, 0.5, 0.2)
		"archer":
			return Color(0.35, 0.75, 0.45)
		"spearman":
			return Color(0.65, 0.45, 0.2)
	return Color(0.8, 0.8, 0.8)


# Drawing is in local space, so moving does not need a redraw.
# Only appearance changes do: HP, selection, and the carry dot.
# Redrawing every frame rebuilt the same canvas item 60 times a
# second for every unit on the map.
var _draw_key := ""


func _process(_delta: float) -> void:
	var key := "%d|%s|%s|%d" % [hp, str(selected), carry_type, carry_amount]
	if key != _draw_key:
		_draw_key = key
		queue_redraw()


func _draw() -> void:
	if dead:
		return
	# Selection ring.
	if selected:
		draw_arc(Vector2.ZERO, 20.0, 0.0, TAU, 24, Color(0.2, 0.9, 0.2), 2.0)
	# Shadow / body.
	draw_circle(Vector2(0, 3), 13.0, Color(0, 0, 0, 0.25))
	draw_circle(Vector2.ZERO, 13.0, body_color())
	draw_arc(Vector2.ZERO, 13.0, 0.0, TAU, 24, faction_color(), 2.5)
	# Face / weapon hint.
	if RTSData.is_ranged(kind):
		draw_line(Vector2(8, -8), Vector2(16, -16), Color(0.4, 0.25, 0.1), 3.0)
	elif not RTSData.is_worker(kind):
		draw_line(Vector2(10, 0), Vector2(18, 0), Color(0.85, 0.85, 0.9), 3.0)
	else:
		draw_circle(Vector2(0, -4), 4.0, Color(0.9, 0.85, 0.7))
	# Carry indicator.
	if carry_amount > 0:
		var c := Color(1.0, 0.85, 0.2) if carry_type == "gold" else Color(0.5, 0.35, 0.15)
		draw_circle(Vector2(0, -16), 5.0, c)
	# Health bar.
	if hp < max_hp:
		var w := 28.0
		var frac := clampf(float(hp) / float(maxi(max_hp, 1)), 0.0, 1.0)
		draw_rect(Rect2(-w / 2.0, -26.0, w, 4.0), Color(0.1, 0.1, 0.1))
		draw_rect(Rect2(-w / 2.0, -26.0, w * frac, 4.0), Color(0.2, 0.85, 0.25))
