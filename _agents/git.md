# Git and GitHub: you run it all

The director doesn't know git, and isn't expected to run any git command. **You do all of it**, routinely and
safely, and you explain it in kid words as you go so they learn the ideas (`teaching.md`, idea #4).

## The setup (how a kid's game is connected)

```
 github.com/<parent>/game-foundation  ──(remote "foundation")──▶  this game  ──(remote "origin")──▶  github.com/<kid>/<game>  (PRIVATE)
   the kit and docs, updated by the parent                          your folder                         their backup, theirs
```

- **`foundation`**: where the kit came from. `make foundation-update` merges kit improvements in; the director's
  files are protected (`.gitattributes` `merge=ours`).
- **`origin`**: the kid's own private GitHub repo, made on day one by `make github-create`.
- **The kid's GitHub sign-in lives in this game folder** (`.gh/`, git-ignored), set up by `make github-login`, and
  is used for this repo only. It never mixes with a parent's or sibling's account on the same computer. Commits are
  signed with their GitHub username and GitHub's private no-reply email (never a real email address).

## Kid words for git

| Git | Say |
|---|---|
| commit | a **save point**, like in a video game: we can always go back to it |
| commit message | the **label** on the save point, so we know what it was |
| push / backup | **backing up** to GitHub, so the game is safe even if this computer breaks |
| repository (repo) | the game's **folder on GitHub**, with every save point in it |
| pull / sync | **getting the latest** from GitHub (if they worked on another computer) |
| merge | **combining** two sets of changes |

## The routine

- **Start of session:** `make sync`. If it says both sides have new work, see *Problems* below.
- **After every green step** (`make check` ALL GREEN): commit. Small commits, plain messages that say what the
  game gained, in words the kid would recognise: "Lava now hurts the player", "Maya's monster has its own model".
  Let the kid write the message sometimes (they're the director); fix only spelling.
- **Back up** with `make backup` after every 2–3 commits and **always at the end of a session**. Say so in one
  line: "Backed up to your GitHub. ✓"
- **Now and then** (every week or two), `git fetch foundation` and, if there's something new, tell the kid in one
  line ("There's a kit update: better enemies. Want it?"), then `make foundation-update` (it runs the check). If
  the merge has conflicts or the check fails, stop, `git merge --abort` if a merge is half done, and write it up in
  `HANDOFF.md` for the parent.
- Show them their repo on GitHub once in a while (`https://github.com/<login>/<repo>`): their save points with
  dates and messages. It makes "backup" real.

## Before every commit

- `make check` is green (or you're committing a deliberate work-in-progress the kid asked to save: say so in the
  message).
- **No secrets**: never commit `.gh/`, `*.env`, API keys or tokens. They are git-ignored; keep it that way.
- **No huge files**: GitHub refuses files over 100 MB and slows down above 50 MB. Check with
  `git diff --cached --stat` and `find . -size +40M -not -path './.godot/*' -not -path './.tools/*' -not -path './build/*'`.
  Raw Meshy downloads in `assets/incoming/` are already git-ignored.
- **No personal information** in commits or the game (full names, school, address, photos of people).

## Never

- `git push --force`, `git reset --hard` on pushed work, `git rebase` of pushed commits, deleting branches or
  the GitHub repo, or rewriting history in any way. If something went wrong, fix it with a **new** commit
  (`git revert` if needed).
- Making the repo public, or pushing anywhere except `origin` (and the `gh-pages` branch via `make publish-web`
  when a parent said yes).
- Committing with someone else's identity (the start-my-game commit is the only one before sign-in).

## Problems and what to do

| Problem | Do |
|---|---|
| `make backup` / `sync` says not signed in, or "Authentication failed" | `make github-status`; then `make github-login` and walk the kid through the code again (`setup-my-game` skill) |
| `sync`: "this computer AND GitHub both have new work" | `git pull --no-rebase origin <branch>`; if it merges cleanly, `make check`, commit, backup. If there are conflicts, keep both sides' work where you can, explain it to the kid simply, and `make check` before committing |
| A commit broke something | Fix forward with a new commit, or `git revert <hash>`. Never rewrite pushed history |
| They want an old version back | `git log --oneline` to find it, then restore just the files they want: `git restore --source <hash> <path>`, test, commit |
| GitHub refuses a big file | Remove it from the commit (`git reset HEAD~1 --soft` only if NOT pushed yet), git-ignore it, commit again |
| No internet | Commit as usual; back up next time. Say so in `HANDOFF.md` |
