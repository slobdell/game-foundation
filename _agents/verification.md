# Verification: what "done" means

You can't watch the game, and "it compiles" is not "it works". Before you tell the director something is ready,
run what applies below **and look at the screenshots** (Read the PNG). Report failures as failures.

## The ladder

| # | Check | Command | Proves | When |
|---|---|---|---|---|
| 0 | Lint | `make lint` | Every script compiles, autoloads included. Reads `lint: all N scripts compile (and the broken probe was caught)` | always (check runs it) |
| 1 | Tests | `make test` (`FILTER=word`) | Kit logic and real physics: walking, jumping, picking up, missions, dialogue, combat, levels load, data files agree. Reads `N passed, M failed` | always |
| 2 | Tool tests | `make py-test` | The asset, audio and pages pipelines against mock servers (no credits) | always |
| 3 | Content contracts | `make assets-check`, `make audio-check` | Every model fits its slot; every sound/voice/music entry is valid and loud enough | always |
| 4 | Browser build | `make export-web` | The game exports for the web | always |
| — | **The check** | **`make check`** | 0–4 in order; stops at the first red. Ends `>> check: ALL GREEN` or `>> check: FAILED at <target>` | **before every commit** |
| 5 | Screenshots | `make shot LEVEL=id` / `make shots` → **Read `build/screenshots/*.png`** | It renders: framing, colours, the HUD, the new thing is visible and the right size. **Strict:** fails on any runtime error the game prints; `shots` adds 12 s of autopilot play | any visible change |
| 6 | Browser boot | `make web-smoke` → **Read `build/web-smoke.png`** | The web build boots in real Chrome with no console errors | before sharing; after export or startup changes |
| 7 | **The director plays it** | `make run` (or `make run LEVEL=id`) | It's fun, it looks right, it feels right. **The only check for anything subjective** | anything they'd notice |

`make check-all` = `check` + `shots` + `web-smoke`.

## Rules

- **A test you haven't seen fail proves nothing.** For anything important, break the code on purpose once and
  watch the test go red, then put it back. (Tank Squad's "no friendly fire" test passed for months because
  shells were missing *every* tank.)
- **Zero is not a pass.** A filter that matches no tests fails; lint fails if its deliberately broken probe file
  isn't caught; `py-test` fails if it finds no tests. Keep it that way when you add checks.
- **Look at every screenshot you produce.** If it's black, blank, or the thing isn't there, it's not done.
- **Every new mechanic gets a test** that drives it the way a player would (set a `MoveCommand`, wait physics
  frames, assert where things ended up). Every new kind of content gets a rule in `tests/test_data.gd`.
- **Never `make check` while another headless Godot runs in this folder** (the lock handles make targets; don't
  start Godot by hand alongside).
- Performance: if the game gets slow, measure on the **slowest computer the director plays on**, and say which
  computer every number came from.

## Writing a test

```gdscript
extends TestCase

func test_lava_hurts() -> void:
	KitFixture.floor_body(self)
	var player: Player = KitFixture.world(self)["player"]   # fresh state, never touches the real save
	var lava := preload("res://game/kit/world/hazard.tscn").instantiate()  # (your new thing)
	add_to_tree(lava)                                        # freed after the test
	await wait_physics_frames(30)
	assert_true(player.health.hp < player.health.max_hp, "standing in lava hurts")
```
`assert_true / assert_false / assert_eq / assert_near`, `expect_error("pattern")` before a call that should
complain, `add_to_tree()` for anything you add. A test that leaves physics bodies behind fails.
