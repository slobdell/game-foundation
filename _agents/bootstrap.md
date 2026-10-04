# Bootstrap: what gets installed and why

`make bootstrap` is the only setup step on a fresh clone.

1. Downloads `SHA512-SUMS.txt` for the pinned Godot release and verifies every download against it.
2. Unzips the **Godot editor** into `.tools/godot-<version>/` and creates `._sc_` beside it: **self-contained
   mode**, so editor settings and export templates live there, not in `~/.config` or `~/.local`. `make distclean`
   removes everything; two projects on different Godot versions can't interfere.
3. Downloads the export templates (~1.3 GB), keeps only **single-threaded web** and **Linux** (~300 MB total),
   deletes the rest.
4. Runs `make import` and `make doctor`.

(Games made with `make new-game` symlink `.tools` to the foundation's copy, so the download happens once per
computer.)

| Choice | Why |
|---|---|
| Pinned Godot version (Makefile `GODOT_VERSION`) | Scene files and export templates are version-specific; everyone on the same version |
| Standard build (GDScript), not .NET/C# | Web export doesn't support C#; GDScript is what Godot learners use |
| Compatibility renderer | The only renderer that exports to the web; also runs on weak laptops |
| Single-threaded web export | Works on any static host (no special COOP/COEP headers) |
| Project-local toolchain | Nothing global to install or remove |

Optional: Python 3 (tools; stdlib only, Pillow optional), `ffmpeg` (audio tools), Node + Google Chrome
(`make web-smoke`). `make doctor` reports each, and whether the Meshy / ElevenLabs keys are set.

**Upgrading Godot:** change `GODOT_VERSION`, `make bootstrap`, `make check-all`, open the editor once (it may
migrate scenes; commit the diff), then update the version in `project.godot` `config/features` and these docs.

**Other platforms:** the Makefile targets Linux x86_64. On Windows use WSL; on macOS change `GODOT_PLATFORM` and
the download names. Record what you did here.
