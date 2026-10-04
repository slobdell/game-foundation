---
name: setup-my-game
description: First-time setup when a kid has just cloned Game Foundation - make it their own game, sign this folder in to their GitHub account, create their own private GitHub repo and back up to it. Use when the repo has no `foundation` remote and is not the maintainer checkout, or when a kid's game has no `origin` remote yet, or when GitHub sign-in stopped working.
---

# Setting up the kid's own game

The kid just cloned the starter project. By the end of this, it's **their** game, saved in **their own private
GitHub repo**, and they know (in kid words) why that matters. They already have a GitHub account. They don't know
git; you run every command. Talk like you're talking to an 11-year-old (`CLAUDE.md`). Keep the whole thing to
about 10 minutes, then go straight to Day one: setup is not the fun part.

## 0. Hello and the plan (two or three sentences)

"Hi! I'm going to help you make your game. First, two quick things: we'll give your game a name, and we'll make
a safe copy of it on your GitHub so your work is never lost. Then we start building."

## 1. Tools

Run `make doctor`. If Godot is missing, run `make bootstrap` in the background (it downloads ~1.5 GB, takes a
while) and carry on with the steps below while it runs. Tell them in one line it's downloading the game engine.

## 2. Make it their game

Ask: "What's your first name (or nickname)?" and "What do you want to call your game? (You can change it later.)"
Then:

```bash
make start-my-game NAME="<their title>" DIRECTOR=<first name>
```

It renames the clone's link to the starter project (`foundation`), so `origin` is free for their own repo, and
it protects their files from future kit updates. Say: "Done. This is now *your* game."

## 3. Sign this folder in to their GitHub

```bash
make github-login
```

It prints `GITHUB CODE: ABCD-1234` and waits in the background. Tell the kid, simply:
1. "Open **github.com/login/device** in your browser. Make sure you're signed in to *your* GitHub account."
2. "Type this code: **ABCD-1234**" (the real code, big and clear).
3. "Click **Authorize** (or Continue). Tell me when it says you're done."

Then `make github-status` must say `signed in as <their login>`. If it doesn't: the code may have expired (run
`make github-login` again), or they authorized on the wrong account (have them sign out of GitHub in the browser
and repeat). If they don't know their GitHub password, stop and ask them to get a parent.

## 4. Their own private repo, and the first backup

Suggest a repo name from the game title: lowercase with dashes (`lava-lover`). Then:

```bash
make github-create REPO=<repo-name>
```

It creates `github.com/<their login>/<repo>` as **private**, connects it as `origin`, and pushes. Tell them:
"Your game now has a home on GitHub. Every time we finish something I'll make a save point and back it up there,
so it's safe even if this computer breaks." Give them the link and suggest they open it.

This is a perfect first **teaching moment** (`_agents/teaching.md`, idea #4): save points, backups, and their
first save point on GitHub. Record it in `_agents/teaching_notes.md`.

## 5. Write it down, then start Day one

- `HANDOFF.md`: replace "(template, before day one)" with today's date, note the repo URL under *Where the game
  stands*, and that setup is done.
- Commit ("Set up my game") and `make backup`.
- Go straight to **Day one** in `HANDOFF.md` (the `session` skill).

## If something goes wrong

- **No internet / GitHub down**: do steps 1–2, start Day one, and finish 3–4 next session. Note it in `HANDOFF.md`.
- **The repo name is taken** on their account: suggest another (`lava-lover-game`).
- **`make start-my-game` refuses (uncommitted changes)**: something changed since the clone. `git status`;
  if it's only build output, it's fine to `git stash`; otherwise ask before discarding anything.
- **This is the parent's maintenance checkout** (`foundation.maintainer` is set): don't run any of this.
