# Fantasy RTS — Godot

## Description

A playable 2D real-time strategy game in **Godot 4.7.2**, in the style
of classic 1990s real-time strategy games. You are the **Humans**
(blue, south-west); the **Orcs** (green, north-east) are AI-controlled
— or, in a 2-player LAN game, played by the joining player.

- **Economy:** gold + lumber, worker gather-and-return (10 per trip),
  farms for supply, halls for supply, barracks that train troops.
- **Combat:** Footmen/Grunt (melee) and Archers/Spear Throwers
  (ranged), worker-built buildings, rally points, attack-move waves.
- **Fog of war:** unseen ground is black, explored-but-unseen ground
  is dimmed, and enemy units/buildings only show where you can
  currently see them. Toggle with F.
- **Minimap:** bottom-right, click/drag to jump the camera; shows
  explored resources, buildings, units, and the camera viewport.
- **Sound:** fully synthesized (no audio files) — select, order,
  coin, train, build-complete, attack, victory/defeat. Mute with M.
- **Multiplayer:** 2-player LAN, port 7777, host-authoritative.
  ENet (UDP) by default, WebSocket (TCP) fallback.
- **Campaign:** three missions with briefings and objectives;
  winning a mission unlocks the next (progress is saved).

All art is original procedural shapes drawn in code and all sound is
synthesized. No third-party assets are used.

<!-- Screenshots: see docs/visual-assets.md for the shot list.
     Nothing is linked here until real captures exist — no mockups.
     1. docs/images/menu.png goes here (start menu).
     8. docs/images/wave-attack.gif goes here (Orc wave, 10–15 s). -->

## Prerequisites

- **Godot 4.7.2** (editor or headless binary). The project targets
  `config/features=PackedStringArray("4.7", "GL Compatibility")`.
  - Windows/macOS/Linux: download from
    [godotengine.org](https://godotengine.org/download) (4.7.2,
    standard build — no .NET needed).
  - Headless Linux: the `Godot_v4.7.2-stable_linux.x86_64` binary.
- **No other dependencies.** No export templates are needed to play
  in the editor or run the tests (see Deployment for exports).
- **Multiplayer:** both players on the same network; port 7777
  reachable (UDP for ENet, TCP for WebSocket). Use WebSocket if UDP
  is blocked on your network.
- **Tests:** nothing extra — they run headless with the same binary.

## Installation

```sh
git clone https://github.com/enonymous1/godot-fantasy-rts.git
cd godot-fantasy-rts
godot --headless --path . --import   # generates .godot/ (first run only)
```

There is no package manager step, no build step, and no vendored
third-party code. The repo is the whole game: `scenes/`,
`scripts/`, `tests/`, `export_presets.cfg`, `project.godot`.

## Local Development

### Play it

```sh
godot --path .          # opens the editor; press F5 / ▶ to run
# or, from the editor: Project → Run
```

Pick a mode on the start menu:

- **Single Battle** — you are the Humans; the Orcs are AI.
- **Campaign** — three missions (see below); winning unlocks the next.
- **Host / Join Game** — 2-player LAN, port 7777. Host plays Humans
  and simulates; the joiner plays Orcs, sends orders to the host,
  and receives world snapshots. Tick *WebSocket (TCP)* if UDP is
  blocked. Quick launch:
  `godot --path . -- --host` / `godot --path . -- --join=192.168.1.10`
  (add `-ws` for WebSocket: `--host-ws`, `--join-ws=…`).

Destroy the enemy base — every enemy unit and building — to win
(except Campaign Mission 2: just the Great Hall). If your base is
destroyed, you lose.

| Control | Action |
|---|---|
| Left-click / drag | Select units (box) or a building |
| Right-click | Move, attack, gather gold / chop wood, set rally point |
| WASD / arrows / screen edge | Pan camera |
| Mouse wheel | Zoom |
| Click the minimap | Jump the camera |
| M | Mute sound, F: toggle fog of war |
| Bottom panel | Train units, build Farm / Barracks |

<!-- docs/images/early-economy.png goes here (early economy).
     docs/images/minimap.png goes here (minimap + camera). -->

### Campaign

- **Mission 1 — First Blood:** destroy everything. Orc attacks come
  slowly (every 120 s) — use the time.
- **Mission 2 — The Lumber War:** you start with half gold (200).
  You only need to burn the Orc Great Hall to win.
- **Mission 3 — The Final Stand:** the Orcs start entrenched (a
  Barracks and two Grunts) and attack every 50 s.

Progress is saved to `user://campaign_progress.cfg` (outside the
repo, in Godot's user dir).

<!-- docs/images/campaign-briefing.png goes here.
     docs/images/victory.png goes here (end screen). -->

### Economy & units

- **Peasant / Peon** (worker, 50 gold): gathers gold (10 per trip)
  and wood (10 per trip), returns it to the Town Hall / Great Hall,
  builds buildings.
- **Farm / Pig Farm** (100g 50w): +4 supply. **Town Hall** gives +5.
- **Barracks** (150g 100w): trains **Footman / Grunt** (60g 20w,
  melee) and **Archer / Spear Thrower** (50g 30w, ranged).
- Buildings under construction need a worker: place one, the
  selected Peasant walks over and construction progresses while it
  is there (2.5x with a worker on site).
- **Fog of war:** unseen ground is black, explored-but-unseen
  ground is dimmed, and enemy units/buildings only show where you
  can currently see them.

<!-- docs/images/fog-of-war.png goes here (fog of war). -->
<!-- docs/images/lan-two-players.png goes here (2-player LAN). -->

### Run the tests

Headless, no rendering — 161 checks total:

```sh
godot --headless --path . -s res://tests/test_rts_data.gd       # 28
godot --headless --path . -s res://tests/test_scene_smoke.gd    # 19
godot --headless --path . -s res://tests/test_simulation.gd     # 7
godot --headless --path . -s res://tests/test_fog_sound.gd      # 19
godot --headless --path . -s res://tests/test_multiplayer_sync.gd # 36
godot --headless --path . -s res://tests/test_campaign.gd       # 19
godot --headless --path . -s res://tests/test_combat_cleanup.gd  # 16
godot --headless --path . -s res://tests/test_review_fixes.gd   # 17
```

CI (`.github/workflows/ci.yml`) runs the import plus every test file
on push to `main` and on pull requests.

Live multiplayer was verified over WebSocket on localhost (host +
client connected, client applied the host snapshot: 6 units,
4 buildings). The ENet path could not be live-tested on the build
box — its sandbox blocks UDP sends — but the host binds UDP *:7777
and the ENet code path is identical to the verified WebSocket one
(same MultiplayerPeer/RPC/snapshot code).

### Change the tuning

All game tuning lives in one place, `scripts/rts_data.gd`
(`RTSData`): unit/building costs and stats, carry amounts, gather
time, sight, separation, stop distances, snapshot interval, AI tick.
Camera and UI constants live at the top of `scripts/main.gd`.
Change a number there and the tests still describe the same game —
`tests/test_rts_data.gd` pins the costs/stats, so update the test
if you intentionally retune.

### Layout

- `scenes/main.tscn` — the game scene (Node2D + `main.gd`)
- `scripts/main.gd` — game controller and composition root: map,
  selection, orders, economy, simulation, AI, fog, camera, input,
  multiplayer, campaign flow
- `scripts/hud.gd` — all UI: top bar, message line, bottom command
  panel, selection rectangle, end panel, start menu
- `scripts/rts_data.gd` — pure game data (costs / stats / tuning,
  testable, no nodes)
- `scripts/rts_unit.gd`, `scripts/rts_building.gd`,
  `scripts/rts_resource.gd` — visual + state for each entity
- `scripts/fog_layer.gd` — fog-of-war overlay drawing
- `scripts/minimap.gd` — clickable minimap
- `scripts/sound_manager.gd` — synthesized sound effects
- `scripts/campaign_data.gd` — mission data + progress save
- `tests/` — headless logic, scene, simulation, fog/sound,
  multiplayer-sync, campaign, combat-cleanup, and review-fixes tests
- `docs/architecture.mmd` — Mermaid diagram of the above
  (GitHub renders it in the browser)
- `docs/visual-assets.md` — the screenshot/GIF shot list and where
  each one goes in this README
- `REVIEW.md` — the 2026-11-07 staff review: findings, what was
  fixed in v0.3.0, and what was deliberately left alone

## Deployment

### Windows / Web exports

Presets live in `export_presets.cfg` (Windows Desktop, Web).
They are **untested** — the export templates are a separate
1.28 GB download and were not installed on the build box.

```sh
# Install the Godot 4.7.2 export templates first (Editor:
# Editor → Manage Export Templates, or download from the
# 4.7.2 release), then:
godot --headless --path . --export-release "Windows Desktop" build/godot-fantasy-rts.exe
godot --headless --path . --export-release "Web" build/web/index.html
```

Notes:

- The Web export only supports the WebSocket transport (raw UDP is
  unavailable in the browser) — the in-game WebSocket checkbox
  covers this.
- The Windows export needs no extra files: art is procedural and
  sound is synthesized, so there are no asset bundles to ship.
- Campaign progress saves to the Godot user dir on the player's
  machine, not next to the executable.

### Publishing the repo

The repo is public-safe: all original code, procedural art,
synthesized sound, no third-party assets or trademarked names.
Pushing is a normal `git push` from the included `.git` history
(single clean commit + the review commit on `main`, no remote).

## Status

- **v0.3.0 (2026-11-07)** — staff-review pass: HUD extracted to
  `scripts/hud.gd`; fixed a dangling-target bug after unit/resource
  death, the Orc player being unable to select/train, and the
  multiplayer trust boundary (see `REVIEW.md`); per-frame redraw
  storm replaced with dirty/quantized redraws; named tuning
  constants; CI added; README rewritten.
- **v0.2.0** — fog of war, minimap, synthesized sound, 2-player LAN
  multiplayer (ENet + WebSocket), and a 3-mission campaign.
