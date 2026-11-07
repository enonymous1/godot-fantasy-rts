## Campaign data: three single-player missions, pure data.
## win: "destroy_all" (every Orc unit + building) or
## "destroy_hall" (the Orc Great Hall only).
class_name RTSCampaign
extends RefCounted

const SAVE_PATH := "user://campaign_progress.cfg"


static func missions() -> Array:
	return [
		{
			"id": "m1", "name": "Mission 1 — First Blood",
			"briefing": "The Orcs have crossed the river. Build up, train Footmen, and destroy their base. Their attacks come slowly — use the time.",
			"win": "destroy_all", "ai_attack_interval": 120.0,
			"starting_gold": 400, "starting_wood": 200,
			"orc_extra_barracks": false, "orc_extra_grunts": 0,
		},
		{
			"id": "m2", "name": "Mission 2 — The Lumber War",
			"briefing": "Gold is scarce here — you start with half. Wood is plentiful. You only need to burn their Great Hall to break them.",
			"win": "destroy_hall", "ai_attack_interval": 90.0,
			"starting_gold": 200, "starting_wood": 300,
			"orc_extra_barracks": false, "orc_extra_grunts": 0,
		},
		{
			"id": "m3", "name": "Mission 3 — The Final Stand",
			"briefing": "The Orcs are entrenched: a Barracks and two Grunts guard their hall, and their waves come fast. Destroy everything.",
			"win": "destroy_all", "ai_attack_interval": 50.0,
			"starting_gold": 400, "starting_wood": 200,
			"orc_extra_barracks": true, "orc_extra_grunts": 2,
		},
	]


static func mission(index: int) -> Dictionary:
	var ms := missions()
	if index < 0 or index >= ms.size():
		return {}
	return ms[index]


static func load_unlocked() -> int:
	var cfg := ConfigFile.new()
	if cfg.load(SAVE_PATH) != OK:
		return 1
	return maxi(1, int(cfg.get_value("campaign", "unlocked", 1)))


static func save_unlocked(count: int) -> void:
	var cfg := ConfigFile.new()
	cfg.set_value("campaign", "unlocked", maxi(1, count))
	cfg.save(SAVE_PATH)
