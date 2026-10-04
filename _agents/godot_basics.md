# Godot basics (for Claude, and for explaining to the director)

Godot concepts mapped to things you already know, with examples from this repo. For the director, translate:
the "Think of it as" column is written so it can be said out loud.

| Godot | Think of it as | Here |
|---|---|---|
| **Node** | One thing in the game, in a tree; it has callbacks like `_ready` and `_process` | `Player`, `Npc`, `Hud` |
| **Scene** (`.tscn`) | A saved bunch of nodes, like a Lego set you can snap into other sets | `player.tscn`, each level |
| **Script** (`.gd`) | Behaviour for ONE node. `extends CharacterBody3D` = "is a CharacterBody3D, plus my code" | `player.gd` |
| `class_name Foo` | A global type name: `Foo.new()`, `var x: Foo` | `Collectible`, `Enemy` |
| **Autoload** | A node that is always there, reachable by name from anywhere | `Game`, `Missions`, `Levels`, `Dialogue`, `Sound` |
| **Signal** | "Tell me when this happens": `signal died`, `died.emit()`, `x.died.connect(fn)` | `Health.died`, `Missions.completed` |
| `@export var` | A setting that appears in the editor's Inspector, saved in the scene | `jump_velocity`, `enemy_id` |
| `@onready var x = $Child` | Grab a child node right before `_ready` | `health` in `player.gd` |
| `_physics_process(delta)` | Runs 60 times a second, steady: movement and rules go here | `Player`, `Enemy` |
| `_process(delta)` | Runs every drawn frame (uneven): visuals go here | `FollowCamera`, `Hud` |
| **Resource** | Data you can save and share (meshes, materials, sounds) | the materials inside level scenes |
| Groups | Tags: `add_to_group("collectible")`, `get_nodes_in_group(...)` | `spawn`, `collectible`, `shots` |
| Collision layer / mask | A body IS ON layers and LOOKS AT masks | 1 world, 2 player, 3 creatures, 4 pickups |
| `res://` / `user://` | The project folder (read-only in a game) / the player's save folder | `res://data/…`, `user://save.json` |
| Feature tags | `OS.has_feature("web")` | tell browser from desktop |

## Physics bodies

| Body | Moves by | Use for |
|---|---|---|
| `StaticBody3D` | never | ground, walls, props (`Prop`) |
| `CharacterBody3D` | your code sets `velocity`, then `move_and_slide()` | the player, enemies, anything game-y |
| `RigidBody3D` | the physics engine (forces) | things that tumble: crates, balls, debris |
| `Area3D` | doesn't move things, detects overlaps | pickups, portals, triggers, shots |

## Coordinates (memorise)

- **Y is up. Forward is −Z.** `-global_transform.basis.z` is "the way this node faces".
- **Positive `rotation.y` turns LEFT** (counter-clockwise seen from above).
- Units are metres. The player is 1.8 m tall.

## GDScript tips

- Indentation like Python; **tabs**. Use static types: `var speed := 5.0`, `func f(x: int) -> void:`.
  When Godot can't infer a type (values from a Dictionary, `get_node`), write it: `var pressed: bool = ...`.
- `await get_tree().physics_frame` waits one physics tick; tests use `await wait_physics_frames(n)`.
- Free nodes with `queue_free()` (end of frame) or `free()` (now). Plain objects (`RefCounted`) free themselves.
- Helpers: `lerp`, `lerp_angle`, `move_toward`, `clampf`, `randf_range`, `Vector3.distance_to`.

## Scene files are text

`.tscn` files are readable (`[ext_resource]`, `[sub_resource]`, then `[node name=... parent=...]`). Claude can
write small scenes directly (every scene here was written that way). For placing lots of things by eye, the
editor is faster: `make editor`, edit, save, commit what it wrote. The editor may add `uid=` values when it
saves; that's normal. In `Transform3D(...)` the first nine numbers are the basis **rows**, then the position.

## The editor tour (good with the director)

1. `make editor` → FileSystem dock (bottom left) → double-click `game/levels/meadow/meadow.tscn`.
2. Scene dock (top left) shows the tree; click `Guide`, and the Inspector (right) shows its settings.
3. Drag things around in the 3D view; press **F6** to play the current scene, **F5** for the whole game.
4. Click `Player` in `game/kit/player/player.tscn` and change `Jump Velocity`. Play. Feel the difference.
