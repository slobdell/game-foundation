# Architecture: the kit, and how to add things

The kit (`game/kit/`) is the engine room. The director's game is mostly **content** (data files, levels,
models, sounds) on top of it, plus new kit pieces when the game needs a new kind of thing. Extend the kit;
don't fork it per level.

## The autoloads (always there, reachable by name from any script)

| Name | File | Owns |
|---|---|---|
| `Game` | `kit/game_state.gd` | inventory (`give/take/count`), flags (`set_flag/get_flag`), `placed` builds, save/load (`user://save.json`), and **`report(kind, data)`**: the one way the world announces things |
| `Missions` | `kit/missions/missions.gd` | missions from `data/missions.json`; listens to `Game.event`; steps: collect, talk, reach, build, defeat, flag |
| `Levels` | `kit/levels.gd` | `go(id, spawn)`: swaps the level under `World`, moves the player to a spawn marker, starts the level's music |
| `Dialogue` | `kit/ui/dialogue.gd` | the conversation box; `open(id)` reads `data/dialogue/<id>.json`, picks a variant, runs `then` actions |
| `Sound` | `kit/audio/sound.gd` | `play(id, at)`, `music(id)`, `voice(line_id)`; missing files are silent (see `audio.md`) |

Events sent with `Game.report` (add new kinds freely and teach `Missions` about them):
`collected {item, amount}`, `talked {npc}`, `reached {place}` (levels and `Place` areas), `built {piece}`,
`defeated {enemy}`, `player_down`.

## Scenes and nodes

| Piece | File | What it is |
|---|---|---|
| Main | `game/main.gd` | builds World + Player + FollowCamera + PlayerInput/Autopilot + BuildMode + Hud; reads launch flags |
| Player | `kit/player/player.tscn/.gd` | CharacterBody3D; obeys `command: MoveCommand`; walk/sprint/jump/interact/attack; Health child; respawns on death |
| PlayerInput / Autopilot | `kit/player/` | the two "deciders"; write your own for cutscenes or a pet that follows |
| FollowCamera | `kit/camera/follow_camera.gd` | third-person orbit, mouse/right stick, SpringArm so walls don't block |
| ModelSlot | `kit/look/model_slot.gd` | shows `assets/models/<slot>.tscn/.glb`, else a coloured placeholder from `data/slots.json` |
| Prop | `kit/world/prop.gd` | solid scenery; collision box = slot size |
| Collectible | `kit/world/collectible.gd` | walk into it: item + sound; stays collected (saved) |
| Interactable / Npc | `kit/world/` | "[E] Talk to …"; Npc opens dialogue and reports `talked` |
| Portal | `kit/world/portal.gd` | walk in → `Levels.go(to_level, to_spawn)` |
| Place | `kit/world/place.gd` | invisible zone → `reached {place}` (mission targets, triggers) |
| Level | `kit/world/level.gd` | root of each level scene; needs ground, light, a `Marker3D` in group `spawn` |
| Health / Shot / Enemy | `kit/combat/` | hit points with teams; projectiles; a chaser enemy that drops items and reports `defeated` |
| BuildMode | `kit/build/build_mode.gd` | B to build, Q next piece, R rotate, E place; pieces/costs in `data/pieces.json`; saved per level |
| Hud | `kit/ui/hud.gd` | hearts, inventory, mission tracker, "[E]" prompt, big messages (`hud.say("…")`) |

Physics layers: 1 world, 2 player, 3 creatures, 4 pickups/interactables. Inputs (in `project.godot`): move_*,
jump, sprint, interact (E), attack (F / click), build_mode (B), build_next (Q), build_rotate (R), pause (Esc),
camera_* (right stick); all have gamepad bindings.

Launch flags (main.gd): `--level=id --spawn=name --new --no-save --autopilot --screenshot=/abs.png
--screenshot-delay=s --quit-after=s`. Harness runs always pass `--no-save` so the director's save is never touched.

## Recipes: how to add…

**An item and things to collect.** Add it to `data/items.json` (`name`, `plural`, `slot`), add a slot to
`data/slots.json` if it needs its own look, then place `Collectible` nodes (script `kit/world/collectible.gd`,
`item = "fire_crystal"`) in a level. `make test FILTER=data` checks the references.

**A level.** `make new-level ID=lava_fields TITLE="Lava Fields" MUSIC=explore` copies `_template` and registers
it. Set ground/sky colours in its scene (the `Environment` and `Ground/Mesh` material), add props, a Portal from
an existing level (`to_level = "lava_fields"`) and one back. `make shot LEVEL=lava_fields`, then look.

**An NPC who talks.** Add an `Area3D` with script `kit/world/npc.gd` (`npc_id`, `display_name`, `dialogue`,
`slot`), and write `data/dialogue/<id>.json` **with the director** (their words!). Variants change what the NPC
says as missions progress; `then` can start a mission, set a flag or give items. Voices: `make-sound` skill.

**A mission.** Add it to `data/missions.json`. Start it with `auto_start`, a dialogue's `then.start_mission`, or
another mission's `reward.start_mission`. Every step needs `text` for the HUD. Add a test in
`tests/test_missions.gd` that plays it through with `Game.report(...)`.

**A new kind of mission step** (e.g. "deliver"): report a new event kind where it happens
(`Game.report("delivered", {...})`), handle it in `Missions._on_event` (or `_recheck` for state-based steps),
add it to the allowed kinds in `tests/test_data.gd`, and test it.

**An enemy.** Place a `CharacterBody3D` with `kit/combat/enemy.gd` (`enemy_id`, `slot`, `max_hp`, `speed`,
`sight_range`, `drop_item`). For special behaviour (shoots, flies, has a boss phase), make a new script that
`extends Enemy` and overrides `_target()` / `_physics_process`, or calls `fire_shot()`. Bosses: big slot, more
hp, a `Place` that starts the fight, a mission step `defeat`.

**Something you build.** Add a slot and a piece in `data/pieces.json` (`cost` in items). Crafting is the same
idea: a `data/recipes.json`, a small UI, and `Game.take/give`.

**A model for anything.** The `make-model` skill: slot → concepts → the director picks → 3D → fitted into
`assets/models/<slot>.glb`. Every ModelSlot using that slot updates.

**A sound, music, a voice.** The `make-sound` skill; then `Sound.play("id", where)` at the moment it happens.

**A new mechanic** (swimming, double jump, a grappling hook, a jetpack). Add the fields to `MoveCommand` if it
needs input, read them in `Player._physics_process`, add an input action in `project.godot` (with a gamepad
binding), and write a test that drives it through a `MoveCommand`. Expose tuning numbers as `@export` so the
director can play with them in the Inspector.

**A menu or title screen.** A `Control` scene under `game/ui/`; main.gd shows it before `Levels.go` (add a
`--skip-title` flag so harness runs skip it). Pause with `get_tree().paused` and `process_mode` on the menu.

## Beyond the kit

All possible, all bigger builds; do them in playable slices and record the design in `game_design.md`:
- **Vehicles / riding / flying**: a new controlled body that takes `MoveCommand` (the Player is the pattern);
  swap which body PlayerInput drives.
- **Pathfinding enemies** around walls: `NavigationRegion3D` baked per level + `NavigationAgent3D` in a new
  Enemy subclass.
- **Day/night, weather**: animate the level's `Sun` and `Environment` from a small script.
- **A 2D game** (platformer, top-down): Godot is excellent at 2D, but this kit is 3D. Talk to the parent first;
  a 2D variant of the kit is a foundation-level job (`FOUNDATION.md`).
- **Multiplayer**: deliberately not in the foundation. Ask the parent.

## Performance guardrails

The game must run on an ordinary laptop and in a browser. Keep each model within its slot's `tris` budget (the
asset pipeline enforces it), prefer a few big props over hundreds of tiny ones, keep shadows on the Sun only, and
if things get slow, measure first (`make run` with the editor's Debugger → Monitors) on the director's computer.
