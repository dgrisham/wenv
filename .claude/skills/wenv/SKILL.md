---
name: wenv
description: Teaches Claude how to USE the wenv shell tool (~/src/wenv) when working in ANY project that has a wenv set up — starting/stopping a wenv's tmux session, navigating via wd/c/edit, and creating or removing parallel checkouts (git worktrees or jj workspaces) for branches via the git-worktree/jj-workspace extensions. Use this whenever the user mentions "wenv", "start my wenv", "wenv start/stop/source", add-worktree/remove-worktree, add-workspace/remove-workspace, "working environment", or asks to set up a parallel checkout/worktree/jj workspace for a branch in a project that might use wenv. Also consult this when poking around an unfamiliar project and you find a file shaped like `wenv_dir=... wenv_deps=(...) wenv_extensions=(...)` — that's a wenv definition, and this skill explains what it means. This is about USING wenv day to day in other projects; for developing wenv's own codebase, AGENTS.md in the wenv repo covers that instead and should not be duplicated here.
---

# wenv

`wenv` is a personal Zsh framework (source: `~/src/wenv`) that gives a project its own
isolated shell environment — variables, aliases, functions, a startup/shutdown lifecycle, and
a dedicated tmux session. It's used across most of this user's projects, so if you're working
in a repo and something feels off about available commands, aliases, or directory shortcuts,
check whether a wenv is active (`$WENV` set) or whether one exists for this project but isn't
started (see "Detecting a wenv" below).

The implementation and its extensions change over time — rather than trust exact flag syntax
baked into this skill, prefer reading the live source when precision matters:
`~/src/wenv/wenv` (core commands), `~/src/wenv/extensions/git-worktree`, and
`~/src/wenv/extensions/jj-workspace`. This skill is a map, not the territory.

## Detecting a wenv

- An **active** wenv exports `$WENV` (its name), `$WENV_DIR` (base directory), `$WENV_DEPS`,
  `$WENV_EXTENSIONS`. If `$WENV` is set in the current shell, you're inside one.
- An **available-but-inactive** wenv is a file at `$WENV_CFG/wenvs/<name>` (`$WENV_CFG`
  defaults to `${XDG_CONFIG_HOME:-$HOME/.config}/wenv`), shaped like:
  ```zsh
  wenv_dir="/path/to/project"
  wenv_deps=('other/wenv' ...)
  wenv_extensions=('wd' 'edit' 'git-worktree' ...)
  startup_wenv() {}
  shutdown_wenv() {}
  bootstrap_wenv() {}
  ((only_load_wenv_vars == 1)) && return 0
  # project-specific aliases/functions/exports below
  ```
  `wenv list` shows every wenv that exists; a project's own directory path usually corresponds
  1:1 with some `wenv_dir` value, so grepping `$WENV_CFG/wenvs` for the project path is a quick
  way to find the right name if the user hasn't said it.

**Important caveat for you as an agent**: `wenv`, `wd`, `c`, `add-worktree`, etc. are Zsh
functions and aliases, not binaries on `$PATH`. They only exist in a shell where the wenv's
file (and its extensions) have actually been sourced — typically an interactive shell inside
the wenv's tmux session. A fresh Bash-tool invocation in this session will **not** have them
unless you explicitly source the right files first (e.g.
`source ~/src/wenv/wenv && source ~/src/wenv/extensions/git-worktree` plus the env vars a wenv
file would normally set, like `$GIT_WORKTREES`/`$JJ_WORKSPACES`). Often the simpler move is to
just run the equivalent `git`/`jj` commands directly (this skill documents what each wenv
command/extension does under the hood so you can translate), or to ask the user to run the
command themselves in their wenv's tmux pane and report back — especially since tmux-session
and worktree/workspace creation are exactly the kind of state-changing actions worth confirming
before taking.

## Core commands

```
wenv start <name>        Start/attach the wenv's tmux session (sources the wenv + deps + extensions)
wenv stop                Stop the active wenv, running shutdown_wenv()
wenv cd [<name>]         cd into a wenv's base directory (active wenv's if no name given)
wenv source [<name>]     Re-source the active (or named) wenv + dependencies in the current shell
wenv edit <name>         Open a wenv's file in $EDITOR
wenv new                 Create a new wenv from the template
wenv list                List all wenvs
wenv remove <name>       Delete a wenv's file
wenv rename <old> <new>  Rename a wenv
wenv bootstrap <name>    Run a wenv's one-time bootstrap_wenv() setup
wenv extension {load,edit,rm} <ext>   Manage extensions directly
```
Every subcommand takes `-h` for its own usage. `wenv_deps` are other wenvs sourced first
(recursively, depth-first, before the requesting wenv's own body runs) — useful for shared
config a whole family of related projects depends on (see "SERVICE / shared root directory
convention" below, which depends on this).

## Directory/file shortcuts: `wd`, `c`, `edit`

If the `wd`/`c`/`edit` extensions are loaded, a wenv can declare associative arrays mapping
short keys to paths/files:
- `wd <key>` prints the resolved path for `key` in `wenv_dirs` (relative entries resolve
  against `$WENV_DIR`); `wd` alone prints `$WENV_DIR`. `c <key>` is `cd $(wd <key>)`.
- `edit <key> [<key> ...]` opens the resolved files for `key` in `wenv_files` via `$EDITOR`.

Both the `git-worktree` and `jj-workspace` extensions (below) register their worktrees/workspaces
into `wenv_dirs` automatically, so `c worktree/<branch>` or `c workspace/<name>` is the fast way
to jump into one once it exists.

## Parallel checkouts: `git-worktree` / `jj-workspace` extensions

These extensions let a wenv create and manage extra working directories for other
branches/bookmarks — one for git repos, one for Jujutsu (`jj`) repos — without the user having
to think about where they live.

### `git-worktree` (for git repos)

```
add-worktree [-b <base>] [-B] [-h] <branch> [<branch> ...]
remove-worktree [-f] [-D] [-h] [<branch-glob> ...]
```
- `add-worktree` matches each `<branch>` against existing local branches (glob-capable) and
  creates a `git worktree` for every match. `-B` creates the branch if nothing matched (`-b
  <base>` sets its start point, default: current branch). Without `-B` a missing branch is
  skipped with a message rather than erroring out the whole call.
- `remove-worktree` matches existing worktrees by branch name against the given glob(s) (all of
  them if none given), confirms (`[yN]`, skip with `-f`), removes the worktree, and (`-D`) also
  deletes the branch.
- Worktrees live under `$GIT_WORKTREES`, a directory root conventionally wired up as
  `export GIT_WORKTREES="$SCRATCH/<org>/$SERVICE"` in a shared "base" wenv, with each
  per-project leaf wenv setting `SERVICE='<project-name>'` **before its own guard** and
  depending on that base wenv — so each project transparently gets its own worktree root
  without the base wenv needing to know about any specific project. If a project's worktrees
  aren't showing up where expected, check that its wenv actually sets `SERVICE` and depends on
  the right base wenv.

### `jj-workspace` (for Jujutsu repos)

```
add-workspace [-r <base>] [-B] [-h] <name> [<name> ...]
remove-workspace [-f] [-D] [-h] [<bookmark-glob> ...]
```
Same shape, jj vocabulary: `<name>` is a bookmark (jj's rough branch equivalent — note that in
jj itself, workspaces and bookmarks are independent concepts; this extension imposes a
bookmark-per-workspace convention on top so it maps cleanly onto `wenv_dirs`, mirroring git's
model). `-r <base>` is the revision new bookmarks are created at (default `@`, the current
working-copy commit). Workspaces live under `$JJ_WORKSPACES` (parallel convention to
`$GIT_WORKTREES`). One real difference worth knowing: `jj workspace forget` (what
`remove-workspace` uses) never touches the filesystem, so `remove-workspace` does an explicit
`rm -rf` of the directory too — if you're ever doing this by hand with raw `jj` commands, don't
forget that step.

Because jj repos created without `--colocate` have no `.git` at all, `git`/`gh` commands won't
work inside a jj workspace directory — `jj git push --bookmark <name>` still works fine from
any workspace (it talks to the shared store, not the filesystem), but anything needing literal
`git`/`gh` (opening a PR, say) needs to run from the project's primary, git-colocated directory.

## If you're asked to add/remove a worktree or jj workspace

1. Check whether the project has a wenv and whether it's active (see "Detecting a wenv").
2. If it does and the relevant extension is loaded, prefer using the real command
   (`add-worktree`/`add-workspace`/etc.) in the wenv's own shell if you have access to one —
   it keeps `wenv_dirs` (and therefore `wd`/`c`) in sync automatically.
3. If you don't have a live wenv shell to work in, you can do the equivalent directly
   (`git worktree add`/`git branch`, or `jj workspace add`/`jj bookmark create`) — just know
   that `wenv_dirs` won't get updated until the extension's reconciliation function
   (`add-worktrees-to-wenv-dirs` / `add-workspaces-to-wenv-dirs`) runs again in a real wenv
   shell, so `c worktree/<branch>`/`c workspace/<name>` won't work yet from elsewhere.
4. Either way, creating a worktree/workspace or deleting a branch/bookmark is a real,
   state-changing action — treat it with the same care you'd give any git/jj write, and when in
   doubt, confirm with the user rather than assuming which branch/base they mean.
