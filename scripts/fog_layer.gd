## Fog-of-war overlay. Draws one rect per map cell: fully black
## where the player has never looked, dim where explored but not
## currently visible. The visibility grids live on the main game
## node (game.fog_visible / game.fog_explored); this node only draws.
class_name RTSFogLayer
extends Node2D

var game: Node2D = null


func _ready() -> void:
	z_index = 50


func _process(_delta: float) -> void:
	queue_redraw()


func _draw() -> void:
	if game == null or not bool(game.get("started")):
		return
	if not bool(game.get("fog_enabled")):
		return
	var cell: float = float(RTSData.TILE)
	var cols: int = int(RTSData.WORLD_SIZE.x / cell)
	var rows: int = int(RTSData.WORLD_SIZE.y / cell)
	var visible: Array = game.get("fog_visible")
	var explored: Array = game.get("fog_explored")
	if visible.size() != cols * rows or explored.size() != cols * rows:
		return
	for cy in rows:
		for cx in cols:
			var i := cy * cols + cx
			if bool(visible[i]):
				continue
			var rect := Rect2(cx * cell, cy * cell, cell, cell)
			if bool(explored[i]):
				draw_rect(rect, Color(0, 0, 0, 0.45))
			else:
				draw_rect(rect, Color(0, 0, 0, 0.92))
