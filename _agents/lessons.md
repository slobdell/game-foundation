# Lessons

Mistakes made once already, mostly on **Tank Squad** (a large Godot game built with Claude agents, from which
this foundation was taken). Each one cost hours. Don't pay again. Add your own at the bottom, numbered, with what
happened and the rule it taught.

## About checking

1. **A gate that cannot fail is not a gate.** Lint once reported "all scripts parse" after checking *zero*
   files. A test filter with a typo printed "0 passed, 0 failed" and exited 0. So: lint compiles a deliberately
   broken probe and fails if it isn't caught; a filter that matches nothing fails; a test file with no tests
   fails. When you add a check, make sure it can go red.
2. **Green tests aren't proof.** A "no friendly fire" test passed only because shells were missing everything.
   Break the code on purpose once and watch the test fail.
3. **Look at the picture.** Claude can read PNGs. A screenshot that's black, blank or framed wrong is a failure
   even when every test passes. Two "identical" screenshots (same byte size) usually mean one is broken.
4. **Read the summary line, never an exit code through a pipe.** `make x | tail` returns tail's exit code.
   The truth is `N passed, M failed` and `>> check: ALL GREEN`.
5. **Warnings are errors in tests.** A warning on a real code path is a bug until someone says otherwise, and the
   way to say otherwise is `expect_warning()` in the test that causes it, never a silent ignore.
6. **One cause, many victims.** A test that leaves a node behind makes the *next* test fail. Free what you add
   (`add_to_tree`), and when many tests fail with the same message, look at the first one.

7. **A runtime error in a console nobody reads is a bug nobody fixes.** On day one of this foundation, a sound
   bug spammed errors whenever a pickup was freed. Every test passed and the screenshot looked fine. So screenshot
   runs are **strict**: `make shot`/`make shots` fail on any engine or script error the game prints, and
   `make shots` includes 12 s of autopilot play, because some errors only happen when things get picked up.

## About Godot

8. **Two headless Godots in one folder corrupt `.godot/`**, and the errors ("Nonexistent function",
   "referenced non-existent resource") look exactly like broken code. Make targets take a lock; use them.
9. **A timeout that kills the parent doesn't stop the children.** If you kill a run, check nothing is still
   running (`pgrep -af Godot`) before starting another.
10. **A new `class_name` is invisible until `make import`.**
11. **Forward is −Z; positive `rotation.y` turns left.** The #1 "it drives backwards" bug.
12. **Physics happens on physics frames.** Set something, then `await` frames before you check it.
13. **The web build is pickier than desktop.** Compatibility renderer only; single-threaded export (works on
    any host); declare the audio bus layout in a file (buses made at runtime went silent in the browser);
    hosting limits are per file (GitHub Pages 100 MB, Cloudflare Pages 25 MiB); the browser's default font has
    no emoji or symbols like ♥ (they showed as boxes on day one: draw them, or add a font); `make web-smoke` and
    LOOK at `build/web-smoke.png` before sharing.
14. **Art must never change gameplay.** Collision comes from the slot size, not the model, so a new model can't
    make a level unwinnable or a door impassable.

## About working with the director

15. **Their words, verbatim, in the docs.** Conversations get summarised and forgotten; `game_design.md` doesn't.
    A future Claude can't ask them what they meant three weeks ago.
16. **Recommend, don't present menus.** Two or three options with your pick and why. A list of eight is homework.
17. **Show, then ask.** "Do you want the lava brighter?" is unanswerable in the abstract. A choices page with
    three lava colours is answered in five seconds.
18. **The person who plays it is the final check** for anything about look, sound or feel. Tests prove it
    works; only they can say it's right.
19. **Measure, don't guess.** "Is this level too hard?" → let the autopilot or a test play it ten times, or
    count how often the director dies. A mirrored map once looked fair and was won 64 % of the time from one
    side; only a measurement showed it.

## Added in this game

(Number from 20. What happened, then the rule.)
