# Staff review — godot-fantasy-rts (2026-11-07)

Reviewer role: staff-level software engineer / open-source maintainer.
Scope: the whole repo at v0.2.0 (commit `a2cdaea`), read end to end —
`scripts/main.gd` (1,664 lines), `rts_data.gd`, `rts_unit.gd`,
`rts_building.gd`, `rts_resource.gd`, `fog_layer.gd`, `minimap.gd`,
`sound_manager.gd`, `campaign_data.gd`, `tests/` (128 checks), README,
`project.godot`, `export_presets.cfg`. No CI existed before this review.

Every finding below was verified in the code before it was written up;
findings marked **Applied** were fixed in this same pass (v0.3.0) and are
pinned by tests where a test can observe them. Findings marked **Noted**
are real but deliberately left for a later pass, with the reason given.

## P0 — real bugs

### 1. Dangling target references after a unit or resource dies — **Applied**
`main.gd` `_damage_building` clears attackers' `target_building`, but
`_damage_unit` did **not** clear `target_unit`, `_remove_resource` did
**not** clear gatherers' `target_resource`, and the snapshot-removal path
cleared nothing. After the victim is `queue_free`d, the next frame
`_update_attack` / `_update_units` reads `.dead` on a freed instance
("previously freed instance" error) and the attacker/gatherer stalls in
its `attack` / `gather_to` state forever.

Why it was never caught: the headless test harness calls
`_main._process(0.1)` in a loop with no frame boundary, so `queue_free`
never actually frees anything inside a test — the bug only bites in a
real running game, one frame after a kill.

Fix: one removal path per entity type — `_remove_unit`,
`_remove_building`, `_remove_resource` — each clears every reference to
the victim (attackers, gatherers, builders, selection), erases it from
its array, and frees it. `_damage_unit` / `_damage_building` /
`_apply_snapshot` all go through them. Every read of a target also
guards with `is_instance_valid`. Pinned by `tests/test_combat_cleanup.gd`,
which steps across a real frame boundary so the free actually happens.

### 2. The Orc (client) player cannot select units or train — **Applied**
`_finish_selection` (box-select and click-select) and
`_refresh_command_panel` hardcoded `PLAYER_FACTION` (`"human"`) instead
of `my_faction`. In client mode (`my_faction == "orc"`) no Orc unit could
ever be selected, the Barracks panel never showed, and the train actions
hardcoded human kinds (`peasant` / `footman` / `archer`) — so an Orc
player could not train at all, and `_train_unit` would have spawned a
human Peasant from an Orc Great Hall if called directly.

Fix: selection and the command panel use `my_faction`, and train/build
actions use the faction-appropriate kinds
(`RTSData.worker_kind` / `melee_kind` / `ranged_kind` /
`hall_kind` / `farm_kind`). Pinned by `tests/test_review_fixes.gd`
(Orc selection + Orc Barracks train panel + grunt queued).

### 3. No trust boundary on multiplayer RPCs — **Applied**
`_rpc_order` / `_rpc_train` / `_rpc_place` only checked
`multiplayer.is_server()`. Any peer could order the other faction's
units, train from the other faction's buildings, and — because
`_apply_place` accepted any kind and `building_cost("town_hall")` is 0 —
place a free Town Hall anywhere.

Fix: each RPC derives the sender's faction from
`multiplayer.get_remote_sender_id()` (server = human, anyone else =
orc) and passes it to `_apply_order` / `_apply_train` / `_apply_place`.
Orders apply only to the sender's own units, training only to the
sender's own buildings and only kinds that building can train
(hall → worker, barracks → melee/ranged), placing only farm/barracks
and only by the sender's own worker. Local single-player calls pass no
faction and are unfiltered, so existing behaviour is unchanged.
Pinned by `tests/test_review_fixes.gd`.

## P1 — correctness / robustness

### 4. Unknown kinds fail silently — **Applied**
`RTSData.unit_stats` / `building_stats` return `{}` for an unknown kind
and `unit_cost` / `building_cost` return zeros. `_spawn_unit("bogus")`
created a 30 HP peasant-looking unit, `_apply_train("bogus")` paid 0 and
queued it, `_apply_place("town_hall")` built a free hall.

Fix: `RTSUnit.setup` / `RTSBuilding.setup` / `RTSResource.setup` return
`bool` (false on an unknown kind); `_spawn_unit` / `_spawn_building` /
`_spawn_resource` return `null` and `push_error` on failure, and every
caller handles `null` (training queue, snapshot, campaign spawns).
`_apply_train` and `_apply_place` reject unknown kinds up front.
Pinned by `tests/test_review_fixes.gd`.

### 5. Snapshot data is trusted wholesale — **Applied**
`_apply_snapshot` did `var d: Dictionary = su` (errors if an entry is
not a Dictionary), called `float()` / `int()` on unvalidated values, and
replaced `res` with whatever the peer sent. One malformed snapshot
could crash the client.

Fix: per-entry type checks (non-Dictionary entries skipped), kind
validated against `RTSData` (unknown kinds skipped), `hp` / `amount`
clamped to sane ranges, `res` replaced only if it has the expected
human/orc dictionary shape. Pinned by `tests/test_review_fixes.gd`
(corrupt snapshot with a string entry, an unknown kind, and a negative
HP is applied without error and the good entries land).

### 6. Camera pans while typing in the Host-IP field — **Applied**
`_update_camera` reads `Input.is_key_pressed(KEY_W/A/S/D)` globally,
so typing `a` / `s` / `d` / `w` into the join IP `LineEdit` also panned
the camera. Edge-pan also fired while the mouse hovered the bottom
command panel (the `vp.y - 132` threshold overlaps the 110 px panel).

Fix: skip keyboard panning while a `LineEdit` has focus; skip edge
panning while the mouse is over the bottom panel strip. Verified by
inspection only — headless tests cannot simulate key focus, so this
needs a real play session to confirm by feel.

### 7. Victory text is wrong for an Orc win — **Applied**
`_end_game` always wrote "Victory! The Orc base has fallen." — including
when the winner is the Orcs and you *are* the Orcs (client mode).
Fix: the text is now "Victory! The enemy base has fallen." /
"Defeat — your base has fallen."

## P1 — performance

### 8. Per-frame redraw storm — **Applied**
- `main.gd` `_process` called `queue_redraw()` every frame, but
  `_draw` only paints static ground + grid (84 draw calls) and the
  placement ghost. Nothing on the map moves in local space.
- Every `RTSUnit` / `RTSBuilding` / `RTSResource` called
  `queue_redraw()` in its own `_process` every frame.
- `RTSFogLayer` redrew up to ~1,650 rects every frame even when the
  fog had not changed; `RTSMinimap` redrew every frame.

Fix: the map redraws only while placing (ghost follows the mouse);
units/buildings redraw only when their appearance state changes
(HP, selection, carry, construction progress quantized to 5%,
training timer quantized to 0.1 s); resources draw once (their
appearance never changes); the fog layer redraws only after a fog
recompute or a toggle; the minimap redraws at 10 Hz. `_update_hud`
is now dirty: label text is only rewritten when the value changed.
No behaviour change — same pixels, far fewer canvas rebuilds.

### 9. `_separate()` is O(n²) per frame — **Noted, not fixed**
It runs for every unit and loops every other unit. Fine at ~40 units
(1,600 distance checks/frame); it becomes the scaling ceiling past
~150 units. The fix is a spatial hash or a uniform grid; that is a
bigger change than this pass warrants and would need its own perf test.

## P1 — architecture / DRY / SOLID

### 10. `main.gd` is a 1,664-line God object — **Applied (HUD split)**
One file held the game controller, map building, economy, simulation,
AI, multiplayer, fog, camera, input, drawing, *and* all UI (top bar,
command panel, start menu, end panel). Nothing else could be tested or
reused without loading the whole game.

Fix: the UI is now `scripts/hud.gd` (`class_name RTSHud`, a
`CanvasLayer`). It owns the top bar, message line, bottom panel,
command buttons, selection rectangle, end panel, and the whole start
menu (single / campaign / host / join / WebSocket toggle). `main.gd`
keeps game flow (`_hide_menu`, `_start_*`, `_on_next_mission_pressed`)
and calls the HUD through a thin surface (`hud.set_message`,
`hud.refresh_command_panel`, `hud.update_hud`, `hud.show_end`).
`main.gd` is a composition root again: it builds camera, map, fog,
minimap, sound, HUD, and wires them together.

The one test that touched UI (`test_multiplayer_sync.gd` used
`_client.menu_panel`) now goes through `_client.hud.menu_panel`.
Nothing else in the tests changed.

The panel rebuild also switched from `queue_free()` to `free()`:
the old buttons must be gone before the new ones are added, and
`queue_free()` only frees at the frame boundary — two refreshes in
one frame stacked stale buttons on top of the new ones. (Caught by
the new review-fixes test, which refreshes twice in one frame.)

### 11. Duplicate nearest-enemy search — **Applied**
`_nearest_enemy_unit(pos, dist)` and `_nearest_enemy_unit_for(faction,
pos, dist)` were the same loop with one condition different. The
first now delegates to the second with `my_faction`.

### 12. Magic numbers everywhere — **Applied**
Building sight `260.0`, camera speed `550.0`, separation `24.0`,
gather/return/build stop distances `34/50/70`, move stop `6.0`,
snapshot interval `0.15`, AI tick `5.0`, build rate `2.5`, spawn offset
`(85, 0)`, hall drop-off `(0, 70)`, edge margin `12`, top bar `36`,
bottom panel `110`, queue cap `5`. All are now named constants in
`RTSData` (game tuning) or `main.gd` (camera/UI constants), so tuning
is a one-line change in one place.

### 13. AI coupled to fixed map coordinates — **Applied**
`_ai_assign_workers`, `_ai_try_build`, and `_ai_attack_wave` hardcoded
the Orc base (`2080, 350`), farm/barracks spots, and the Human base
(`320, 1250`). Moving a base on the map would silently break the AI.

Fix: `_ai_base_pos()` derives the base from the Orc Great Hall
position (falling back to the old coordinates if there is no hall
yet), and farm/barracks spots are offsets from it. The offsets were
chosen so the built positions are byte-identical to before
(farm `1920, 480`, barracks `2080, 500`), so AI behaviour is
unchanged; the attack destination is the nearest Human hall, falling
back to the old coordinates.

### 14. Stale comment in `rts_unit.gd` — **Applied**
The `state` comment listed `chop` / `chopping` states that do not
exist anywhere. It now lists the real state machine:
`idle / move / attack_move / gather_to / gathering / return /
build / building / attack`.

### 15. Duplicated supply-max logic — **Applied**
`RTSData.supply_max(buildings)` and `main.gd` `supply_max(faction)`
computed the same sum two ways. `main.supply_max` now filters by
faction and delegates to `RTSData.supply_max`.

## P2 — docs, tests, CI

### 16. README lacked the standard sections — **Applied**
The old README had "Play / Economy / Run it / Tests / Layout /
Status" but no Prerequisites, Installation, Local Development, or
Deployment. Rewritten to the requested structure (see `README.md`):
Description, Prerequisites, Installation, Local Development
(how to run, how to test, how to change tuning), Deployment
(Windows/Web exports, what is still untested), plus the existing
Play / Controls / Economy / Layout sections updated for v0.3.0.

### 17. No CI — **Applied**
Added `.github/workflows/ci.yml` (same shape as the sibling
`godot-dungeon-looter` repo): `chickensoft-games/setup-godot@v2`
with Godot 4.7.2, headless `--import`, then every test file
headless. Note the org is `chickensoft-games`, not
`chickensoft-godot` — the wrong org failed the first CI run on the
sibling repo. CI is unrun until the first push.

### 18. No visual assets / no architecture diagram — **Applied (docs only)**
Added `docs/architecture.mmd` (Mermaid: main → hud / fog / minimap /
sound / data / campaign, and the MP host/client split) and
`docs/visual-assets.md`: an exact shot list of what to capture from a
real Windows play session (menu, early economy, fog-of-war split,
minimap, campaign briefing, 2-player LAN, victory screen, and a 10–15 s
GIF of a wave hitting the base), with the exact README placement for
each. Nothing is mocked: the README links no images until real
captures exist.

### 19. Test gaps — **Applied**
128 checks before this pass, with no coverage of the three P0 bugs
(the dangling-target bug was untestable in the old harness shape).
Added `tests/test_combat_cleanup.gd` (16 checks: kill across a real
frame boundary — attacker, gatherer, and builder references all
clear, and the victims are proven actually freed) and
`tests/test_review_fixes.gd` (17 checks: unknown-kind spawns,
train/place validation, MP faction filtering, corrupt snapshot, Orc
selection and training, Orc victory text). Total is now 161 checks.

## Deliberately not done

- **No spatial hash for `_separate()`** (finding 9) — needs its own
  perf test; the current unit counts do not justify it.
- **No snapshot delta compression / interpolation** — snapshots are
  full state at ~7 Hz and fine at this scale; the next step would be
  delta snapshots + client-side interpolation, a protocol change.
- **No lobby / player names / chat** — out of scope for a review pass.
- **No export-template download / export run** — the Windows/Web
  presets are still untested (1.28 GB templates, not installed here).
- **`SoundManager.play()` cap** frees the oldest player, which can be
  the currently-playing victory tone, and it counts children on every
  call. Cosmetic at this scale; noted, not changed.
- **ConfigFile save errors ignored** (`save_unlocked`,
  `_on_next_mission_pressed`) — a read-only user dir would silently
  lose campaign progress. Minor; noted, not changed.

## Verification (this pass)

From a fresh extraction of the rebuilt push zip:
`godot --headless --path . --import` — 0 errors; tests PASS 161/161
(28 data + 19 smoke + 7 sim + 19 fog/sound + 36 MP sync + 19 campaign
+ 16 combat cleanup + 17 review fixes); a 300-frame live headless
run in host mode is clean; zero matches for the old trademarked
terms in tree and history; the clean single-commit history is
preserved plus the review commit on `main`, no remote.
