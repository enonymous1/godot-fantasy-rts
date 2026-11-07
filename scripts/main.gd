## Fantasy RTS — Godot (v0.2.0).
## A playable 2D RTS in the style of classic 1990s
## real-time strategy games: gold + lumber economy,
## worker gather-and-return, farms for supply, barracks
## troops, and an Orc AI that builds up and attacks in waves.
## All art is original procedural shapes and all sound is
## synthesized; no third-party assets are used.
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
var sound_button: Button = null

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

# UI
var ui: CanvasLayer
var gold_label: Label
var wood_label: Label
var supply_label: Label
var time_label: Label
var message_label: Label
var selection_label: Label
var command_box: HBoxContainer
var selection_rect: ColorRect
var end_panel: PanelContainer
var end_label: Label
var next_mission_button: Button = null
# Start menu.
var menu_panel: PanelContainer
var mission_list: VBoxContainer
var briefing_label: Label
var mission_start_button: Button
var selected_mission: int = -1
var ip_edit: LineEdit


func _ready() -> void:
	campaign_unlocked = RTSCampaign.load_unlocked()
	_build_camera()
	_build_map()
	_init_fog()
	_build_ui()
	_build_fog_layer()
	_build_minimap()
	_build_sound()
	_build_menu()
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


func _build_minimap() -> void:
	minimap = RTSMinimap.new()
	minimap.game = self
	minimap.set_anchors_preset(Control.PRESET_BOTTOM_RIGHT)
	minimap.offset_left = -212
	minimap.offset_top = -245
	minimap.offset_right = -12
	minimap.offset_bottom = -112
	ui.add_child(minimap)


func _build_sound() -> void:
	sound = RTSSoundManager.new()
	sound.name = "Sound"
	add_child(sound)


func _build_menu() -> void:
	menu_panel = PanelContainer.new()
	menu_panel.set_anchors_preset(Control.PRESET_CENTER)
	ui.add_child(menu_panel)
	var vbox := VBoxContainer.new()
	menu_panel.add_child(vbox)
	var title := Label.new()
	title.text = "Fantasy RTS"
	title.add_theme_font_size_override("font_size", 30)
	vbox.add_child(title)
	var sub := Label.new()
	sub.text = "Humans vs Orcs — Godot RTS  •  Left: select  •  Right: move / attack / gather"
	vbox.add_child(sub)
	var single := Button.new()
	single.text = "Single Battle (vs Orc AI)"
	single.pressed.connect(_start_single)
	vbox.add_child(single)
	var camp_toggle := Button.new()
	camp_toggle.text = "Campaign…"
	camp_toggle.pressed.connect(func() -> void: mission_list.visible = not mission_list.visible)
	vbox.add_child(camp_toggle)
	mission_list = VBoxContainer.new()
	mission_list.visible = false
	vbox.add_child(mission_list)
	for i in RTSCampaign.missions().size():
		var m: Dictionary = RTSCampaign.mission(i)
		var b := Button.new()
		var locked := i >= campaign_unlocked
		b.text = String(m.get("name", "?")) + ("  (locked)" if locked else "")
		b.disabled = locked
		b.pressed.connect(_on_mission_picked.bind(i))
		mission_list.add_child(b)
	briefing_label = Label.new()
	briefing_label.text = "Pick a mission to see its briefing."
	briefing_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	briefing_label.custom_minimum_size = Vector2(420, 60)
	mission_list.add_child(briefing_label)
	mission_start_button = Button.new()
	mission_start_button.text = "Start mission"
	mission_start_button.disabled = true
	mission_start_button.pressed.connect(_on_mission_start_pressed)
	mission_list.add_child(mission_start_button)
	var host := Button.new()
	host.text = "Host Game (LAN, you are Humans)"
	host.pressed.connect(_start_host)
	vbox.add_child(host)
	var join_row := HBoxContainer.new()
	vbox.add_child(join_row)
	ip_edit = LineEdit.new()
	ip_edit.text = "127.0.0.1"
	ip_edit.custom_minimum_size = Vector2(160, 0)
	ip_edit.placeholder_text = "Host IP"
	join_row.add_child(ip_edit)
	var join := Button.new()
	join.text = "Join Game (you are Orcs)"
	join.pressed.connect(_on_join_pressed)
	join_row.add_child(join)
	var ws_check := CheckButton.new()
	ws_check.text = "WebSocket (TCP) transport instead of ENet (UDP)"
	ws_check.toggled.connect(func(on: bool) -> void: use_websocket = on)
	vbox.add_child(ws_check)
	var note := Label.new()
	note.text = "Multiplayer: 2 players on the same network, port 7777. Host simulates; joiner sends orders. Use WebSocket if UDP is blocked on your network."
	note.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	note.custom_minimum_size = Vector2(420, 40)
	vbox.add_child(note)


func _on_mission_picked(index: int) -> void:
	selected_mission = index
	var m := RTSCampaign.mission(index)
	briefing_label.text = String(m.get("briefing", ""))
	mission_start_button.disabled = false
	if sound:
		sound.play("click")


func _on_mission_start_pressed() -> void:
	if selected_mission >= 0:
		_start_campaign(selected_mission)


func _on_next_mission_pressed() -> void:
	# Remember the next mission across the scene reload, then start it.
	var cfg := ConfigFile.new()
	cfg.load(RTSCampaign.SAVE_PATH)
	cfg.set_value("campaign", "pending_mission", mission_index + 1)
	cfg.save(RTSCampaign.SAVE_PATH)
	get_tree().reload_current_scene()


func _on_sound_button_pressed() -> void:
	if sound:
		var muted := sound.toggle_mute()
		sound_button.text = "Sound: Off" if muted else "Sound: On"


func _on_join_pressed() -> void:
	_start_join(ip_edit.text.strip_edges())


func _hide_menu() -> void:
	menu_panel.visible = false
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


func _spawn_unit(faction: String, kind: String, pos: Vector2, p_id: int = -1) -> RTSUnit:
	var u := RTSUnit.new()
	u.id = _next_entity_id(p_id)
	u.setup(faction, kind, pos)
	add_child(u)
	units.append(u)
	return u


func _spawn_building(faction: String, kind: String, pos: Vector2, under_construction: bool = false, p_id: int = -1) -> RTSBuilding:
	var b := RTSBuilding.new()
	b.id = _next_entity_id(p_id)
	b.setup(faction, kind, pos, under_construction)
	add_child(b)
	buildings.append(b)
	return b


func _spawn_resource(kind: String, pos: Vector2, amount: int, p_id: int = -1) -> RTSResource:
	var r := RTSResource.new()
	r.id = _next_entity_id(p_id)
	r.setup(kind, pos, amount)
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

func _build_ui() -> void:
	ui = CanvasLayer.new()
	ui.name = "UI"
	add_child(ui)

	var top := ColorRect.new()
	top.color = Color(0.08, 0.08, 0.12, 0.9)
	top.set_anchors_preset(Control.PRESET_TOP_WIDE)
	top.offset_bottom = 36
	ui.add_child(top)

	gold_label = _make_label(Vector2(12, 8), "Gold: 400")
	wood_label = _make_label(Vector2(160, 8), "Wood: 200")
	supply_label = _make_label(Vector2(300, 8), "Supply: 3/9")
	time_label = _make_label(Vector2(460, 8), "0:00")
	var help := _make_label(Vector2(620, 8), "Left: select  |  Right: move / attack / gather  |  WASD: pan  |  Wheel: zoom")
	help.add_theme_color_override("font_color", Color(0.75, 0.75, 0.75))

	message_label = _make_label(Vector2(12, 44), "")
	message_label.add_theme_color_override("font_color", Color(1.0, 0.9, 0.4))

	var bottom := ColorRect.new()
	bottom.color = Color(0.08, 0.08, 0.12, 0.9)
	bottom.set_anchors_preset(Control.PRESET_BOTTOM_WIDE)
	bottom.offset_top = -110
	ui.add_child(bottom)

	selection_label = _make_label(Vector2(12, 618), "Nothing selected")
	command_box = HBoxContainer.new()
	command_box.position = Vector2(12, 648)
	command_box.add_theme_constant_override("separation", 8)
	ui.add_child(command_box)

	selection_rect = ColorRect.new()
	selection_rect.color = Color(0.2, 0.9, 0.2, 0.15)
	selection_rect.visible = false
	ui.add_child(selection_rect)

	end_panel = PanelContainer.new()
	end_panel.set_anchors_preset(Control.PRESET_CENTER)
	end_panel.visible = false
	ui.add_child(end_panel)
	var vbox := VBoxContainer.new()
	end_panel.add_child(vbox)
	end_label = Label.new()
	end_label.add_theme_font_size_override("font_size", 28)
	vbox.add_child(end_label)
	var restart := Button.new()
	restart.text = "Play again"
	restart.pressed.connect(_on_restart_pressed)
	vbox.add_child(restart)
	next_mission_button = Button.new()
	next_mission_button.text = "Next mission"
	next_mission_button.visible = false
	next_mission_button.pressed.connect(_on_next_mission_pressed)
	vbox.add_child(next_mission_button)
	sound_button = Button.new()
	sound_button.text = "Sound: On"
	sound_button.position = Vector2(1080, 4)
	sound_button.pressed.connect(_on_sound_button_pressed)
	ui.add_child(sound_button)


func _make_label(pos: Vector2, text: String) -> Label:
	var l := Label.new()
	l.position = pos
	l.text = text
	l.add_theme_font_size_override("font_size", 16)
	ui.add_child(l)
	return l


func _set_message(text: String) -> void:
	if message_label:
		message_label.text = text


func _refresh_command_panel() -> void:
	for c in command_box.get_children():
		c.queue_free()
	if selected_building != null and selected_building.faction == PLAYER_FACTION and not selected_building.under_construction:
		if selected_building.kind == "town_hall":
			_add_command("Train Peasant (50g)", "train_peasant")
		elif selected_building.kind == "barracks":
			_add_command("Train Footman (60g 20w)", "train_footman")
			_add_command("Train Archer (50g 30w)", "train_archer")
		selection_label.text = "%s — HP %d/%d  (queue: %d)" % [
			String(RTSData.building_stats(selected_building.kind).get("name", "?")),
			selected_building.hp, selected_building.max_hp, selected_building.queue.size()]
		return
	if selected_units.is_empty():
		selection_label.text = "Nothing selected"
		return
	var worker_count := 0
	for u in selected_units:
		if RTSData.is_worker(u.kind):
			worker_count += 1
	selection_label.text = "%d unit(s) selected" % selected_units.size()
	if worker_count > 0:
		_add_command("Build Farm (100g 50w)", "build_farm")
		_add_command("Build Barracks (150g 100w)", "build_barracks")
	_add_command("Stop", "stop")


func _add_command(text: String, action: String) -> void:
	var b := Button.new()
	b.text = text
	b.pressed.connect(_on_command_pressed.bind(action))
	command_box.add_child(b)


func _on_command_pressed(action: String) -> void:
	if game_over:
		return
	match action:
		"train_peasant":
			_train_unit("peasant")
		"train_footman":
			_train_unit("footman")
		"train_archer":
			_train_unit("archer")
		"build_farm":
			placing_kind = "farm"
			_set_message("Placing Farm — left-click to place, right-click to cancel.")
		"build_barracks":
			placing_kind = "barracks"
			_set_message("Placing Barracks — left-click to place, right-click to cancel.")
		"stop":
			for u in selected_units:
				u.state = "idle"
				u.target_unit = null
				u.target_building = null
				u.target_resource = null


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
				var muted := sound.toggle_mute()
				sound_button.text = "Sound: Off" if muted else "Sound: On"
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
			selection_rect.visible = false
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
	if rect.size.x > 12 and rect.size.y > 12:
		for u in units:
			if not u.dead and u.faction == PLAYER_FACTION and rect.has_point(u.position):
				_select_unit(u)
	else:
		# Single click: nearest friendly unit, else enemy unit, else building.
		var best: RTSUnit = null
		var best_d := 30.0
		for u in units:
			if u.dead:
				continue
			var d := u.position.distance_to(world_pos)
			if d < best_d and (best == null or u.faction == PLAYER_FACTION):
				best = u
				best_d = d
		if best != null and best.faction == PLAYER_FACTION:
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


func _apply_order(order: Dictionary) -> void:
	var ids: Array = order.get("unit_ids", [])
	var i := 0
	for id in ids:
		var u := _unit_by_id(int(id))
		if u == null:
			continue
		match String(order.get("type", "")):
			"move":
				var offset := Vector2((i % 3) * 36 - 36, (i / 3) * 36)
				u.state = "move"
				u.target_pos = Vector2(float(order.get("x", 0.0)), float(order.get("y", 0.0))) + offset
				u.target_unit = null
				u.target_building = null
				u.target_resource = null
			"attack_unit":
				u.state = "attack"
				u.target_unit = _unit_by_id(int(order.get("target_id", -1)))
				u.target_building = null
				u.target_resource = null
			"attack_building":
				u.state = "attack"
				u.target_unit = null
				u.target_building = _building_by_id(int(order.get("target_id", -1)))
				u.target_resource = null
			"gather":
				u.state = "gather_to"
				u.target_resource = _resource_by_id(int(order.get("target_id", -1)))
				u.target_unit = null
				u.target_building = null
			"rally":
				pass
		i += 1
	if String(order.get("type", "")) == "rally":
		var b := _building_by_id(int(order.get("building_id", -1)))
		if b != null:
			b.rally_pos = Vector2(float(order.get("x", 0.0)), float(order.get("y", 0.0)))


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


func _apply_place(kind: String, world_pos: Vector2, worker_id: int) -> void:
	var worker := _unit_by_id(worker_id)
	if worker == null:
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
	var total := 0
	for b in buildings:
		if not b.dead and b.faction == faction and not b.under_construction:
			total += int(RTSData.building_stats(b.kind).get("supply", 0))
	return total


func _train_unit(kind: String) -> void:
	if selected_building == null or selected_building.under_construction:
		return
	if game_mode == "client":
		rpc_id(1, "_rpc_train", selected_building.id, kind)
		return
	_apply_train(selected_building.id, kind)


func _apply_train(building_id: int, kind: String) -> void:
	var building := _building_by_id(building_id)
	if building == null or building.under_construction:
		return
	if building.queue.size() >= 5:
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
	var best: RTSUnit = null
	var best_d := max_dist
	for u in units:
		if u.dead or u.faction == my_faction:
			continue
		var d := u.position.distance_to(pos)
		if d < best_d:
			best = u
			best_d = d
	return best


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
		queue_redraw()
		return
	if game_over:
		return
	elapsed += delta
	_update_camera(delta)
	_update_drag_rect()
	if game_mode == "client":
		# Host-authoritative: the client only renders snapshots.
		_update_hud()
		_update_fog(delta)
		queue_redraw()
		return
	_update_units(delta)
	_update_buildings(delta)
	if game_mode == "single" or game_mode == "campaign":
		_update_ai(delta)
	_update_hud()
	_update_fog(delta)
	_check_end()
	if game_mode == "host" and remote_peer_id != 0:
		snapshot_timer += delta
		if snapshot_timer >= 0.15:
			snapshot_timer = 0.0
			_send_snapshot()
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
	fog_timer = 0.25
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
		_mark_visible(b.position, 260.0)
	_apply_fog_visibility()


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
		if mp.x < 12:
			dir.x -= 1
		elif mp.x > vp.x - 12:
			dir.x += 1
		if mp.y < 48:
			dir.y -= 1
		elif mp.y > vp.y - 132:
			dir.y += 1
	if dir != Vector2.ZERO:
		camera.position += dir.normalized() * 550.0 * delta
		camera.position = camera.position.clamp(Vector2.ZERO, RTSData.WORLD_SIZE)


func _update_drag_rect() -> void:
	if dragging:
		var mp := get_viewport().get_mouse_position()
		var rect := Rect2(
			Vector2(minf(drag_start_screen.x, mp.x), minf(drag_start_screen.y, mp.y)),
			Vector2(absf(mp.x - drag_start_screen.x), absf(mp.y - drag_start_screen.y)))
		selection_rect.visible = true
		selection_rect.position = rect.position
		selection_rect.size = rect.size


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


func _separate(u: RTSUnit) -> void:
	for other in units:
		if other == u or other.dead:
			continue
		var d := u.position - other.position
		var dist := d.length()
		if dist > 0.01 and dist < 24.0:
			u.position += d.normalized() * (24.0 - dist) * 0.5


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
				if _move_toward(u, u.target_pos, delta, 6.0):
					u.state = "idle"
			"attack_move":
				var foe2 := _nearest_enemy_unit_for(u.faction, u.position, u.sight)
				if foe2 != null:
					u.state = "attack"
					u.target_unit = foe2
				elif _move_toward(u, u.target_pos, delta, 6.0):
					u.state = "idle"
			"gather_to":
				if u.target_resource == null or u.target_resource.dead or u.target_resource.amount <= 0:
					u.state = "idle"
					u.target_resource = null
				elif _move_toward(u, u.target_resource.position, delta, 34.0):
					u.state = "gathering"
					u.gather_timer = RTSData.GATHER_TIME
			"gathering":
				if u.target_resource == null or u.target_resource.dead:
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
							u.target_pos = hall.position + Vector2(0, 70)
			"return":
				var hall2 := _nearest_hall(u.faction, u.position)
				if hall2 == null:
					u.state = "idle"
				elif _move_toward(u, hall2.position + Vector2(0, 70), delta, 50.0):
					var r: Dictionary = res[u.faction]
					if u.carry_type == "gold":
						r["gold"] = int(r["gold"]) + u.carry_amount
					elif u.carry_type == "tree":
						r["wood"] = int(r["wood"]) + u.carry_amount
					if u.faction == my_faction and sound:
						sound.play("coin")
					u.carry_amount = 0
					u.carry_type = ""
					if u.target_resource != null and not u.target_resource.dead and u.target_resource.amount > 0:
						u.state = "gather_to"
					else:
						u.state = "idle"
						u.target_resource = null
			"build":
				if u.target_building == null or u.target_building.dead or not u.target_building.under_construction:
					u.state = "idle"
					u.target_building = null
				elif _move_toward(u, u.target_building.position, delta, 70.0):
					u.state = "building"
			"building":
				if u.target_building == null or u.target_building.dead or not u.target_building.under_construction:
					u.state = "idle"
					u.target_building = null
			"attack":
				_update_attack(u, delta)
		_separate(u)


func _update_attack(u: RTSUnit, delta: float) -> void:
	var target_pos := Vector2.INF
	var target_is_unit := false
	if u.target_unit != null:
		if u.target_unit.dead:
			u.target_unit = null
			u.state = "idle"
			return
		target_pos = u.target_unit.position
		target_is_unit = true
	elif u.target_building != null:
		if u.target_building.dead:
			u.target_building = null
			u.state = "idle"
			return
		target_pos = u.target_building.position
	else:
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


func _damage_unit(u: RTSUnit, amount: int) -> void:
	if u.dead:
		return
	u.hp -= amount
	if u.hp <= 0:
		u.dead = true
		units.erase(u)
		selected_units.erase(u)
		u.queue_free()


func _damage_building(b: RTSBuilding, amount: int) -> void:
	if b.dead:
		return
	b.hp -= amount
	if b.hp <= 0:
		b.dead = true
		buildings.erase(b)
		if selected_building == b:
			selected_building = null
			_refresh_command_panel()
		for u in units:
			if u.target_building == b:
				u.target_building = null
				u.state = "idle"
		b.queue_free()
		_set_message("A %s has fallen!" % String(RTSData.building_stats(b.kind).get("name", "building")))


func _remove_resource(r: RTSResource) -> void:
	r.dead = true
	resource_nodes.erase(r)
	r.queue_free()


func _update_buildings(delta: float) -> void:
	for b in buildings.duplicate():
		if b.dead:
			continue
		if b.under_construction:
			var rate := 1.0
			for u in units:
				if not u.dead and u.state == "building" and u.target_building == b:
					rate = 2.5
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
			var spawn_pos: Vector2 = b.position + Vector2(85, 0)
			var u := _spawn_unit(b.faction, kind, spawn_pos)
			u.state = "move"
			u.target_pos = b.rally_pos
			if b.faction == my_faction and sound:
				sound.play("train")
			if not b.queue.is_empty():
				b.queue_timer = float(RTSData.unit_stats(String(b.queue[0])).get("train_time", 10.0))


func _update_hud() -> void:
	var my_res: Dictionary = res[my_faction]
	gold_label.text = "Gold: %d" % int(my_res.get("gold", 0))
	wood_label.text = "Wood: %d" % int(my_res.get("wood", 0))
	supply_label.text = "Supply: %d/%d" % [supply_used(my_faction), supply_max(my_faction)]
	var mins := int(elapsed) / 60
	var secs := int(elapsed) % 60
	time_label.text = "%d:%02d" % [mins, secs]
	if selected_building != null and not selected_building.dead:
		selection_label.text = "%s — HP %d/%d  (queue: %d)" % [
			String(RTSData.building_stats(selected_building.kind).get("name", "?")),
			selected_building.hp, selected_building.max_hp, selected_building.queue.size()]


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
	if victory:
		end_label.text = "Victory! The Orc base has fallen."
		if sound:
			sound.play("victory")
	else:
		end_label.text = "Defeat — your base has fallen."
		if sound:
			sound.play("defeat")
	end_panel.visible = true
	if game_mode == "campaign" and victory and mission_index >= 0:
		campaign_unlocked = maxi(campaign_unlocked, mission_index + 2)
		RTSCampaign.save_unlocked(campaign_unlocked)
		if mission_index + 1 < RTSCampaign.missions().size():
			next_mission_button.visible = true
	if game_mode == "host" and remote_peer_id != 0:
		_send_snapshot()


# ---------------------------------------------------------------- Orc AI

func _update_ai(delta: float) -> void:
	ai_timer += delta
	ai_attack_timer -= delta
	if ai_timer < 5.0:
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
	var gold_mine: RTSResource = null
	var tree: RTSResource = null
	var tree_d := 1e9
	for r in resource_nodes:
		if r.dead:
			continue
		if r.kind == "gold" and gold_mine == null and r.position.distance_to(Vector2(2080, 350)) < 600:
			gold_mine = r
		if r.kind == "tree":
			var td := r.position.distance_to(Vector2(2080, 350))
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
	# Stage 0: pig farm once we can afford it.
	if ai_stage == 0:
		if _ai_try_build("pig_farm", Vector2(1920, 480)):
			ai_stage = 1
		return
	# Stage 1: barracks.
	if ai_stage == 1:
		if _ai_try_build("barracks", Vector2(2080, 500)):
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

@rpc("any_peer", "call_remote", "reliable")
func _rpc_order(order: Dictionary) -> void:
	if multiplayer.is_server():
		_apply_order(order)


@rpc("any_peer", "call_remote", "reliable")
func _rpc_train(building_id: int, kind: String) -> void:
	if multiplayer.is_server():
		_apply_train(building_id, kind)


@rpc("any_peer", "call_remote", "reliable")
func _rpc_place(kind: String, x: float, y: float, worker_id: int) -> void:
	if multiplayer.is_server():
		_apply_place(kind, Vector2(x, y), worker_id)


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


func _apply_snapshot(data: Dictionary) -> void:
	res = data.get("res", res)
	elapsed = float(data.get("elapsed", elapsed))
	var seen_units: Dictionary = {}
	for su in data.get("units", []):
		var d: Dictionary = su
		var id := int(d.get("id", -1))
		seen_units[id] = true
		var u := _unit_by_id(id)
		if u == null:
			u = _spawn_unit(String(d.get("faction", "human")), String(d.get("kind", "peasant")), Vector2(float(d.get("x", 0.0)), float(d.get("y", 0.0))), id)
		u.position = Vector2(float(d.get("x", 0.0)), float(d.get("y", 0.0)))
		u.hp = int(d.get("hp", u.max_hp))
		u.state = String(d.get("state", "idle"))
		u.carry_type = String(d.get("carry_type", ""))
		u.carry_amount = int(d.get("carry_amount", 0))
	for u in units.duplicate():
		if not seen_units.has(u.id):
			units.erase(u)
			selected_units.erase(u)
			u.queue_free()
	var seen_buildings: Dictionary = {}
	for sb in data.get("buildings", []):
		var d: Dictionary = sb
		var id := int(d.get("id", -1))
		seen_buildings[id] = true
		var b := _building_by_id(id)
		if b == null:
			b = _spawn_building(String(d.get("faction", "human")), String(d.get("kind", "farm")), Vector2(float(d.get("x", 0.0)), float(d.get("y", 0.0))), bool(d.get("under_construction", false)), id)
		b.position = Vector2(float(d.get("x", 0.0)), float(d.get("y", 0.0)))
		b.hp = int(d.get("hp", b.max_hp))
		b.under_construction = bool(d.get("under_construction", false))
		b.build_progress = float(d.get("build_progress", 0.0))
		b.queue = Array(d.get("queue", []))
		b.queue_timer = float(d.get("queue_timer", 0.0))
		b.rally_pos = Vector2(float(d.get("rally_x", 0.0)), float(d.get("rally_y", 0.0)))
	for b in buildings.duplicate():
		if not seen_buildings.has(b.id):
			buildings.erase(b)
			if selected_building == b:
				selected_building = null
			b.queue_free()
	var seen_resources: Dictionary = {}
	for sr in data.get("resources", []):
		var d: Dictionary = sr
		var id := int(d.get("id", -1))
		seen_resources[id] = true
		var r := _resource_by_id(id)
		if r == null:
			r = _spawn_resource(String(d.get("kind", "gold")), Vector2(float(d.get("x", 0.0)), float(d.get("y", 0.0))), int(d.get("amount", 0)), id)
		r.amount = int(d.get("amount", 0))
	for r in resource_nodes.duplicate():
		if not seen_resources.has(r.id):
			resource_nodes.erase(r)
			r.queue_free()
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
