# Bootstrap: what gets installed and why

`make bootstrap` is the only setup step on a fresh clone. It works on **macOS** (Apple Silicon and Intel) and
**Linux** (x86_64), and needs **no admin password**: everything goes into the project's own `.tools/` folder.
`make doctor` says what kind of computer it found and what's installed.

| Step | Target | What | Size |
|---|---|---|---|
| 1 | `make python` | uv (pinned, sha256-checked) installs **Python 3.12** and a venv in `.tools/python3.12-venv`. All Python tools run on it (`$(PYTHON)`); a Mac's own Python is 3.9 | ~60 MB |
| 2 | `make ffmpeg` | ffmpeg + ffprobe: the system's if present; otherwise a pinned static build (ffmpeg.martin-riedl.de, sha256-checked) into `.tools/bin`, which make puts first on `PATH` | ~130 MB unpacked |
| 3 | `$(GODOT)` | The **Godot editor**, checked against Godot's `SHA512-SUMS.txt`. Linux: one binary. Mac: `Godot.app` (unpacked with `ditto` so the app's signature stays intact) | ~140 MB |
| 4 | `$(TEMPLATES_OK)` | Only the **export templates** we use, pulled out of the 1.3 GB `.tpz` with HTTP range requests (`tools/setup/zip_members.py`), each checked against a sha256 pinned in the Makefile: single-threaded web (both), macOS (both, so Linux can build the Mac game too), Linux (Linux only) | Mac ~145 MB, Linux ~290 MB |
| 5 | `make gh` | GitHub's `gh` tool (pinned, sha256-checked) | ~50 MB |
| 6 | `make import`, `make doctor` | builds Godot's `.godot/` cache, prints the report | |

`._sc_` beside the editor turns on Godot's **self-contained mode**: editor settings and export templates live in
`.tools/godot-<version>/editor_data/` instead of `~/.config` or `~/Library`. On a Mac Godot looks for `._sc_` next
to `Godot.app` (the app bundle is read-only), which is where `make bootstrap` puts it. `make distclean` removes the
whole toolchain. Every step is a file target, so re-running skips finished work.

Games made with `make new-game` on the same computer symlink `.tools` to the foundation's copy.

| Choice | Why |
|---|---|
| Pinned versions, every download checksum-checked | Scene files and templates are version-specific; everyone on the same version; a bad download fails loudly |
| Standard build (GDScript), not .NET/C# | Web export doesn't support C#; GDScript is what Godot learners use |
| Compatibility renderer | The only renderer that exports to the web; runs on weak laptops and on Macs |
| Single-threaded web export | Works on any static host (no special COOP/COEP headers) |
| Project-local toolchain | Nothing global to install, no admin password, no Homebrew |

## macOS notes

- **The one thing a Mac needs first: Apple's Command Line Tools** (git, make, curl, unzip, python3). Typing `git`
  in Terminal offers to install them (`xcode-select --install`); this is the only step that may ask for the Mac's
  password. Everything else is project-local.
- macOS ships **GNU make 3.81** and **bash 3.2**. The Makefile runs recipes through `tools/setup/shell.sh` (bash with
  `-eu -o pipefail`; make 3.81 ignores `.SHELLFLAGS`), and recipes and scripts avoid bash-4 features (no `mapfile`,
  associative arrays, `${x,,}`) and GNU-only tools: `flock` → `tools/setup/lock.py`, `timeout` →
  `tools/setup/timeout.py`, `sha*sum` → `shasum -a`, `readlink -f` → Python's realpath, `find -printf` → `wc -c`.
  Keep it that way when you add targets. (Verified on Linux with a hand-built GNU make 3.81: `make check` green.)
- **Gatekeeper**: files downloaded with `curl` are not quarantined, so Godot, gh, uv and ffmpeg run without the
  "downloaded from the internet" prompt. A game exported for Mac (`make export-desktop`) is ad-hoc signed, not
  notarized: on another Mac, right-click → Open the first time.
- Screenshots and `make run` use the Mac's screen; there is no `DISPLAY` variable on a Mac.
- Optional: Node.js and Google Chrome for `make web-smoke` (Chrome's default path on a Mac is
  `/Applications/Google Chrome.app/Contents/MacOS/Google Chrome`).

## Upgrading

- **Godot:** change `GODOT_VERSION`; re-pin `TEMPLATE_SHAS` with
  `python3 tools/setup/zip_members.py <tpz url> /tmp/t --print-sha --member templates/<file> ...`, after checking
  the members against a copy extracted from the SHA512-verified `.tpz` once; `make bootstrap`; `make check-all`;
  open the editor once (it may migrate scenes; commit the diff); update `config/features` in `project.godot`.
- **gh / uv / ffmpeg:** change the version (and for ffmpeg the pinned folder + sha256s) in the Makefile.

## Platform scope

macOS and Linux x86_64. Windows: use WSL (Linux rules apply). Linux on ARM: Godot and gh would need their arm64
downloads added to the Makefile.
