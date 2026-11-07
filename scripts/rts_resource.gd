## A gatherable resource node: a gold mine or a tree.
class_name RTSResource
extends Node2D

var id: int = 0 # Stable network id, assigned by main.gd on spawn.
var kind: String = "gold" # gold | tree
var amount: int = 1500
var dead: bool = false


# Returns false for an unknown kind or a negative amount.
func setup(p_kind: String, pos: Vector2, p_amount: int) -> bool:
	if p_kind != "gold" and p_kind != "tree":
		push_error("RTSResource.setup: unknown resource kind '%s'" % p_kind)
		return false
	if p_amount < 0:
		push_error("RTSResource.setup: negative amount %d" % p_amount)
		return false
	kind = p_kind
	amount = p_amount
	position = pos
	return true


# No _process: a resource's appearance never changes (the amount is
# not drawn), so it is painted once when it enters the tree. The old
# per-frame queue_redraw rebuilt ~50 static canvas items 60x/sec.


func _draw() -> void:
	if dead:
		return
	if kind == "gold":
		draw_circle(Vector2.ZERO, 26.0, Color(0.95, 0.75, 0.15))
		draw_circle(Vector2.ZERO, 26.0, Color(0, 0, 0, 0.0))
		draw_arc(Vector2.ZERO, 26.0, 0.0, TAU, 24, Color(0.6, 0.45, 0.05), 3.0)
		draw_circle(Vector2(-8, -6), 6.0, Color(1.0, 0.9, 0.4))
		draw_circle(Vector2(9, 5), 6.0, Color(1.0, 0.9, 0.4))
		draw_circle(Vector2(2, -10), 4.0, Color(1.0, 0.9, 0.4))
	else:
		# Tree: trunk + canopy.
		draw_rect(Rect2(-3, 0, 6, 16), Color(0.45, 0.3, 0.12))
		draw_circle(Vector2(0, -10), 18.0, Color(0.2, 0.55, 0.25))
		draw_circle(Vector2(-10, -4), 12.0, Color(0.25, 0.62, 0.3))
		draw_circle(Vector2(10, -4), 12.0, Color(0.18, 0.5, 0.22))
