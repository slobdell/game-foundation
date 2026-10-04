# Sharing the game

Two builds: the **browser build** (friends click a link and play; nothing to install) and the **desktop build**
(a Linux program). The browser build is the main way to share. Both are made from `export_presets.cfg`.

| Target | What it does |
|---|---|
| `make export-web` | browser build -> `build/web/` (`index.html`, `index.wasm` = the engine, `index.pck` = the game) and its sizes. Part of `make check`. |
| `make serve-web` | play it at http://localhost:8060 (`WEB_HOST=0.0.0.0` also prints a link for a phone/tablet on the home Wi-Fi) |
| `make web-smoke` | headless Chrome loads it, plays a few seconds, saves `build/web-smoke.png`; fails on console errors, files that didn't load, or a blank screen. Look at the PNG. |
| `make publish-web` | puts the browser build on GitHub Pages (below) |
| `make web-zip` | `build/game-web.zip` for itch.io (below) |
| `make export-desktop` | `build/desktop/game.x86_64` (one file, game data inside) + `game-linux.zip` |

## Why the browser build is made this way

- **Single-threaded** (`variant/thread_support=false`; `make bootstrap` installs only the no-threads web templates).
  Threaded builds need `SharedArrayBuffer`, which needs special COOP/COEP headers that GitHub Pages and itch.io's
  defaults don't send. Single-threaded runs on any static host. `tools/serve_web.py` sends those headers anyway so
  local play would match a threaded build if one is ever needed.
- **Compatibility renderer** (`project.godot`): the only Godot 4 renderer that runs in a browser (WebGL 2), so the
  browser looks like the desktop.
- **What goes in the pack.** Godot packs scenes, scripts and imported art/sound automatically. Plain files the game
  reads itself are only packed if `include_filter` lists them: today `data/*.json, data/dialogue/*.json,
  assets/audio/*.json, assets/music/*.json, assets/models/*.json`. **If the game starts reading a new kind of file
  (a `.txt`, a `.csv`, JSON in a new folder), add it to `include_filter` in BOTH presets**, or it works in the
  editor and is missing in the exported game. `exclude_filter` keeps the workshop out: `_agents/ tests/ build/
  tools/ assets/pipeline/ assets/review/` and audio masters (`assets/audio/masters/`, `assets/music/masters/`).
- **Sizes** (game-foundation's first export, 2026-10-04, laptop): `index.wasm` 38 MB (the engine; the same for
  every game), `index.pck` 0.2 MB (the game), 9.9 MB zipped. Hosts usually send the wasm compressed, so a friend downloads closer to the zipped size.
  `make export-web` lists the big files and **warns at 80 MB for any one file**: GitHub Pages refuses files over
  100 MB, itch.io allows 200 MB per file (500 MB total), and Cloudflare Pages stops at 25 MiB per file (it cannot
  host even the engine file, so we don't use it). The pack grows with music, voices and big textures: compress audio
  to ogg, keep textures at 1024-2048 px.

## Put it online: GitHub Pages (free; `make publish-web`)

Once per game (the parent does this with the kid):
1. The repo is on GitHub (`git remote -v` shows `origin ... github.com/...`), and `git push` works from this
   computer (`gh auth login` is the easy way). GitHub Pages is free for **public** repos; a private repo needs a
   paid plan.
2. `make publish-web`. It exports, copies `build/web` into a fresh one-commit branch `gh-pages` (plus `.nojekyll`),
   and force-pushes it. Your code branches are never touched; the branch only ever holds the latest build.
3. If the `gh` tool is installed, the target also switches Pages on. Otherwise, on GitHub: **Settings > Pages >
   Build and deployment > Source: Deploy from a branch > Branch: `gh-pages`, folder `/ (root)` > Save**.
4. After a minute or two the game is at **`https://<owner>.github.io/<repo>/`** (the target prints it). Send that
   link to friends. Every later `make publish-web` updates it; reload the page to see the new version.

If the link shows a 404 at first, wait two minutes (the first deploy is slow) and check Settings > Pages for the
green "Your site is live" line.

## Or: itch.io (free, made for games; good for a kid's portfolio)

`make web-zip`, then on itch.io: **Create new project > Kind of project: HTML > upload `build/game-web.zip` >
tick "This file will be played in the browser"**, set a viewport of 1280 x 720 (tick "Fullscreen button"), and
save as Public, Restricted (password) or Draft. Under 13s can't hold their own itch.io account (its terms), so the
parent's account hosts it. Updating: upload a new zip and delete the old one.

## Sharing the desktop build

`make export-desktop` makes `build/desktop/game.x86_64` (the game's data is inside it) and `game-linux.zip`. A
friend on **Linux** unzips it, then `chmod +x game.x86_64` (zips can drop the "runnable" flag) and runs it.
Windows and macOS friends: use the browser link. (A Windows build needs the `windows_release_x86_64.exe` export
template added to `TEMPLATE_FILES` in the root `Makefile`, a "Windows Desktop" preset, and an unsigned-app warning
click-through for the friend; not set up yet.)

## Saves in the browser

The game saves to `user://`, which in a browser is the site's IndexedDB storage: per browser, per site address.
A save made on `localhost:8060` is not on the GitHub Pages site, and clearing site data deletes it.

## When it breaks

| Symptom | Cause |
|---|---|
| `export-web` fails: "No export template found" | `make bootstrap` (it installs the templates) |
| works in the editor, missing data in the browser | a file the game reads isn't in `include_filter` (above) |
| page stuck on the loading bar, `.pck` 404 | serve the folder over HTTP (`make serve-web`), not `file://` |
| "SharedArrayBuffer" error | a threaded export: the preset must keep `variant/thread_support=false` |
| `web-smoke`: "the screen is blank" | the game drew one flat colour: look at `build/web-smoke.png`, then the `[browser:...]` lines above it |
| GitHub Pages 404 | Pages not switched on for `gh-pages`, or the first deploy is still running |
