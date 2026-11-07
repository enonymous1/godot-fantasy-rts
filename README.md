# Fantasy RTS — Godot

A playable 2D real-time strategy game in **Godot 4.7.2**, in the style
of classic 1990s real-time strategy games — gold + lumber economy,
worker gather-and-return, farms for supply, barracks troops, fog of
war, and an AI opponent that builds up and attacks in waves.

All art is original procedural shapes drawn in code and all sound is
synthesized. No third-party assets are used.

## Play

Pick a mode on the start menu:

- **Single Battle** — you are the **Humans** (blue, south-west). The
  **Orcs** (green, north-east) are AI-controlled.
- **Campaign** — three missions with briefings and objectives; winning a
  mission unlocks the next (progress is saved). Mission 2 only needs the
  Orc Great Hall destroyed; Mission 3 starts the Orcs entrenched with a
  Barracks and two Grunts, attacking every 50 seconds.
- **Host / Join Game** — 2-player LAN, port 7777. Host plays Humans and
  simulates the game; the joiner plays Orcs, sends orders to the host,
  and receives world snapshots. ENet (UDP) is the default; tick
  *WebSocket (TCP)* if UDP is blocked on your network (also the only
  transport that works in the web export). Quick launch:
  `godot --path . -- --host` / `godot --path . -- --join=192.168.1.10`
  (add `-ws` for WebSocket: `--host-ws`, `--join-ws=…`).

Destroy the enemy base — every enemy unit and building — to win (except
Campaign Mission 2: just the Great Hall). If your base is destroyed,
you lose.

| Control | Action |
|---|---|
| Left-click / drag | Select units (box) or a building |
| Right-click | Move, attack, gather gold / chop wood, set rally point |
| WASD / arrows / screen edge | Pan camera |
| Mouse wheel | Zoom |
| Click the minimap | Jump the camera |
| M | Mute sound, F: toggle fog of war |
| Bottom panel | Train units, build Farm / Barracks |

## Economy & units

- **Peasant / Peon** (worker, 50 gold): gathers gold (10 per trip) and wood
  (10 per trip), returns it to the Town Hall / Great Hall, builds buildings.
- **Farm / Pig Farm** (100g 50w): +4 supply. **Town Hall** gives +5 supply.
- **Barracks** (150g 100w): trains **Footman / Grunt** (60g 20w, melee) and
  **Archer / Spear Thrower** (50g 30w, ranged).
- Buildings under construction need a worker: place one, the selected
  Peasant walks over and construction progresses while it is there.
- **Fog of war:** unseen ground is black, explored-but-unseen ground is
  dimmed, and enemy units/buildings only show where you can currently see
  them. **Minimap** (bottom-right) shows explored resources, buildings,
  units, and the camera viewport. **Sound** is fully synthesized
  (select, order, coin, train, build-complete, attack, victory/defeat).

## Run it

Godot 4.7.2 (no export templates needed to play in the editor):

```sh
godot --path .          # opens the editor; press F5 / ▶ to run
# or, from the editor: Project → Run
```

Windows / Web exports are in `export_presets.cfg` (untested here — the
export templates are a separate 1.28 GB download).

## Tests

Headless, no rendering:

```sh
godot --headless --path . -s res://tests/test_rts_data.gd       # 28
godot --headless --path . -s res://tests/test_scene_smoke.gd    # 19
godot --headless --path . -s res://tests/test_simulation.gd     # 7
godot --headless --path . -s res://tests/test_fog_sound.gd      # 19
godot --headless --path . -s res://tests/test_multiplayer_sync.gd # 36
godot --headless --path . -s res://tests/test_campaign.gd       # 19
godot --headless --path . --import   # project import check
```

128 checks total. Live multiplayer was verified over WebSocket on
localhost (host + client connected, client applied the host snapshot:
6 units, 4 buildings). The ENet path could not be live-tested on the
build box — its sandbox blocks UDP sends — but the host binds UDP
*:7777 and the ENet code path is identical to the verified WebSocket
one (same MultiplayerPeer/RPC/snapshot code).

## Layout

- `scenes/main.tscn` — the game scene (Node2D + `main.gd`)
- `scripts/main.gd` — game controller: map, selection, orders, economy, AI, UI, fog, multiplayer, campaign
- `scripts/rts_data.gd` — pure game data (costs / stats, testable, no nodes)
- `scripts/rts_unit.gd`, `scripts/rts_building.gd`, `scripts/rts_resource.gd` — visual + state
- `scripts/fog_layer.gd` — fog-of-war overlay drawing
- `scripts/minimap.gd` — clickable minimap
- `scripts/sound_manager.gd` — synthesized sound effects
- `scripts/campaign_data.gd` — mission data + progress save
- `tests/` — headless logic, scene, simulation, fog/sound, multiplayer-sync, and campaign tests

## Status

- v0.2.0 — fog of war, minimap, synthesized sound, 2-player LAN
  multiplayer (ENet + WebSocket), and a 3-mission campaign.
