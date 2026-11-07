## Pure game data for the Fantasy RTS.
## No nodes, no scene state — everything here is unit-testable.
## Costs / stats are the game's own tuning, following the
## classic RTS loop (gold + lumber, supply from farms, worker
## gather-and-return, barracks troops).
class_name RTSData
extends RefCounted

const FACTION_HUMAN := "human"
const FACTION_ORC := "orc"

const WORLD_SIZE := Vector2(2400, 1600)
const TILE := 48.0

const GOLD_CARRY := 10
const WOOD_CARRY := 10
const GATHER_TIME := 1.0

# Simulation tuning. Keep every magic number here (or in main.gd's
# camera/UI constants) so balancing is a one-line change, not a
# hunt through the simulation code.
const BUILDING_SIGHT := 260.0
const SEPARATION_DIST := 24.0
const MOVE_STOP_DIST := 6.0
const GATHER_STOP_DIST := 34.0
const RETURN_STOP_DIST := 50.0
const BUILD_STOP_DIST := 70.0
const BUILD_RATE_WITH_WORKER := 2.5
const TRAIN_SPAWN_OFFSET := Vector2(85, 0)
const HALL_DROPOFF_OFFSET := Vector2(0, 70)
const MAX_TRAIN_QUEUE := 5
const SNAPSHOT_INTERVAL := 0.15
const AI_TICK := 5.0
const FOG_RECOMPUTE_INTERVAL := 0.25


static func unit_stats(kind: String) -> Dictionary:
	match kind:
		"peasant":
			return {"name": "Peasant", "hp": 30, "speed": 95.0, "damage": 3, "range": 20.0, "cooldown": 1.0, "sight": 200.0, "train_time": 8.0}
		"peon":
			return {"name": "Peon", "hp": 30, "speed": 95.0, "damage": 3, "range": 20.0, "cooldown": 1.0, "sight": 200.0, "train_time": 8.0}
		"footman":
			return {"name": "Footman", "hp": 60, "speed": 72.0, "damage": 9, "range": 22.0, "cooldown": 1.1, "sight": 220.0, "train_time": 12.0}
		"grunt":
			return {"name": "Grunt", "hp": 70, "speed": 68.0, "damage": 10, "range": 22.0, "cooldown": 1.2, "sight": 220.0, "train_time": 12.0}
		"archer":
			return {"name": "Archer", "hp": 35, "speed": 78.0, "damage": 7, "range": 190.0, "cooldown": 1.3, "sight": 260.0, "train_time": 10.0}
		"spearman":
			return {"name": "Spear Thrower", "hp": 38, "speed": 75.0, "damage": 7, "range": 180.0, "cooldown": 1.3, "sight": 260.0, "train_time": 10.0}
	return {}


static func unit_cost(kind: String) -> Dictionary:
	match kind:
		"peasant", "peon":
			return {"gold": 50, "wood": 0, "supply": 1}
		"footman", "grunt":
			return {"gold": 60, "wood": 20, "supply": 1}
		"archer", "spearman":
			return {"gold": 50, "wood": 30, "supply": 1}
	return {"gold": 0, "wood": 0, "supply": 0}


static func building_stats(kind: String) -> Dictionary:
	match kind:
		"town_hall":
			return {"name": "Town Hall", "hp": 1500, "supply": 5, "build_time": 0.0}
		"great_hall":
			return {"name": "Great Hall", "hp": 1500, "supply": 5, "build_time": 0.0}
		"farm":
			return {"name": "Farm", "hp": 400, "supply": 4, "build_time": 20.0}
		"pig_farm":
			return {"name": "Pig Farm", "hp": 400, "supply": 4, "build_time": 20.0}
		"barracks":
			return {"name": "Barracks", "hp": 800, "supply": 0, "build_time": 30.0}
	return {}


static func building_cost(kind: String) -> Dictionary:
	match kind:
		"farm", "pig_farm":
			return {"gold": 100, "wood": 50}
		"barracks":
			return {"gold": 150, "wood": 100}
		"town_hall", "great_hall":
			return {"gold": 0, "wood": 0}
	return {"gold": 0, "wood": 0}


static func worker_kind(faction: String) -> String:
	return "peasant" if faction == FACTION_HUMAN else "peon"


static func hall_kind(faction: String) -> String:
	return "town_hall" if faction == FACTION_HUMAN else "great_hall"


static func farm_kind(faction: String) -> String:
	return "farm" if faction == FACTION_HUMAN else "pig_farm"


static func melee_kind(faction: String) -> String:
	return "footman" if faction == FACTION_HUMAN else "grunt"


static func ranged_kind(faction: String) -> String:
	return "archer" if faction == FACTION_HUMAN else "spearman"


static func can_afford(res: Dictionary, cost: Dictionary) -> bool:
	return int(res.get("gold", 0)) >= int(cost.get("gold", 0)) and int(res.get("wood", 0)) >= int(cost.get("wood", 0))


static func pay(res: Dictionary, cost: Dictionary) -> void:
	res["gold"] = int(res.get("gold", 0)) - int(cost.get("gold", 0))
	res["wood"] = int(res.get("wood", 0)) - int(cost.get("wood", 0))


static func starting_resources() -> Dictionary:
	return {"gold": 400, "wood": 200}


static func supply_max(buildings: Array) -> int:
	var total := 0
	for b in buildings:
		# Buildings arrive as RTSBuilding nodes from the game and
		# as plain Dictionaries from the data tests. Node2D.get()
		# takes one argument (no default), so read the kind by
		# type instead of calling .get("kind", "") on both.
		var kind := ""
		if b is RTSBuilding:
			kind = (b as RTSBuilding).kind
		elif b is Dictionary:
			kind = String((b as Dictionary).get("kind", ""))
		total += int(RTSData.building_stats(kind).get("supply", 0))
	return total


static func is_worker(kind: String) -> bool:
	return kind == "peasant" or kind == "peon"


static func is_ranged(kind: String) -> bool:
	return kind == "archer" or kind == "spearman"


static func is_known_unit(kind: String) -> bool:
	return not unit_stats(kind).is_empty()


static func is_known_building(kind: String) -> bool:
	return not building_stats(kind).is_empty()


# What a building can train: halls train workers, barracks train
# combat units. Used by the host to validate train orders, so a
# client cannot queue a Grunt from a Town Hall (or a bogus kind).
static func can_train_at(building_kind: String, unit_kind: String) -> bool:
	if not is_known_unit(unit_kind):
		return false
	if building_kind == "town_hall" or building_kind == "great_hall":
		return is_worker(unit_kind)
	if building_kind == "barracks":
		return not is_worker(unit_kind)
	return false


# Only farms and barracks are placeable by a worker. Halls are
# map fixtures: letting an order spawn one would be a free building.
static func is_placeable(kind: String) -> bool:
	return kind == "farm" or kind == "pig_farm" or kind == "barracks"
