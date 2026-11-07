## HUD + start menu for the Fantasy RTS. Owns every Control: the
## top resource bar, the message line, the bottom command panel,
## the selection rectangle, the end panel, and the whole start menu
## (single battle / campaign / host / join / WebSocket toggle).
##
## It never simulates anything. It reads game state through `game`
## (the main game node, set before add_child) and forwards button
## presses to game methods. Splitting it out of main.gd is what
## keeps the game controller a controller instead of a 1,600-line
## God object: the HUD can change layout without touching rules,
## and the rules can change without touching layout.
##
## Layout note: the bottom labels and command buttons are anchored
## to the bottom of the viewport, not placed at a fixed y for a
## 720p window — the old absolute positions (y 618 / 648) floated
## off the panel whenever the window was resized.
class_name RTSHud
extends CanvasLayer

const TOP_BAR_HEIGHT := 36
const BOTTOM_PANEL_HEIGHT := 110

# Untyped on purpose: the game node (main.gd) has no class_name,
# so there is no type to declare. Calls on it are dynamic.
var game = null

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
var sound_button: Button = null
# Start menu.
var menu_panel: PanelContainer
var mission_list: VBoxContainer
var briefing_label: Label
var mission_start_button: Button
var selected_mission: int = -1
var ip_edit: LineEdit

# Dirty-check cache: rewriting label text every frame forces a
# layout pass for text that has not changed. Only set what moved.
var _last_gold := ""
var _last_wood := ""
var _last_supply := ""
var _last_time := ""
var _last_selection := ""


func _ready() -> void:
	_build_ui()
	_build_menu()


func _build_ui() -> void:
	var top := ColorRect.new()
	top.color = Color(0.08, 0.08, 0.12, 0.9)
	top.set_anchors_preset(Control.PRESET_TOP_WIDE)
	top.offset_bottom = TOP_BAR_HEIGHT
	add_child(top)

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
	bottom.offset_top = -BOTTOM_PANEL_HEIGHT
	add_child(bottom)

	selection_label = Label.new()
	selection_label.text = "Nothing selected"
	selection_label.add_theme_font_size_override("font_size", 16)
	selection_label.set_anchors_preset(Control.PRESET_BOTTOM_LEFT)
	selection_label.offset_left = 12
	selection_label.offset_top = -BOTTOM_PANEL_HEIGHT + 6
	selection_label.offset_right = 500
	selection_label.offset_bottom = -BOTTOM_PANEL_HEIGHT + 26
	add_child(selection_label)

	command_box = HBoxContainer.new()
	command_box.set_anchors_preset(Control.PRESET_BOTTOM_LEFT)
	command_box.offset_left = 12
	command_box.offset_top = -BOTTOM_PANEL_HEIGHT + 38
	command_box.offset_right = 900
	command_box.offset_bottom = -8
	command_box.add_theme_constant_override("separation", 8)
	add_child(command_box)

	selection_rect = ColorRect.new()
	selection_rect.color = Color(0.2, 0.9, 0.2, 0.15)
	selection_rect.visible = false
	add_child(selection_rect)

	end_panel = PanelContainer.new()
	end_panel.set_anchors_preset(Control.PRESET_CENTER)
	end_panel.visible = false
	add_child(end_panel)
	var vbox := VBoxContainer.new()
	end_panel.add_child(vbox)
	end_label = Label.new()
	end_label.add_theme_font_size_override("font_size", 28)
	vbox.add_child(end_label)
	var restart := Button.new()
	restart.text = "Play again"
	restart.pressed.connect(game._on_restart_pressed)
	vbox.add_child(restart)
	next_mission_button = Button.new()
	next_mission_button.text = "Next mission"
	next_mission_button.visible = false
	next_mission_button.pressed.connect(game._on_next_mission_pressed)
	vbox.add_child(next_mission_button)

	sound_button = Button.new()
	sound_button.text = "Sound: On"
	sound_button.set_anchors_preset(Control.PRESET_TOP_RIGHT)
	sound_button.offset_left = -200
	sound_button.offset_right = -12
	sound_button.offset_top = 4
	sound_button.offset_bottom = 32
	sound_button.pressed.connect(_on_sound_button_pressed)
	add_child(sound_button)


func _make_label(pos: Vector2, text: String) -> Label:
	var l := Label.new()
	l.position = pos
	l.text = text
	l.add_theme_font_size_override("font_size", 16)
	add_child(l)
	return l


func _build_menu() -> void:
	menu_panel = PanelContainer.new()
	menu_panel.set_anchors_preset(Control.PRESET_CENTER)
	add_child(menu_panel)
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
	single.pressed.connect(game._start_single)
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
		var locked := i >= int(game.get("campaign_unlocked"))
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
	host.pressed.connect(game._start_host)
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
	ws_check.toggled.connect(func(on: bool) -> void: game.set("use_websocket", on))
	vbox.add_child(ws_check)
	var note := Label.new()
	note.text = "Multiplayer: 2 players on the same network, port 7777. Host simulates; joiner sends orders. Use WebSocket if UDP is blocked on your network."
	note.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	note.custom_minimum_size = Vector2(420, 40)
	vbox.add_child(note)


func hide_menu() -> void:
	menu_panel.visible = false


func set_message(text: String) -> void:
	if message_label:
		message_label.text = text


func set_sound_label(muted: bool) -> void:
	if sound_button:
		sound_button.text = "Sound: Off" if muted else "Sound: On"


# The resource/time bar. Called every frame by the game, but only
# writes label text when the value actually changed (see the
# _last_* cache above) — otherwise every frame pays for a layout.
func update_hud() -> void:
	if game == null:
		return
	var my_faction: String = String(game.get("my_faction"))
	var my_res: Dictionary = (game.get("res") as Dictionary).get(my_faction, {})
	var gold := "Gold: %d" % int(my_res.get("gold", 0))
	if gold != _last_gold:
		_last_gold = gold
		gold_label.text = gold
	var wood := "Wood: %d" % int(my_res.get("wood", 0))
	if wood != _last_wood:
		_last_wood = wood
		wood_label.text = wood
	var supply := "Supply: %d/%d" % [game.call("supply_used", my_faction), game.call("supply_max", my_faction)]
	if supply != _last_supply:
		_last_supply = supply
		supply_label.text = supply
	var mins := int(float(game.get("elapsed"))) / 60
	var secs := int(float(game.get("elapsed"))) % 60
	var time_text := "%d:%02d" % [mins, secs]
	if time_text != _last_time:
		_last_time = time_text
		time_label.text = time_text
	var selected_building = game.get("selected_building")
	if selected_building != null and not bool(selected_building.get("dead")):
		var sel := "%s — HP %d/%d  (queue: %d)" % [
			String(RTSData.building_stats(String(selected_building.get("kind"))).get("name", "?")),
			int(selected_building.get("hp")), int(selected_building.get("max_hp")),
			(selected_building.get("queue") as Array).size()]
		if sel != _last_selection:
			_last_selection = sel
			selection_label.text = sel


func show_end(victory: bool, show_next: bool) -> void:
	end_label.text = "Victory! The enemy base has fallen." if victory else "Defeat — your base has fallen."
	end_panel.visible = true
	next_mission_button.visible = show_next


# The command panel is rebuilt on every selection change. It is
# driven by my_faction, not by a hardcoded "human": in client mode
# the player is the Orcs, and the old code never showed them a
# train panel at all. Kinds and costs come from RTSData, so the
# button text can never drift from the real tuning.
func refresh_command_panel() -> void:
	# free(), not queue_free(): the old buttons must be gone
	# before the new ones are added. queue_free only frees at the
	# frame boundary, so two refreshes in one frame stacked stale
	# buttons on top of the new ones.
	for c in command_box.get_children():
		c.free()
	var my_faction: String = String(game.get("my_faction"))
	var selected_building = game.get("selected_building")
	var selected_units: Array = game.get("selected_units")
	if selected_building != null and String(selected_building.get("faction")) == my_faction and not bool(selected_building.get("under_construction")):
		var bkind := String(selected_building.get("kind"))
		if bkind == RTSData.hall_kind(my_faction):
			_add_train_command(RTSData.worker_kind(my_faction), "train_worker")
		elif bkind == "barracks":
			_add_train_command(RTSData.melee_kind(my_faction), "train_melee")
			_add_train_command(RTSData.ranged_kind(my_faction), "train_ranged")
		var sel := "%s — HP %d/%d  (queue: %d)" % [
			String(RTSData.building_stats(bkind).get("name", "?")),
			int(selected_building.get("hp")), int(selected_building.get("max_hp")),
			(selected_building.get("queue") as Array).size()]
		_last_selection = sel
		selection_label.text = sel
		return
	if selected_units.is_empty():
		selection_label.text = "Nothing selected"
		return
	var worker_count := 0
	for u in selected_units:
		if RTSData.is_worker(String(u.get("kind"))):
			worker_count += 1
	selection_label.text = "%d unit(s) selected" % selected_units.size()
	if worker_count > 0:
		_add_build_command(RTSData.farm_kind(my_faction), "build_farm")
		_add_build_command("barracks", "build_barracks")
	_add_command("Stop", "stop")


func _add_train_command(kind: String, action: String) -> void:
	var cost: Dictionary = RTSData.unit_cost(kind)
	_add_command("Train %s (%dg %dw)" % [
		String(RTSData.unit_stats(kind).get("name", "?")),
		int(cost.get("gold", 0)), int(cost.get("wood", 0))], action)


func _add_build_command(kind: String, action: String) -> void:
	var cost: Dictionary = RTSData.building_cost(kind)
	_add_command("Build %s (%dg %dw)" % [
		String(RTSData.building_stats(kind).get("name", "?")),
		int(cost.get("gold", 0)), int(cost.get("wood", 0))], action)


func _add_command(text: String, action: String) -> void:
	var b := Button.new()
	b.text = text
	b.pressed.connect(_on_command_pressed.bind(action))
	command_box.add_child(b)


func _on_command_pressed(action: String) -> void:
	if bool(game.get("game_over")):
		return
	var my_faction: String = String(game.get("my_faction"))
	match action:
		"train_worker":
			game._train_unit(RTSData.worker_kind(my_faction))
		"train_melee":
			game._train_unit(RTSData.melee_kind(my_faction))
		"train_ranged":
			game._train_unit(RTSData.ranged_kind(my_faction))
		"build_farm":
			game.set("placing_kind", RTSData.farm_kind(my_faction))
			set_message("Placing %s — left-click to place, right-click to cancel." % String(RTSData.building_stats(RTSData.farm_kind(my_faction)).get("name", "?")))
		"build_barracks":
			game.set("placing_kind", "barracks")
			set_message("Placing Barracks — left-click to place, right-click to cancel.")
		"stop":
			for u in game.get("selected_units"):
				u.set("state", "idle")
				u.set("target_unit", null)
				u.set("target_building", null)
				u.set("target_resource", null)


func _on_mission_picked(index: int) -> void:
	selected_mission = index
	var m := RTSCampaign.mission(index)
	briefing_label.text = String(m.get("briefing", ""))
	mission_start_button.disabled = false
	var sound = game.get("sound")
	if sound:
		sound.play("click")


func _on_mission_start_pressed() -> void:
	if selected_mission >= 0:
		game._start_campaign(selected_mission)


func _on_sound_button_pressed() -> void:
	var sound = game.get("sound")
	if sound:
		set_sound_label(bool(sound.toggle_mute()))


func _on_join_pressed() -> void:
	game._start_join(ip_edit.text.strip_edges())
