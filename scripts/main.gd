## Fantasy RTS — Godot (v0.3.0).
## A playable 2D RTS in the style of classic 1990s
## real-time strategy games: gold + lumber economy,
## worker gather-and-return, farms for supply, barracks
## troops, and an Orc AI that builds up and attacks in waves.
## All art is original procedural shapes and all sound is
## synthesized; no third-party assets are used.
##
## Architecture: this file is the game controller and
## composition root — map, economy, simulation, AI, fog,
## camera, input, and multiplayer. All UI lives in
## scripts/hud.gd (RTSHud); all tuning lives in
## scripts/rts_data.gd (RTSData). See REVIEW.md for the
## staff-review pass that split the HUD out (v0.3.0).
##
## Modes (pick one on the start menu):
##   Single Battle — you are the Humans, the Orcs are AI.
##   Campaign — three missions with briefings and objectives.
##   Host / Join — 2-player LAN: host plays Humans, the
##     joining player plays Orcs. Host-authoritative: the host
##     simulates, the client sends orders and gets snapshots.
##
## Controls:
##   Left-click / drag: select units or a building
##   Right-click: move, attack, gather gold / chop wood,
##     or set a building rally point
##   WASD / arrows / screen edge: pan camera, wheel: zoom
##   Click the minimap to jump the camera
##   M: mute sound, F: toggle fog of war
##   Bottom panel: train units, build farms / barracks
##   A worker must build a placed building (it walks over
##   and construction progresses while it is there).
extends Node2D

const PLAYER_FACTION := "human"
const AI_FACTION := "orc"
const MP_PORT := 7777

# Camera / UI constants (game tuning lives in RTSData).
const CAMERA_SPEED := 550.0
const CAMERA_ZOOM_MIN := 0.5
const CAMERA_ZOOM_MAX := 1.5
const EDGE_MARGIN := 12.0
const TOP_BAR_HEIGHT := 36.0
const BOTTOM_PANEL_HEIGHT := 110.0

var camera: Camera2D
var units: Array[RTSUnit] = []
var buildings: Array[RTSBuilding] = []
var resource_nodes: Array[RTSResource] = []
var selected_units: Array[RTSUnit] = []
var selected_building: RTSBuilding = null

var res: Dictionary = {
	"human": {"gold": 400, "wood": 200},
	"orc": {"gold": 400, "wood": 200},
}
var game_over: bool = false
var victory: bool = false
var elapsed: float = 0.0
var winner_faction: String = ""

# Start / mode state. The game does not simulate until a mode
# is picked on the start menu (started == true).
var started: bool = false
var game_mode: String = "single" # single | campaign | host | client
var my_faction: String = "human"
var next_id: int = 1

# Fog of war (computed from my_faction's sight).
var fog_enabled: bool = true
var fog_visible: Array = []
var fog_explored: Array = []
var fog_timer: float = 0.0
var fog_layer: RTSFogLayer = null

# Sound + minimap.
var sound: RTSSoundManager = null
var minimap: RTSMinimap = null

# Campaign.
var mission: Dictionary = {}
var mission_index: int = -1
var campaign_unlocked: int = 1
var ai_attack_interval: float = 80.0

# Multiplayer (host-authoritative). ENet (UDP) is the default;
# WebSocket (TCP) is the fallback — it also works in the web
# export, where raw UDP is unavailable.
var remote_peer_id: int = 0
var snapshot_timer: float = 0.0
var use_websocket: bool = false
var _snapshot_logged: bool = false

var placing_kind: String = ""
var dragging: bool = false
var drag_start_screen: Vector2 = Vector2.ZERO
var drag_start_world: Vector2 = Vector2.ZERO

var ai_timer: float = 0.0
var ai_attack_timer: float = 75.0
var ai_stage: int = 0

# UI lives in scripts/hud.gd (RTSHud). This node only calls
# into it (hud.set_message / hud.refresh_command_panel /
# hud.update_hud / hud.show_end) and keeps game flow here.
var hud: RTSHud = null


func _ready() -> void:
	campaign_unlocked = RTSCampaign.load_unlocked()
	_build_camera()
	_build_map()
	_init_fog()
	_build_hud()
	_build_fog_layer()
	_build_minimap()
	_build_sound()
	multiplayer.peer_connected.connect(_on_peer_connected)
	multiplayer.peer_disconnected.connect(_on_peer_disconnected)
	_set_message("Pick a mode on the menu to start.")
	camera.position = Vector2(350, 1150)
	# Resume a campaign "Next mission" across the reload.
	var pending_cfg := ConfigFile.new()
	if pending_cfg.load(RTSCampaign.SAVE_PATH) == OK:
		var pending := int(pending_cfg.get_value("campaign", "pending_mission", -1))
		if pending >= 0 and pending < RTSCampaign.missions().size():
			pending_cfg.set_value("campaign", "pending_mission", -1)
			pending_cfg.save(RTSCampaign.SAVE_PATH)
			_start_campaign(pending)
	# Headless / quick-launch args: `godot --path . -- --host`
	# or `godot --path . -- --join=192.168.1.10`.
	for arg in OS.get_cmdline_user_args():
		if arg == "--host":
			_start_host()
		elif arg == "--host-ws":
			use_websocket = true
			_start_host()
		elif String(arg).begins_with("--join="):
			_start_join(String(arg).trim_prefix("--join="))
		elif String(arg).begins_with("--join-ws="):
			use_websocket = true
			_start_join(String(arg).trim_prefix("--join-ws="))


func _init_fog() -> void:
	var cols := int(RTSData.WORLD_SIZE.x / RTSData.TILE)
	var rows := int(RTSData.WORLD_SIZE.y / RTSData.TILE)
	fog_visible.resize(cols * rows)
	fog_explored.resize(cols * rows)
	fog_visible.fill(false)
	fog_explored.fill(false)


func _build_fog_layer() -> void:
	fog_layer = RTSFogLayer.new()
	fog_layer.game = self
	add_child(fog_layer)


func _build_hud() -> void:
	hud = RTSHud.new()
	hud.game = self
	add_child(hud)


func _build_minimap() -> void:
	minimap = RTSMinimap.new()
	minimap.game = self
	minimap.set_anchors_preset(Control.PRESET_BOTTOM_RIGHT)
	minimap.offset_left = -212
	minimap.offset_top = -245
	minimap.offset_right = -12
	minimap.offset_bottom = -112
	hud.add_child(minimap)


# Thin wrappers so the rest of the controller keeps calling
# _set_message / _refresh_command_panel without knowing the HUD
# owns the labels and buttons.
func _set_message(text: String) -> void:
	if hud:
		hud.set_message(text)


func _refresh_command_panel() -> void:
	if hud:
		hud.refresh_command_panel()


func _build_sound() -> void:
	sound = RTSSoundManager.new()
	sound.name = "Sound"
	add_child(sound)


func _on_next_mission_pressed() -> void:
	# Remember the next mission across the scene reload, then start it.
	var cfg := ConfigFile.new()
	cfg.load(RTSCampaign.SAVE_PATH)
	cfg.set_value("campaign", "pending_mission", mission_index + 1)
	cfg.save(RTSCampaign.SAVE_PATH)
	get_tree().reload_current_scene()


func _hide_menu() -> void:
	if hud:
		hud.hide_menu()
	started = true
	_recompute_fog()
	_set_message("Order a Peasant to the Gold Mine (right-click it), and another to chop wood. Build a Barracks to train Footmen.")
	if my_faction == "orc":
		camera.position = Vector2(2050, 350)
		_set_message("You are the Orcs. Order a Peon to the Gold Mine, and another to chop wood.")


func _start_single() -> void:
	game_mode = "single"
	my_faction = "human"
	mission = {}
	mission_index = -1
	_hide_menu()
	if sound:
		sound.play("click")


func _start_campaign(index: int) -> void:
	game_mode = "campaign"
	my_faction = "human"
	mission_index = index
	mission = RTSCampaign.mission(index)
	ai_attack_interval = float(mission.get("ai_attack_interval", 80.0))
	var gold := int(mission.get("starting_gold", 400))
	var wood := int(mission.get("starting_wood", 200))
	(res["human"] as Dictionary)["gold"] = gold
	(res["human"] as Dictionary)["wood"] = wood
	if bool(mission.get("orc_extra_barracks", false)):
		_spawn_building("orc", "barracks", Vector2(1900, 500))
		for i in int(mission.get("orc_extra_grunts", 0)):
			_spawn_unit("orc", "grunt", Vector2(1950 + i * 50, 620))
	# Stage 2 skips the AI's build stages (farm, then barracks):
	# mission 3 starts the Orcs entrenched, so they go straight
	# to training and attacking.
	ai_stage = 2
	_hide_menu()
	_set_message(String(mission.get("briefing", "")))
	if sound:
		sound.play("click")


func _make_peer() -> MultiplayerPeer:
	if use_websocket:
		return WebSocketMultiplayerPeer.new()
	return ENetMultiplayerPeer.new()


func _start_host() -> void:
	game_mode = "host"
	my_faction = "human"
	mission = {}
	var peer: MultiplayerPeer = _make_peer()
	var err: Error = OK
	if peer is WebSocketMultiplayerPeer:
		err = (peer as WebSocketMultiplayerPeer).create_server(MP_PORT)
	else:
		err = (peer as ENetMultiplayerPeer).create_server(MP_PORT, 2)
	print("MP: create_server port %d (%s) err=%d" % [MP_PORT, "websocket" if use_websocket else "enet", err])
	if err != OK:
		_set_message("Could not host on port %d (error %d)." % [MP_PORT, err])
		return
	multiplayer.multiplayer_peer = peer
	print("MP: hosting as server, unique_id=%d" % multiplayer.get_unique_id())
	_hide_menu()
	_set_message("Hosting on port %d — waiting for player 2 (Orcs) to join…" % MP_PORT)


func _start_join(ip: String) -> void:
	game_mode = "client"
	my_faction = "orc"
	mission = {}
	var peer: MultiplayerPeer = _make_peer()
	var err: Error = OK
	if peer is WebSocketMultiplayerPeer:
		err = (peer as WebSocketMultiplayerPeer).create_client("ws://%s:%d" % [ip, MP_PORT])
	else:
		err = (peer as ENetMultiplayerPeer).create_client(ip, MP_PORT)
	print("MP: create_client %s:%d (%s) err=%d" % [ip, MP_PORT, "websocket" if use_websocket else "enet", err])
	if err != OK:
		_set_message("Could not connect to %s (error %d)." % [ip, err])
		return
	multiplayer.multiplayer_peer = peer
	_hide_menu()
	_set_message("Connecting to %s…" % ip)


func _on_peer_connected(id: int) -> void:
	remote_peer_id = id
	print("MP: peer %d connected (server=%s)" % [id, str(multiplayer.is_server())])
	if multiplayer.is_server():
		_set_message("Player 2 joined! They play the Orcs.")
		_send_snapshot()
	else:
		_set_message("Connected! You play the Orcs — orders go to the host.")


func _on_peer_disconnected(id: int) -> void:
	print("MP: peer %d disconnected" % id)
	if id == remote_peer_id:
		remote_peer_id = 0
		_set_message("The other player disconnected.")


func _build_camera() -> void:
	camera = Camera2D.new()
	camera.name = "Camera"
	camera.zoom = Vector2(0.85, 0.85)
	add_child(camera)
	camera.make_current()


func _build_map() -> void:
	# Human base (south-west).
	_spawn_building(PLAYER_FACTION, "town_hall", Vector2(320, 1250))
	_spawn_building(PLAYER_FACTION, "farm", Vector2(480, 1250))
	for i in 3:
		_spawn_unit(PLAYER_FACTION, "peasant", Vector2(320 + i * 50, 1360))
	# Orc base (north-east).
	_spawn_building(AI_FACTION, "great_hall", Vector2(2080, 350))
	_spawn_building(AI_FACTION, "pig_farm", Vector2(1920, 350))
	for i in 3:
		_spawn_unit(AI_FACTION, "peon", Vector2(2080 - i * 50, 240))
	# Gold mines: one per base, one contested in the middle.
	_spawn_resource("gold", Vector2(320, 1020), 1500)
	_spawn_resource("gold", Vector2(2080, 580), 1500)
	_spawn_resource("gold", Vector2(1200, 800), 1200)
	# Tree patches.
	_make_tree_patch(Vector2(850, 650), 10)
	_make_tree_patch(Vector2(1550, 950), 10)
	_make_tree_patch(Vector2(1150, 300), 8)
	_make_tree_patch(Vector2(1250, 1300), 8)
	_make_tree_patch(Vector2(600, 500), 6)
	_make_tree_patch(Vector2(1800, 1100), 6)
	# Close lumber for each base, so early wood income is not a
	# cross-map walk (the Orc AI was starved for wood without this).
	_make_tree_patch(Vector2(600, 950), 7)
	_make_tree_patch(Vector2(1850, 650), 7)


func _make_tree_patch(center: Vector2, count: int) -> void:
	var rng := RandomNumberGenerator.new()
	rng.seed = int(center.x) * 31 + int(center.y)
	for i in count:
		var pos := center + Vector2(rng.randf_range(-110, 110), rng.randf_range(-80, 80))
		pos.x = clampf(pos.x, 80, RTSData.WORLD_SIZE.x - 80)
		pos.y = clampf(pos.y, 80, RTSData.WORLD_SIZE.y - 80)
		_spawn_resource("tree", pos, 100)


func _next_entity_id(p_id: int = -1) -> int:
	if p_id >= 0:
		next_id = maxi(next_id, p_id + 1)
		return p_id
	var id := next_id
	next_id += 1
	return id


# Spawn helpers. They return null (and push_error) for an unknown
# kind instead of silently creating a default-stat entity — a bad
# kind is a loud error at the call site, not a mystery unit on the
# map. Callers must null-check the result.
func _spawn_unit(faction: String, kind: String, pos: Vector2, p_id: int = -1) -> RTSUnit:
	var u := RTSUnit.new()
	if not u.setup(faction, kind, pos):
		push_error("main._spawn_unit: refusing unknown unit kind '%s'" % kind)
		u.free()
		return null
	u.id = _next_entity_id(p_id)
	add_child(u)
	units.append(u)
	return u


func _spawn_building(faction: String, kind: String, pos: Vector2, under_construction: bool = false, p_id: int = -1) -> RTSBuilding:
	var b := RTSBuilding.new()
	if not b.setup(faction, kind, pos, under_construction):
		push_error("main._spawn_building: refusing unknown building kind '%s'" % kind)
		b.free()
		return null
	b.id = _next_entity_id(p_id)
	add_child(b)
	buildings.append(b)
	return b


func _spawn_resource(kind: String, pos: Vector2, amount: int, p_id: int = -1) -> RTSResource:
	var r := RTSResource.new()
	if not r.setup(kind, pos, amount):
		push_error("main._spawn_resource: refusing resource kind '%s' amount %d" % [kind, amount])
		r.free()
		return null
	r.id = _next_entity_id(p_id)
	add_child(r)
	resource_nodes.append(r)
	return r


func _unit_by_id(id: int) -> RTSUnit:
	for u in units:
		if not u.dead and u.id == id:
			return u
	return null


func _building_by_id(id: int) -> RTSBuilding:
	for b in buildings:
		if not b.dead and b.id == id:
			return b
	return null


func _resource_by_id(id: int) -> RTSResource:
	for r in resource_nodes:
		if not r.dead and r.id == id:
			return r
	return null


# ---------------------------------------------------------------- UI
# The UI lives in scripts/hud.gd (RTSHud): top bar, message line,
# bottom command panel, selection rectangle, end panel, and the
# start menu. This file only keeps game flow (restart / next
# mission) and the thin _set_message / _refresh_command_panel
# wrappers near _build_hud above.

func _on_restart_pressed() -> void:
	get_tree().reload_current_scene()


# ---------------------------------------------------------------- Input

func _unhandled_input(event: InputEvent) -> void:
	if game_over or not started:
		return
	if event is InputEventKey:
		var k := event as InputEventKey
		if k.pressed and not k.echo:
			if k.keycode == KEY_M and sound != null:
				if hud:
					hud.set_sound_label(sound.toggle_mute())
			elif k.keycode == KEY_F:
				fog_enabled = not fog_enabled
				_recompute_fog()
				_set_message("Fog of war " + ("on." if fog_enabled else "off."))
		return
	if event is InputEventMouseButton:
		var mb := event as InputEventMouseButton
		if mb.button_index == MOUSE_BUTTON_WHEEL_UP and mb.pressed:
			camera.zoom = (camera.zoom * 1.1).clamp(Vector2(0.5, 0.5), Vector2(1.5, 1.5))
		elif mb.button_index == MOUSE_BUTTON_WHEEL_DOWN and mb.pressed:
			camera.zoom = (camera.zoom / 1.1).clamp(Vector2(0.5, 0.5), Vector2(1.5, 1.5))
		elif mb.button_index == MOUSE_BUTTON_LEFT and mb.pressed:
			if placing_kind != "":
				_try_place(get_global_mouse_position())
			else:
				dragging = true
				drag_start_screen = mb.position
				drag_start_world = get_global_mouse_position()
		elif mb.button_index == MOUSE_BUTTON_LEFT and not mb.pressed and dragging:
			dragging = false
			if hud:
				hud.selection_rect.visible = false
			_finish_selection(get_global_mouse_position())
		elif mb.button_index == MOUSE_BUTTON_RIGHT and mb.pressed:
			if placing_kind != "":
				placing_kind = ""
				_set_message("Placement cancelled.")
			else:
				_order_right_click(get_global_mouse_position())


func _finish_selection(world_pos: Vector2) -> void:
	_clear_selection()
	var rect := Rect2(
		Vector2(minf(drag_start_world.x, world_pos.x), minf(drag_start_world.y, world_pos.y)),
		Vector2(absf(world_pos.x - drag_start_world.x), absf(world_pos.y - drag_start_world.y)))
	# Selection is by my_faction, not the hardcoded PLAYER_FACTION:
	# in client mode the player is the Orcs, and the old code never
	# selected an Orc unit (see REVIEW.md, finding 2).
	if rect.size.x > 12 and rect.size.y > 12:
		for u in units:
			if not u.dead and u.faction == my_faction and rect.has_point(u.position):
				_select_unit(u)
	else:
		# Single click: nearest friendly unit, else enemy unit, else building.
		var best: RTSUnit = null
		var best_d := 30.0
		for u in units:
			if u.dead:
				continue
			var d := u.position.distance_to(world_pos)
			if d < best_d and (best == null or u.faction == my_faction):
				best = u
				best_d = d
		if best != null and best.faction == my_faction:
			_select_unit(best)
		else:
			var bb: RTSBuilding = null
			var bd := 60.0
			for b in buildings:
				if b.dead:
					continue
				var d := b.position.distance_to(world_pos)
				if d < bd:
					bb = b
					bd = d
			if bb != null:
				selected_building = bb
				bb.selected = true
	if sound and (not selected_units.is_empty() or selected_building != null):
		sound.play("click")
	_refresh_command_panel()


func _clear_selection() -> void:
	for u in selected_units:
		u.selected = false
	selected_units.clear()
	if selected_building != null:
		selected_building.selected = false
	selected_building = null


func _select_unit(u: RTSUnit) -> void:
	u.selected = true
	selected_units.append(u)


func _order_right_click(world_pos: Vector2) -> void:
	# Rally point for a selected building.
	if selected_building != null and selected_building.faction == my_faction:
		if game_mode == "client":
			rpc_id(1, "_rpc_order", {"type": "rally", "building_id": selected_building.id, "x": world_pos.x, "y": world_pos.y})
		else:
			selected_building.rally_pos = world_pos
		_set_message("Rally point set.")
		return
	if selected_units.is_empty():
		return
	var ids: Array = []
	for u in selected_units:
		ids.append(u.id)
	# Attack an enemy?
	var enemy_unit := _nearest_enemy_unit(world_pos, 35.0)
	var enemy_building := _nearest_enemy_building(world_pos, 60.0)
	if enemy_unit != null:
		_issue_order({"type": "attack_unit", "unit_ids": ids, "target_id": enemy_unit.id})
		if sound:
			sound.play("attack")
		return
	if enemy_building != null:
		_issue_order({"type": "attack_building", "unit_ids": ids, "target_id": enemy_building.id})
		if sound:
			sound.play("attack")
		return
	# Gather / chop.
	var node := _nearest_resource(world_pos, 45.0)
	if node != null:
		var worker_ids: Array = []
		for u in selected_units:
			if RTSData.is_worker(u.kind):
				worker_ids.append(u.id)
		if not worker_ids.is_empty():
			_issue_order({"type": "gather", "unit_ids": worker_ids, "target_id": node.id})
			_set_message("Gathering %s." % ("gold" if node.kind == "gold" else "wood"))
			if sound:
				sound.play("order")
			return
	# Otherwise move (formation offsets so units do not stack).
	_issue_order({"type": "move", "unit_ids": ids, "x": world_pos.x, "y": world_pos.y})
	if sound:
		sound.play("order")


func _issue_order(order: Dictionary) -> void:
	if game_mode == "client":
		rpc_id(1, "_rpc_order", order)
		return
	_apply_order(order)


# Numbers arriving in an order may come from a network peer, so they
# are read through _num: only real numbers are accepted, anything
# else falls back to the default instead of erroring on a bad cast.
static func _num(v: Variant, fallback: float) -> float:
	if v is int or v is float:
		return float(v)
	return fallback


# sender_faction is the faction of the peer that sent this order
# ("" = local / trusted: no filtering). A remote order only ever
# applies to the sender's own units and buildings — the old code
# let any peer order either side's army (see REVIEW.md, finding 3).
func _apply_order(order: Dictionary, sender_faction: String = "") -> void:
	var ids: Array = order.get("unit_ids", [])
	var i := 0
	for id in ids:
		if not (id is int or id is float):
			continue
		var u := _unit_by_id(int(id))
		if u == null:
			continue
		if sender_faction != "" and u.faction != sender_faction:
			continue
		match String(order.get("type", "")):
			"move":
				var offset := Vector2((i % 3) * 36 - 36, (i / 3) * 36)
				u.state = "move"
				u.target_pos = Vector2(_num(order.get("x", 0.0), 0.0), _num(order.get("y", 0.0), 0.0)) + offset
				u.target_unit = null
				u.target_building = null
				u.target_resource = null
			"attack_unit":
				u.state = "attack"
				u.target_unit = _unit_by_id(int(_num(order.get("target_id", -1), -1.0)))
				u.target_building = null
				u.target_resource = null
			"attack_building":
				u.state = "attack"
				u.target_unit = null
				u.target_building = _building_by_id(int(_num(order.get("target_id", -1), -1.0)))
				u.target_resource = null
			"gather":
				u.state = "gather_to"
				u.target_resource = _resource_by_id(int(_num(order.get("target_id", -1), -1.0)))
				u.target_unit = null
				u.target_building = null
			"rally":
				pass
		i += 1
	if String(order.get("type", "")) == "rally":
		var b := _building_by_id(int(_num(order.get("building_id", -1), -1.0)))
		if b != null and (sender_faction == "" or b.faction == sender_faction):
			b.rally_pos = Vector2(_num(order.get("x", 0.0), 0.0), _num(order.get("y", 0.0), 0.0))


func _try_place(world_pos: Vector2) -> void:
	var kind := placing_kind
	placing_kind = ""
	var worker: RTSUnit = null
	for u in selected_units:
		if RTSData.is_worker(u.kind):
			worker = u
			break
	if worker == null:
		_set_message("Select a Peasant first, then place the building.")
		return
	if game_mode == "client":
		rpc_id(1, "_rpc_place", kind, world_pos.x, world_pos.y, worker.id)
		return
	_apply_place(kind, world_pos, worker.id)


func _apply_place(kind: String, world_pos: Vector2, worker_id: int, sender_faction: String = "") -> void:
	var worker := _unit_by_id(worker_id)
	if worker == null:
		return
	if sender_faction != "" and worker.faction != sender_faction:
		return
	# Only farms and barracks are placeable, and only known kinds:
	# the old code accepted "town_hall" at cost 0 — a free hall.
	if not RTSData.is_placeable(kind):
		push_error("main._apply_place: kind '%s' is not placeable" % kind)
		return
	var faction := worker.faction
	var cost: Dictionary = RTSData.building_cost(kind)
	var faction_res: Dictionary = res[faction]
	if not RTSData.can_afford(faction_res, cost):
		_set_message("Not enough resources for a %s." % String(RTSData.building_stats(kind).get("name", "?")))
		return
	RTSData.pay(faction_res, cost)
	var pos := world_pos.clamp(Vector2(80, 80), RTSData.WORLD_SIZE - Vector2(80, 80))
	var b := _spawn_building(faction, kind, pos, true)
	if b == null:
		return
	worker.state = "build"
	worker.target_building = b
	worker.target_pos = pos
	_set_message("Peasant is building a %s." % String(RTSData.building_stats(kind).get("name", "?")))
	if sound:
		sound.play("order")


# ---------------------------------------------------------------- Economy

func supply_used(faction: String) -> int:
	var n := 0
	for u in units:
		if not u.dead and u.faction == faction:
			n += 1
	return n


func supply_max(faction: String) -> int:
	# Filter by faction, then delegate the sum to RTSData instead
	# of duplicating it (see REVIEW.md, finding 15).
	var mine: Array = []
	for b in buildings:
		if not b.dead and b.faction == faction and not b.under_construction:
			mine.append(b)
	return RTSData.supply_max(mine)


func _train_unit(kind: String) -> void:
	if selected_building == null or selected_building.under_construction:
		return
	if game_mode == "client":
		rpc_id(1, "_rpc_train", selected_building.id, kind)
		return
	_apply_train(selected_building.id, kind)


func _apply_train(building_id: int, kind: String, sender_faction: String = "") -> void:
	var building := _building_by_id(building_id)
	if building == null or building.under_construction:
		return
	if sender_faction != "" and building.faction != sender_faction:
		return
	# Only kinds this building can train (hall -> worker, barracks
	# -> combat). The old code queued anything, including unknown
	# kinds at cost 0, and a Grunt from a Town Hall.
	if not RTSData.can_train_at(building.kind, kind):
		push_error("main._apply_train: '%s' cannot train at a '%s'" % [kind, building.kind])
		return
	if building.queue.size() >= RTSData.MAX_TRAIN_QUEUE:
		_set_message("Training queue is full.")
		return
	var faction := building.faction
	var cost: Dictionary = RTSData.unit_cost(kind)
	var faction_res: Dictionary = res[faction]
	if not RTSData.can_afford(faction_res, cost):
		_set_message("Not enough resources.")
		if sound:
			sound.play("error")
		return
	if supply_used(faction) + int(cost.get("supply", 1)) > supply_max(faction):
		_set_message("Not enough supply — build a Farm.")
		if sound:
			sound.play("error")
		return
	RTSData.pay(faction_res, cost)
	if building.queue.is_empty():
		building.queue_timer = float(RTSData.unit_stats(kind).get("train_time", 10.0))
	building.queue.append(kind)
	if sound:
		sound.play("click")


func _nearest_enemy_unit(pos: Vector2, max_dist: float) -> RTSUnit:
	# One search, not two near-identical loops: this is the
	# faction-specific search with my_faction filled in.
	return _nearest_enemy_unit_for(my_faction, pos, max_dist)


func _nearest_enemy_unit_for(faction: String, pos: Vector2, max_dist: float) -> RTSUnit:
	var best: RTSUnit = null
	var best_d := max_dist
	for u in units:
		if u.dead or u.faction == faction:
			continue
		var d := u.position.distance_to(pos)
		if d < best_d:
			best = u
			best_d = d
	return best


func _nearest_enemy_building(pos: Vector2, max_dist: float) -> RTSBuilding:
	var best: RTSBuilding = null
	var best_d := max_dist
	for b in buildings:
		if b.dead or b.faction == my_faction:
			continue
		var d := b.position.distance_to(pos)
		if d < best_d:
			best = b
			best_d = d
	return best


func _nearest_resource(pos: Vector2, max_dist: float) -> RTSResource:
	var best: RTSResource = null
	var best_d := max_dist
	for r in resource_nodes:
		if r.dead:
			continue
		var d := r.position.distance_to(pos)
		if d < best_d:
			best = r
			best_d = d
	return best


func _nearest_hall(faction: String, pos: Vector2) -> RTSBuilding:
	var best: RTSBuilding = null
	var best_d := 1e9
	for b in buildings:
		if b.dead or b.faction != faction:
			continue
		if b.kind != RTSData.hall_kind(faction):
			continue
		var d := b.position.distance_to(pos)
		if d < best_d:
			best = b
			best_d = d
	return best


# ---------------------------------------------------------------- Simulation

func _process(delta: float) -> void:
	if not started:
		return
	if game_over:
		return
	elapsed += delta
	_update_camera(delta)
	_update_drag_rect()
	if game_mode == "client":
		# Host-authoritative: the client only renders snapshots.
		if hud:
			hud.update_hud()
		_update_fog(delta)
		return
	_update_units(delta)
	_update_buildings(delta)
	if game_mode == "single" or game_mode == "campaign":
		_update_ai(delta)
	if hud:
		hud.update_hud()
	_update_fog(delta)
	_check_end()
	if game_mode == "host" and remote_peer_id != 0:
		snapshot_timer += delta
		if snapshot_timer >= RTSData.SNAPSHOT_INTERVAL:
			snapshot_timer = 0.0
			_send_snapshot()
	# No blanket queue_redraw(): _draw only paints static ground/grid
	# plus the placement ghost. The ghost follows the mouse, so the
	# map redraws only while placing; everything else redraws only
	# when its own appearance changes (see RTSUnit / RTSFogLayer).
	if placing_kind != "":
		queue_redraw()


func _fog_index(pos: Vector2) -> int:
	var cols := int(RTSData.WORLD_SIZE.x / RTSData.TILE)
	var cx := clampi(int(pos.x / RTSData.TILE), 0, cols - 1)
	var rows := int(RTSData.WORLD_SIZE.y / RTSData.TILE)
	var cy := clampi(int(pos.y / RTSData.TILE), 0, rows - 1)
	return cy * cols + cx


func is_visible_at(pos: Vector2) -> bool:
	if not fog_enabled:
		return true
	return bool(fog_visible[_fog_index(pos)])


func is_explored(pos: Vector2) -> bool:
	if not fog_enabled:
		return true
	return bool(fog_explored[_fog_index(pos)])


func _update_fog(delta: float) -> void:
	fog_timer -= delta
	if fog_timer > 0.0:
		return
	fog_timer = RTSData.FOG_RECOMPUTE_INTERVAL
	_recompute_fog()


func _recompute_fog() -> void:
	var cols := int(RTSData.WORLD_SIZE.x / RTSData.TILE)
	var rows := int(RTSData.WORLD_SIZE.y / RTSData.TILE)
	fog_visible.fill(false)
	if not fog_enabled:
		_apply_fog_visibility()
		return
	for u in units:
		if u.dead or u.faction != my_faction:
			continue
		_mark_visible(u.position, u.sight)
	for b in buildings:
		if b.dead or b.faction != my_faction:
			continue
		_mark_visible(b.position, RTSData.BUILDING_SIGHT)
	_apply_fog_visibility()
	# The fog layer only redraws when the fog actually changed
	# (see RTSFogLayer) — this is the moment that happens.
	if fog_layer:
		fog_layer.queue_redraw()


func _mark_visible(pos: Vector2, radius: float) -> void:
	var cols := int(RTSData.WORLD_SIZE.x / RTSData.TILE)
	var rows := int(RTSData.WORLD_SIZE.y / RTSData.TILE)
	var cell := RTSData.TILE
	var r_cells := int(radius / cell) + 1
	var ccx := int(pos.x / cell)
	var ccy := int(pos.y / cell)
	for cy in range(maxi(0, ccy - r_cells), mini(rows, ccy + r_cells + 1)):
		for cx in range(maxi(0, ccx - r_cells), mini(cols, ccx + r_cells + 1)):
			var cell_pos := Vector2((cx + 0.5) * cell, (cy + 0.5) * cell)
			if cell_pos.distance_to(pos) <= radius:
				var i := cy * cols + cx
				fog_visible[i] = true
				fog_explored[i] = true


func _apply_fog_visibility() -> void:
	for u in units:
		if u.dead:
			continue
		u.visible = u.faction == my_faction or is_visible_at(u.position)
	for b in buildings:
		if b.dead:
			continue
		b.visible = b.faction == my_faction or is_visible_at(b.position)
	for r in resource_nodes:
		if r.dead:
			continue
		r.visible = is_explored(r.position)


func _update_camera(delta: float) -> void:
	var dir := Vector2.ZERO
	# WASD panning is skipped while a text field has focus: typing
	# an IP address into the join field used to pan the camera at
	# the same time (see REVIEW.md, finding 6).
	var focus_owner := get_viewport().gui_get_focus_owner()
	var typing := focus_owner is LineEdit
	if not typing:
		if Input.is_key_pressed(KEY_W) or Input.is_key_pressed(KEY_UP):
			dir.y -= 1
		if Input.is_key_pressed(KEY_S) or Input.is_key_pressed(KEY_DOWN):
			dir.y += 1
		if Input.is_key_pressed(KEY_A) or Input.is_key_pressed(KEY_LEFT):
			dir.x -= 1
		if Input.is_key_pressed(KEY_D) or Input.is_key_pressed(KEY_RIGHT):
			dir.x += 1
	if dir == Vector2.ZERO and not dragging:
		var mp := get_viewport().get_mouse_position()
		var vp := get_viewport_rect().size
		# No edge-pan while the mouse is over the bottom command
		# panel: the old threshold (vp.y - 132) overlapped the
		# panel, so clicking a command button panned the camera.
		var over_bottom_panel := mp.y > vp.y - BOTTOM_PANEL_HEIGHT
		if not over_bottom_panel:
			if mp.x < EDGE_MARGIN:
				dir.x -= 1
			elif mp.x > vp.x - EDGE_MARGIN:
				dir.x += 1
			if mp.y < TOP_BAR_HEIGHT + EDGE_MARGIN:
				dir.y -= 1
			elif mp.y > vp.y - BOTTOM_PANEL_HEIGHT - EDGE_MARGIN:
				dir.y += 1
	if dir != Vector2.ZERO:
		camera.position += dir.normalized() * CAMERA_SPEED * delta
		camera.position = camera.position.clamp(Vector2.ZERO, RTSData.WORLD_SIZE)


func _update_drag_rect() -> void:
	if dragging and hud:
		var mp := get_viewport().get_mouse_position()
		var rect := Rect2(
			Vector2(minf(drag_start_screen.x, mp.x), minf(drag_start_screen.y, mp.y)),
			Vector2(absf(mp.x - drag_start_screen.x), absf(mp.y - drag_start_screen.y)))
		hud.selection_rect.visible = true
		hud.selection_rect.position = rect.position
		hud.selection_rect.size = rect.size


func _move_toward(u: RTSUnit, dest: Vector2, delta: float, stop_dist: float) -> bool:
	var to := dest - u.position
	var dist := to.length()
	if dist <= stop_dist:
		return true
	var step := u.speed * delta
	if step >= dist:
		u.position = dest
		return true
	u.position += to.normalized() * step
	u.position = u.position.clamp(Vector2(20, 20), RTSData.WORLD_SIZE - Vector2(20, 20))
	return false


# O(n²) per frame (called once per unit, loops all units) — fine
# at ~40 units, the scaling ceiling past ~150. A spatial hash is
# the fix if the unit cap ever grows; see REVIEW.md, finding 9.
func _separate(u: RTSUnit) -> void:
	for other in units:
		if other == u or other.dead:
			continue
		var d := u.position - other.position
		var dist := d.length()
		if dist > 0.01 and dist < RTSData.SEPARATION_DIST:
			u.position += d.normalized() * (RTSData.SEPARATION_DIST - dist) * 0.5


func _update_units(delta: float) -> void:
	for u in units.duplicate():
		if u.dead:
			continue
		u.attack_timer -= delta
		match u.state:
			"idle":
				if not RTSData.is_worker(u.kind):
					var foe := _nearest_enemy_unit_for(u.faction, u.position, u.sight)
					if foe != null:
						u.state = "attack"
						u.target_unit = foe
			"move":
				if _move_toward(u, u.target_pos, delta, RTSData.MOVE_STOP_DIST):
					u.state = "idle"
			"attack_move":
				var foe2 := _nearest_enemy_unit_for(u.faction, u.position, u.sight)
				if foe2 != null:
					u.state = "attack"
					u.target_unit = foe2
				elif _move_toward(u, u.target_pos, delta, RTSData.MOVE_STOP_DIST):
					u.state = "idle"
			"gather_to":
				# is_instance_valid first: the target may have been
				# freed since it was assigned (see _remove_resource
				# and REVIEW.md, finding 1). Reading .dead on a
				# freed instance is an error, not a null.
				if not is_instance_valid(u.target_resource) or u.target_resource.dead or u.target_resource.amount <= 0:
					u.state = "idle"
					u.target_resource = null
				elif _move_toward(u, u.target_resource.position, delta, RTSData.GATHER_STOP_DIST):
					u.state = "gathering"
					u.gather_timer = RTSData.GATHER_TIME
			"gathering":
				if not is_instance_valid(u.target_resource) or u.target_resource.dead:
					u.state = "idle"
				else:
					u.gather_timer -= delta
					if u.gather_timer <= 0.0:
						u.carry_type = u.target_resource.kind
						u.carry_amount = mini(RTSData.GOLD_CARRY if u.target_resource.kind == "gold" else RTSData.WOOD_CARRY, u.target_resource.amount)
						u.target_resource.amount -= u.carry_amount
						if u.target_resource.amount <= 0:
							_remove_resource(u.target_resource)
						u.state = "return"
						var hall := _nearest_hall(u.faction, u.position)
						if hall != null:
							u.target_pos = hall.position + RTSData.HALL_DROPOFF_OFFSET
			"return":
				var hall2 := _nearest_hall(u.faction, u.position)
				if hall2 == null:
					u.state = "idle"
				elif _move_toward(u, hall2.position + RTSData.HALL_DROPOFF_OFFSET, delta, RTSData.RETURN_STOP_DIST):
					var r: Dictionary = res[u.faction]
					if u.carry_type == "gold":
						r["gold"] = int(r["gold"]) + u.carry_amount
					elif u.carry_type == "tree":
						r["wood"] = int(r["wood"]) + u.carry_amount
					if u.faction == my_faction and sound:
						sound.play("coin")
					u.carry_amount = 0
					u.carry_type = ""
					if is_instance_valid(u.target_resource) and not u.target_resource.dead and u.target_resource.amount > 0:
						u.state = "gather_to"
					else:
						u.state = "idle"
						u.target_resource = null
			"build":
				if not is_instance_valid(u.target_building) or u.target_building.dead or not u.target_building.under_construction:
					u.state = "idle"
					u.target_building = null
				elif _move_toward(u, u.target_building.position, delta, RTSData.BUILD_STOP_DIST):
					u.state = "building"
			"building":
				if not is_instance_valid(u.target_building) or u.target_building.dead or not u.target_building.under_construction:
					u.state = "idle"
					u.target_building = null
			"attack":
				_update_attack(u, delta)
		_separate(u)


func _update_attack(u: RTSUnit, delta: float) -> void:
	var target_pos := Vector2.INF
	var target_is_unit := false
	# is_instance_valid first — see the gather_to branch above:
	# a target freed last frame is not null, it is a dangling
	# reference, and reading .dead on it is an error.
	if is_instance_valid(u.target_unit):
		if u.target_unit.dead:
			u.target_unit = null
			u.state = "idle"
			return
		target_pos = u.target_unit.position
		target_is_unit = true
	elif is_instance_valid(u.target_building):
		if u.target_building.dead:
			u.target_building = null
			u.state = "idle"
			return
		target_pos = u.target_building.position
	else:
		u.target_unit = null
		u.target_building = null
		u.state = "idle"
		return
	var dist := u.position.distance_to(target_pos)
	var reach := u.attack_range + (40.0 if not target_is_unit else 0.0)
	if dist > reach:
		_move_toward(u, target_pos, delta, reach * 0.9)
		return
	if u.attack_timer <= 0.0:
		u.attack_timer = u.attack_cooldown
		if target_is_unit:
			_damage_unit(u.target_unit, u.damage)
		else:
			_damage_building(u.target_building, u.damage)


# One removal path per entity type. Everything that kills or
# despawns an entity goes through here, because removal has a
# second job besides erasing and freeing: every other unit that
# was targeting the victim must forget it. The old code did that
# for buildings only; a dead unit left attackers holding a
# reference to a freed instance, which errored the next frame
# and stalled their state machine (see REVIEW.md, finding 1).
func _clear_targets_of_unit(victim: RTSUnit) -> void:
	for u in units:
		if u.target_unit == victim:
			u.target_unit = null
			if u.state == "attack":
				u.state = "idle"


func _clear_targets_of_building(victim: RTSBuilding) -> void:
	for u in units:
		if u.target_building == victim:
			u.target_building = null
			if u.state == "attack" or u.state == "build" or u.state == "building":
				u.state = "idle"


func _clear_targets_of_resource(victim: RTSResource) -> void:
	for u in units:
		if u.target_resource == victim:
			u.target_resource = null
			if u.state == "gather_to" or u.state == "gathering" or u.state == "return":
				u.state = "idle"


func _remove_unit(u: RTSUnit) -> void:
	_clear_targets_of_unit(u)
	units.erase(u)
	selected_units.erase(u)
	u.dead = true
	u.queue_free()


func _remove_building(b: RTSBuilding) -> void:
	_clear_targets_of_building(b)
	buildings.erase(b)
	if selected_building == b:
		selected_building = null
		_refresh_command_panel()
	b.dead = true
	b.queue_free()


func _remove_resource(r: RTSResource) -> void:
	_clear_targets_of_resource(r)
	resource_nodes.erase(r)
	r.dead = true
	r.queue_free()


func _damage_unit(u: RTSUnit, amount: int) -> void:
	if u.dead:
		return
	u.hp -= amount
	if u.hp <= 0:
		_remove_unit(u)


func _damage_building(b: RTSBuilding, amount: int) -> void:
	if b.dead:
		return
	b.hp -= amount
	if b.hp <= 0:
		_remove_building(b)
		_set_message("A %s has fallen!" % String(RTSData.building_stats(b.kind).get("name", "building")))


func _update_buildings(delta: float) -> void:
	for b in buildings.duplicate():
		if b.dead:
			continue
		if b.under_construction:
			var rate := 1.0
			for u in units:
				if not u.dead and u.state == "building" and u.target_building == b:
					rate = RTSData.BUILD_RATE_WITH_WORKER
			b.build_progress += delta * rate
			if b.build_progress >= b.build_time:
				b.under_construction = false
				b.hp = b.max_hp
				_set_message("A %s is complete." % String(RTSData.building_stats(b.kind).get("name", "building")))
				if b.faction == my_faction and sound:
					sound.play("build_complete")
			continue
		if b.queue.is_empty():
			continue
		b.queue_timer -= delta
		if b.queue_timer <= 0.0:
			var kind := String(b.queue[0])
			b.queue.remove_at(0)
			var spawn_pos: Vector2 = b.position + RTSData.TRAIN_SPAWN_OFFSET
			var u := _spawn_unit(b.faction, kind, spawn_pos)
			if u == null:
				# Unknown kind in the queue (rejected at train
				# time since v0.3.0, but never assume the queue
				# is clean): drop it instead of crashing.
				continue
			u.state = "move"
			u.target_pos = b.rally_pos
			if b.faction == my_faction and sound:
				sound.play("train")
			if not b.queue.is_empty():
				b.queue_timer = float(RTSData.unit_stats(String(b.queue[0])).get("train_time", 10.0))


func _check_end() -> void:
	# Campaign mission 2 only needs the Orc Great Hall destroyed.
	if game_mode == "campaign" and String(mission.get("win", "")) == "destroy_hall":
		for b in buildings:
			if not b.dead and b.faction == AI_FACTION and b.kind == RTSData.hall_kind(AI_FACTION):
				return
		_end_game(PLAYER_FACTION)
		return
	var human_alive := false
	var orc_alive := false
	for u in units:
		if not u.dead:
			if u.faction == PLAYER_FACTION:
				human_alive = true
			else:
				orc_alive = true
	for b in buildings:
		if not b.dead:
			if b.faction == PLAYER_FACTION:
				human_alive = true
			else:
				orc_alive = true
	if not orc_alive:
		_end_game(PLAYER_FACTION)
	elif not human_alive:
		_end_game(AI_FACTION)


func _end_game(winner: String) -> void:
	if game_over:
		return
	game_over = true
	winner_faction = winner
	victory = winner == my_faction
	# The old text always said "The Orc base has fallen" — wrong
	# when the winner is the Orcs and you are the Orcs.
	if sound:
		sound.play("victory" if victory else "defeat")
	var show_next := false
	if game_mode == "campaign" and victory and mission_index >= 0:
		campaign_unlocked = maxi(campaign_unlocked, mission_index + 2)
		RTSCampaign.save_unlocked(campaign_unlocked)
		show_next = mission_index + 1 < RTSCampaign.missions().size()
	if hud:
		hud.show_end(victory, show_next)
	if game_mode == "host" and remote_peer_id != 0:
		_send_snapshot()


# ---------------------------------------------------------------- Orc AI

# The AI's home base, derived from its Great Hall — not a
# hardcoded map coordinate (see REVIEW.md, finding 13). Farm and
# barracks spots are offsets from it, so moving the base on the
# map moves the AI's build plan with it.
func _ai_base_pos() -> Vector2:
	var hall := _nearest_hall(AI_FACTION, Vector2.ZERO)
	if hall != null:
		return hall.position
	return Vector2(2080, 350)


func _update_ai(delta: float) -> void:
	ai_timer += delta
	ai_attack_timer -= delta
	if ai_timer < RTSData.AI_TICK:
		return
	ai_timer = 0.0
	_ai_assign_workers()
	_ai_build_and_train()
	if ai_attack_timer <= 0.0:
		ai_attack_timer = ai_attack_interval
		_ai_attack_wave()


func _ai_assign_workers() -> void:
	var peons: Array[RTSUnit] = []
	for u in units:
		if not u.dead and u.faction == AI_FACTION and RTSData.is_worker(u.kind):
			peons.append(u)
	var base := _ai_base_pos()
	var gold_mine: RTSResource = null
	var tree: RTSResource = null
	var tree_d := 1e9
	for r in resource_nodes:
		if r.dead:
			continue
		if r.kind == "gold" and gold_mine == null and r.position.distance_to(base) < 600:
			gold_mine = r
		if r.kind == "tree":
			var td := r.position.distance_to(base)
			if td < tree_d:
				tree = r
				tree_d = td
	var i := 0
	for p in peons:
		if p.state == "idle":
			# Two on gold, the rest on wood.
			var node := gold_mine if (i < 2 and gold_mine != null) else tree
			if node != null:
				p.state = "gather_to"
				p.target_resource = node
		i += 1


func _ai_build_and_train() -> void:
	var ai_res: Dictionary = res[AI_FACTION]
	# Stage 0: pig farm once we can afford it. Spots are offsets
	# from the hall, so they match the old fixed coordinates
	# (farm 1920,480 / barracks 2080,500) on the current map.
	var base := _ai_base_pos()
	if ai_stage == 0:
		if _ai_try_build("pig_farm", base + Vector2(-160, 130)):
			ai_stage = 1
		return
	# Stage 1: barracks.
	if ai_stage == 1:
		if _ai_try_build("barracks", base + Vector2(0, 150)):
			ai_stage = 2
		return
	# Stage 2+: keep training.
	var hall := _nearest_hall(AI_FACTION, Vector2(2080, 350))
	if hall != null and hall.queue.size() < 2:
		var cost: Dictionary = RTSData.unit_cost("peon")
		if RTSData.can_afford(ai_res, cost) and supply_used(AI_FACTION) < supply_max(AI_FACTION):
			RTSData.pay(ai_res, cost)
			if hall.queue.is_empty():
				hall.queue_timer = float(RTSData.unit_stats("peon").get("train_time", 8.0))
			hall.queue.append("peon")
	for b in buildings:
		if b.dead or b.faction != AI_FACTION or b.under_construction:
			continue
		if b.kind == "barracks" and b.queue.size() < 3:
			var kind := "grunt" if randi() % 3 != 0 else "spearman"
			var c: Dictionary = RTSData.unit_cost(kind)
			if RTSData.can_afford(ai_res, c) and supply_used(AI_FACTION) < supply_max(AI_FACTION):
				RTSData.pay(ai_res, c)
				if b.queue.is_empty():
					b.queue_timer = float(RTSData.unit_stats(kind).get("train_time", 12.0))
				b.queue.append(kind)


func _ai_try_build(kind: String, pos: Vector2) -> bool:
	var ai_res: Dictionary = res[AI_FACTION]
	var cost: Dictionary = RTSData.building_cost(kind)
	if not RTSData.can_afford(ai_res, cost):
		return false
	for b in buildings:
		if not b.dead and b.faction == AI_FACTION and b.kind == kind:
			return true
	var worker: RTSUnit = null
	for u in units:
		if not u.dead and u.faction == AI_FACTION and RTSData.is_worker(u.kind) and u.state == "idle":
			worker = u
			break
	if worker == null:
		# Use any peon not already building.
		for u in units:
			if not u.dead and u.faction == AI_FACTION and RTSData.is_worker(u.kind) and u.state != "building":
				worker = u
				break
	if worker == null:
		return false
	RTSData.pay(ai_res, cost)
	var b := _spawn_building(AI_FACTION, kind, pos, true)
	worker.state = "build"
	worker.target_building = b
	worker.target_pos = pos
	return true


func _ai_attack_wave() -> void:
	var hall := _nearest_hall(PLAYER_FACTION, Vector2(1200, 800))
	var dest := Vector2(320, 1250) if hall == null else hall.position
	# (The fallback is the Human Town Hall's map position; the
	# hall lookup above finds it on the current map.)
	var sent := 0
	for u in units:
		if u.dead or u.faction != AI_FACTION or RTSData.is_worker(u.kind):
			continue
		u.state = "attack_move"
		u.target_pos = dest + Vector2(randi_range(-60, 60), randi_range(-60, 60))
		u.target_unit = null
		u.target_building = null
		sent += 1
	if sent > 0:
		_set_message("The Orcs are attacking! (%d warriors)" % sent)


# ---------------------------------------------------------------- Multiplayer

# The sender's faction is derived from the peer id, not trusted
# from the message: the server is always the Humans (id 1), the
# joining player is always the Orcs. _apply_* then only lets the
# sender touch their own side (see REVIEW.md, finding 3).
func _sender_faction() -> String:
	return PLAYER_FACTION if multiplayer.get_remote_sender_id() == 1 else AI_FACTION


@rpc("any_peer", "call_remote", "reliable")
func _rpc_order(order: Dictionary) -> void:
	if multiplayer.is_server():
		_apply_order(order, _sender_faction())


@rpc("any_peer", "call_remote", "reliable")
func _rpc_train(building_id: int, kind: String) -> void:
	if multiplayer.is_server():
		_apply_train(building_id, kind, _sender_faction())


@rpc("any_peer", "call_remote", "reliable")
func _rpc_place(kind: String, x: float, y: float, worker_id: int) -> void:
	if multiplayer.is_server():
		_apply_place(kind, Vector2(x, y), worker_id, _sender_faction())


@rpc("any_peer", "call_remote", "unreliable")
func _rpc_snapshot(data: Dictionary) -> void:
	if not multiplayer.is_server():
		_apply_snapshot(data)


func _build_snapshot() -> Dictionary:
	var unit_list: Array = []
	for u in units:
		if u.dead:
			continue
		unit_list.append({
			"id": u.id, "kind": u.kind, "faction": u.faction,
			"x": u.position.x, "y": u.position.y, "hp": u.hp,
			"state": u.state, "carry_type": u.carry_type, "carry_amount": u.carry_amount,
		})
	var building_list: Array = []
	for b in buildings:
		if b.dead:
			continue
		building_list.append({
			"id": b.id, "kind": b.kind, "faction": b.faction,
			"x": b.position.x, "y": b.position.y, "hp": b.hp,
			"under_construction": b.under_construction, "build_progress": b.build_progress,
			"queue": b.queue.duplicate(), "queue_timer": b.queue_timer,
			"rally_x": b.rally_pos.x, "rally_y": b.rally_pos.y,
		})
	var resource_list: Array = []
	for r in resource_nodes:
		if r.dead or r.amount <= 0:
			continue
		resource_list.append({
			"id": r.id, "kind": r.kind, "x": r.position.x, "y": r.position.y, "amount": r.amount,
		})
	return {
		"res": {"human": (res["human"] as Dictionary).duplicate(), "orc": (res["orc"] as Dictionary).duplicate()},
		"elapsed": elapsed, "winner": winner_faction,
		"units": unit_list, "buildings": building_list, "resources": resource_list,
	}


func _send_snapshot() -> void:
	if multiplayer.multiplayer_peer == null:
		return
	rpc("_rpc_snapshot", _build_snapshot())


# Snapshot entries come from the network, so every entry is
# validated before it touches the game: non-Dictionary entries
# are skipped, unknown kinds/factions are skipped, and numbers
# are clamped to sane ranges. The old code did
# `var d: Dictionary = su` (errors on a non-Dictionary) and
# replaced `res` wholesale with whatever the peer sent.
# Removal goes through _remove_* so dangling target references
# are cleared (see REVIEW.md, findings 1 and 5).
func _apply_snapshot(data: Dictionary) -> void:
	var new_res: Variant = data.get("res", null)
	if new_res is Dictionary and (new_res as Dictionary).get("human") is Dictionary and (new_res as Dictionary).get("orc") is Dictionary:
		res = new_res
	elapsed = _num(data.get("elapsed", elapsed), elapsed)
	var seen_units: Dictionary = {}
	for su in data.get("units", []):
		if not (su is Dictionary):
			continue
		var d: Dictionary = su
		var id := int(_num(d.get("id", -1), -1.0))
		if id < 0:
			continue
		var faction := String(d.get("faction", "human"))
		var kind := String(d.get("kind", "peasant"))
		if faction != PLAYER_FACTION and faction != AI_FACTION:
			continue
		if not RTSData.is_known_unit(kind):
			continue
		seen_units[id] = true
		var u := _unit_by_id(id)
		if u == null:
			u = _spawn_unit(faction, kind, Vector2(_num(d.get("x", 0.0), 0.0), _num(d.get("y", 0.0), 0.0)), id)
			if u == null:
				continue
		u.position = Vector2(_num(d.get("x", 0.0), 0.0), _num(d.get("y", 0.0), 0.0))
		u.hp = clampi(int(_num(d.get("hp", u.max_hp), float(u.max_hp))), 0, u.max_hp)
		u.state = String(d.get("state", "idle"))
		u.carry_type = String(d.get("carry_type", ""))
		u.carry_amount = maxi(0, int(_num(d.get("carry_amount", 0), 0.0)))
	for u in units.duplicate():
		if not seen_units.has(u.id):
			_remove_unit(u)
	var seen_buildings: Dictionary = {}
	for sb in data.get("buildings", []):
		if not (sb is Dictionary):
			continue
		var d: Dictionary = sb
		var id := int(_num(d.get("id", -1), -1.0))
		if id < 0:
			continue
		var faction := String(d.get("faction", "human"))
		var kind := String(d.get("kind", "farm"))
		if faction != PLAYER_FACTION and faction != AI_FACTION:
			continue
		if not RTSData.is_known_building(kind):
			continue
		seen_buildings[id] = true
		var b := _building_by_id(id)
		if b == null:
			b = _spawn_building(faction, kind, Vector2(_num(d.get("x", 0.0), 0.0), _num(d.get("y", 0.0), 0.0)), bool(d.get("under_construction", false)), id)
			if b == null:
				continue
		b.position = Vector2(_num(d.get("x", 0.0), 0.0), _num(d.get("y", 0.0), 0.0))
		b.hp = clampi(int(_num(d.get("hp", b.max_hp), float(b.max_hp))), 0, b.max_hp)
		b.under_construction = bool(d.get("under_construction", false))
		b.build_progress = maxf(0.0, _num(d.get("build_progress", 0.0), 0.0))
		var q: Variant = d.get("queue", [])
		b.queue = Array(q) if q is Array else []
		b.queue_timer = maxf(0.0, _num(d.get("queue_timer", 0.0), 0.0))
		b.rally_pos = Vector2(_num(d.get("rally_x", 0.0), 0.0), _num(d.get("rally_y", 0.0), 0.0))
	for b in buildings.duplicate():
		if not seen_buildings.has(b.id):
			_remove_building(b)
	var seen_resources: Dictionary = {}
	for sr in data.get("resources", []):
		if not (sr is Dictionary):
			continue
		var d: Dictionary = sr
		var id := int(_num(d.get("id", -1), -1.0))
		if id < 0:
			continue
		var kind := String(d.get("kind", "gold"))
		if kind != "gold" and kind != "tree":
			continue
		seen_resources[id] = true
		var r := _resource_by_id(id)
		if r == null:
			r = _spawn_resource(kind, Vector2(_num(d.get("x", 0.0), 0.0), _num(d.get("y", 0.0), 0.0)), maxi(0, int(_num(d.get("amount", 0), 0.0))), id)
			if r == null:
				continue
		r.amount = maxi(0, int(_num(d.get("amount", 0), 0.0)))
	for r in resource_nodes.duplicate():
		if not seen_resources.has(r.id):
			_remove_resource(r)
	_recompute_fog()
	if not _snapshot_logged:
		_snapshot_logged = true
		print("MP: first snapshot applied, units=%d buildings=%d" % [units.size(), buildings.size()])
	var winner := String(data.get("winner", ""))
	if winner != "" and not game_over:
		_end_game(winner)


# ---------------------------------------------------------------- Map drawing

func _draw() -> void:
	# Ground.
	draw_rect(Rect2(Vector2.ZERO, RTSData.WORLD_SIZE), Color(0.32, 0.55, 0.28))
	# Tile grid.
	var grid_col := Color(0, 0, 0, 0.08)
	var x := 0.0
	while x <= RTSData.WORLD_SIZE.x:
		draw_line(Vector2(x, 0), Vector2(x, RTSData.WORLD_SIZE.y), grid_col, 1.0)
		x += RTSData.TILE
	var y := 0.0
	while y <= RTSData.WORLD_SIZE.y:
		draw_line(Vector2(0, y), Vector2(RTSData.WORLD_SIZE.x, y), grid_col, 1.0)
		y += RTSData.TILE
	draw_rect(Rect2(Vector2.ZERO, RTSData.WORLD_SIZE), Color(0.15, 0.3, 0.12), false, 4.0)
	# Placing ghost.
	if placing_kind != "":
		var mp := get_global_mouse_position()
		draw_rect(Rect2(mp - Vector2(40, 30), Vector2(80, 60)), Color(1, 1, 1, 0.35))
		draw_rect(Rect2(mp - Vector2(40, 30), Vector2(80, 60)), Color(1, 1, 1, 0.8), false, 2.0)
