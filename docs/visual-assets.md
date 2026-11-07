# Visual assets — shot list

No screenshots, diagrams, or GIFs are in the repo yet. Everything
below must be captured from a **real play session** (Windows,
Godot 4.7.2, the game running) — never mocked up, never drawn from
a description, never generated. The repo is headless-tested only;
the scene has never been seen rendered, so the first real captures
are also the first visual verification that the game looks right.

Capture at 1280x720 (the project's viewport). Save captures under
`docs/images/` and link them from the README at the spots listed.

## Shots

### 1. `docs/images/menu.png` — the start menu
- **Depict:** the game open on the start menu: the "Fantasy RTS"
  title, the Single Battle / Campaign / Host / Join buttons, the
  mission list expanded with the Mission 1 briefing visible.
- **README placement:** Description section, right after the first
  paragraph — it is the first thing a visitor sees, and it shows
  the game has a menu, a campaign, and multiplayer before they
  read a word of the feature list.

### 2. `docs/images/early-economy.png` — early game
- **Depict:** 30–60 seconds into a Single Battle: the Human base
  (Town Hall, Farm, 3 Peasants), one Peasant walking to the gold
  mine, one chopping a tree, the top bar showing Gold/Wood/Supply,
  and the bottom panel with the Farm/Barracks buttons visible.
- **README placement:** Play section, beside the controls table —
  it shows the economy loop the controls describe.

### 3. `docs/images/fog-of-war.png` — fog of war
- **Depict:** the same game from the Human camera with the Orc
  base area black (unexplored) on one side and dimmed (explored
  but not currently visible) on the other, with an Orc unit visible
  only where a Footman can see it.
- **README placement:** Economy & units section, in the fog-of-war
  bullet — the mechanic is hard to picture from text alone.

### 4. `docs/images/minimap.png` — minimap + camera
- **Depict:** a zoomed-out view with the minimap (bottom-right)
  showing blue/green dots for both armies, gold dots for mines,
  and the white camera-viewport rectangle.
- **README placement:** Play section, next to the "Click the
  minimap" control row.

### 5. `docs/images/campaign-briefing.png` — campaign
- **Depict:** the Campaign menu with Mission 3 selected, its
  briefing text visible, and the "Start mission" button.
- **README placement:** Play section, in the Campaign bullet.

### 6. `docs/images/lan-two-players.png` — 2-player LAN
- **Depict:** two windows side by side on the same LAN game — the
  host as Humans, the joiner as Orcs — showing the same world from
  both sides (or a photo of two machines if that is how it is
  played).
- **README placement:** Play section, in the Host / Join bullet.
  This is the feature most likely to be doubted, so show it.

### 7. `docs/images/victory.png` — end screen
- **Depict:** the "Victory! The enemy base has fallen." end panel
  with the "Play again" button, over a battlefield with the Orc
  base destroyed.
- **README placement:** end of the Play section, after the win
  condition paragraph.

### 8. `docs/images/wave-attack.gif` — animated GIF
- **Depict:** 10–15 seconds of an Orc attack wave hitting the
  Human base: Grunts and Spear Throwers advancing, Footmen
  engaging, health bars dropping, the "The Orcs are attacking!"
  message on screen. Record the real game, do not animate a
  mockup.
- **README placement:** Description section, under the menu
  screenshot — a moving game sells the project more than any
  paragraph. Keep it under ~5 MB so the README stays fast.

## Checklist before linking any of these in the README

- [ ] Captured from the real game running on Windows, not staged
      in an image editor.
- [ ] 1280x720, PNG for stills, GIF for the wave attack.
- [ ] Filenames match the list above exactly.
- [ ] Each image is placed at the README spot listed for it, not
      dumped at the bottom of the file.
- [ ] The architecture diagram (`docs/architecture.mmd`) is linked
      from the Layout section once it renders correctly on GitHub.
