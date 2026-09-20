# AGENTS.md

This file provides guidance to AI coding agents working in this repository.

## What this is

`wenv` ("working environment") is a Zsh framework that connects tmux and Zsh to give each
project its own isolated shell environment: variables, aliases, functions, a startup/shutdown
lifecycle, and a dedicated tmux session. There is no build step, package manifest, test suite,
or CI — this is a sourced shell script plus a Zsh completion file plus a directory of optional
"extensions." Changes are verified by sourcing the script and exercising commands interactively
in a shell (see "Developing/testing changes" below).

Only the Zsh implementation is active. There was a Nushell rewrite (`impl/nushell` branch,
`backup/impl-nushell-pre-email-fix` branch) that has been **scrapped** — do not port features
from it or treat it as a reference for current behavior.

## Repo layout

- `wenv` — the entire implementation. A single Zsh file defining `__wenv` (aliased to `wenv`)
  and its subcommand functions (`wenv_start`, `wenv_stop`, `wenv_source`, `wenv_cd`, `wenv_new`,
  `wenv_edit`, `wenv_list`, `wenv_remove`, `wenv_rename`, `wenv_bootstrap`, `wenv_extension*`).
  Sourced from the user's `zshrc`.
- `_wenv` — Zsh completion function for `wenv` (`#compdef wenv`), discovers wenvs/extensions by
  listing `$WENV_CFG/wenvs` and `$WENV_CFG/extensions` on the fly.
- `completion.bash` — equivalent completion for Bash, kept in sync with `_wenv` by hand.
- `template` — the skeleton copied by `wenv new` into a fresh wenv file
  (`$WENV_CFG/wenvs/<name>`).
- `extensions/` — optional, reusable shell snippets a wenv can opt into via its
  `wenv_extensions` array (sourced once per shell in that wenv). Each is independent; read one
  before editing since none share code except by convention (e.g. `wd`/`c`/`edit` all key off
  associative arrays like `wenv_dirs`/`wenv_files` that a wenv file declares).
- `examples/` — annotated example wenv files (not code this project ships/executes, just
  reference material referenced from the README walkthrough).
- `README.rst` — the actual user-facing documentation: install steps, full command reference,
  and a walkthrough of the config surface (`wenv_dir`, `wenv_deps`, `wenv_extensions`,
  `startup_wenv()`/`shutdown_wenv()`/`bootstrap_wenv()`). Read it before making behavioral
  changes — it's the spec.

## Core architecture

**A "wenv" is just a Zsh file** living at `$WENV_CFG/wenvs/<name>` (`WENV_CFG` defaults to
`$XDG_CONFIG_HOME/wenv` or `~/.config/wenv`). It declares a few lowercase config variables and
lifecycle functions, then (below an early-return guard) any aliases/functions/exports for that
project:

```zsh
wenv_dir=""            # base directory the wenv cd's into
wenv_deps=()           # names of other wenvs to source first
wenv_extensions=()     # names of extensions/ to source

startup_wenv() {}      # runs on `wenv start`, cwd = $wenv_dir
shutdown_wenv() {}     # runs on `wenv stop`
bootstrap_wenv() {}    # runs on `wenv bootstrap <name>`, one-time setup

((only_load_wenv_vars == 1)) && return 0   # see below
# project-specific aliases/functions/exports go below this line
```

The `only_load_wenv_vars` guard is the key mechanism: several commands (`wenv cd`, `wenv rename`,
tab completion, dependency resolution) only need `wenv_dir`/`wenv_deps`/etc., not the full
project setup, so they `source` the wenv file with `only_load_wenv_vars=1` to short-circuit
before the expensive/side-effecting part of the file runs.

**Starting a wenv** (`wenv_start` in `wenv:101`): creates a detached tmux session named after the
wenv, writes a one-shot script to `/tmp/wenv/start-<name>` that exports `WENV`, calls
`wenv_source -c` (source the wenv + deps + extensions, staying in `wenv_dir`), mirrors `WENV`
into the tmux session's environment, then runs `startup_wenv()`. That script is `send`-keyed
into the new tmux pane so it runs in the session's actual shell rather than in the shell that
invoked `wenv start`. Attaches/switches to the session afterward.

**Sourcing** (`wenv_source` in `wenv:191`): loads the wenv file, exports `WENV_DIR`/`WENV_DEPS`/
`WENV_EXTENSIONS` from the lowercase vars, recursively sources every dependency in `wenv_deps`
(`source_wenv_dependencies_recursively`, `wenv:246` — dependencies are sourced bottom-up, and
because it's a plain recursive `source` of the *entire* dependency file, any inline shell code in
a dependency's wenv file runs too, not just declared vars/functions), loads all
`wenv_extensions`, then re-sources the wenv file itself for its project-specific body.

**Dependencies vs. extensions** are the two composition mechanisms and are easy to conflate:
`wenv_deps` pulls in another *wenv's* full file (for sharing env vars/logic between related
projects); `wenv_extensions` pulls in a shared, wenv-agnostic *extension* file from
`extensions/` (for sharing generic shell tooling across unrelated wenvs).

**Naming convention**: lowercase (`wenv_dir`, `wenv_deps`, `wenv_extensions`) are user-declared
config inputs, local to the wenv file. Uppercase (`WENV`, `WENV_DIR`, `WENV_DEPS`,
`WENV_EXTENSIONS`, `WENV_CFG`) are the framework's resolved, exported runtime state for the
active wenv. This distinction is intentional and holds throughout the codebase.

**Extensions** are wenv-agnostic shell files sourced into every shell of a wenv that lists them
in `wenv_extensions` — see the dedicated section below.

**tmux integration**: `WENV` is mirrored into tmux's session environment
(`tmux set-environment`) so that new panes/windows in that session can re-source the wenv (via
`[[ -n "$WENV" ]] && wenv_source -c "$WENV"` in the user's `zshrc`, per the README's installation
step 5). `wenv stop` clears `WENV`/`WENV_*`, unsets the three lifecycle functions, and renames the
tmux session back to its numeric ID.

## Extensions

Extensions (`extensions/`) don't import each other's code — they compose purely by convention,
mostly by reading/writing shared associative arrays (`wenv_dirs`, `wenv_files`) that a wenv file
or another extension declares with `declare -Ag`. Load order in `wenv_extensions` can matter
(see `notes` below).

- **`wd` / `c`** — the base directory-lookup mechanism, and what most other extensions exist to
  feed. `wd <key>` resolves `key` against the `wenv_dirs` associative array (relative values
  resolve against `$WENV_DIR`, absolute ones pass through); `wd` with no argument prints
  `$WENV_DIR`. `c` is `cd $(wd ...)`. `extensions/c` is a symlink to `extensions/wd` — loading
  extension `c` sources the same file, just under a name that makes `c <key>` read naturally.

- **`edit`** — the file-lookup analogue of `wd`. Reads a `wenv_files` associative array mapping
  short keys to files/globs and opens the resolved set in `$EDITOR`; `edit -r <key>` also renames
  the current tmux window to `<key>`.

- **`notes`** — sets and creates `NOTES_DIR="$SCRATCH/notes/$WENV"`, and if `wenv_files` is
  already declared, registers `wenv_files[notes]="$NOTES_DIR/notes.md"`. Must be loaded *after*
  `edit` in `wenv_extensions` (its own header comment says so) or the registration is skipped.

- **`git-worktree`** — see below.

- **`history`** — swaps in a per-wenv history file (`$XDG_CACHE_HOME/wenv/history/<wenv>`) via
  `fc -pa` and rebinds `^T` to search it. Its own header flags it as WIP and possibly
  history-destroying — don't treat it as a pattern to copy.

- **`nvm`** / **`ssh-agent`** — thin wrappers around existing tools: sourcing `nvm.sh`, and
  start/stop/status for a user-level ssh-agent unit via `systemctl --user` (Linux/systemd-specific,
  not macOS).

### `git-worktree`: shared worktree directories across dependent wenvs

This extension makes `git worktree` addressable through `wd`/`c`, and — combined with
`wenv_deps` — lets a family of related wenvs agree on *where* each project's worktrees live
without any of them hardcoding a path.

It provides three functions, all following `wenv`'s own flag-parsing convention (a `local
usage="..."` block, `getopts`, `shift $((OPTIND-1))`, `-h` for help, unknown flags/missing args
error to stderr and `return 1`):

- **`add-worktree [-b <base>] [-B] [-h] <branch> [<branch> ...]`** — for each `<branch>` argument
  (a literal name or a `git branch --list`-style glob), resolves it against existing local
  branches and runs `git worktree add $GIT_WORKTREES/<branch> <branch>` for every match. `-B`
  creates `<branch>` if nothing matched (instead of erroring/skipping it); `-b <base>` sets the
  start-point for that creation (`git branch <branch> [<base>]`), defaulting to empty so it falls
  through to git's own default (branch from the current `HEAD`). Without `-B`, a branch that
  doesn't exist just prints `branch '<branch>' doesn't exist (use -B to create it)` and moves on
  to the next argument rather than aborting the whole call. Ends with a single call to
  `add-worktrees-to-wenv-dirs` (see below) to register everything just created.
- **`remove-worktree [-f] [-D] [-h] <branch-glob>`** — finds existing worktrees under
  `$GIT_WORKTREES` matching the glob; for each, confirms with the codebase's `[yN]` prompt unless
  `-f` is given, `git worktree remove --force`s it, un-registers `wenv_dirs[worktree/<branch>]` if
  that key is actually set, and (with `-D`) also runs `git branch -D <branch>`. Declining a
  confirmation aborts the whole loop (matches the original, pre-`-f` behavior) rather than just
  skipping that one worktree.
- **`add-worktrees-to-wenv-dirs`** — ensures `wenv_dirs` exists (`declare -Ag wenv_dirs`, so it's
  created fresh if nothing declared it, or left alone/reused if something already did — see the
  gotcha below), then scans `git worktree list` for worktrees already living under
  `$GIT_WORKTREES` and registers each as `wenv_dirs[worktree/<branch>]`. Runs automatically at the
  bottom of the extension file (so every new shell in the wenv picks up worktrees created from
  *other* shells/sessions), and again at the end of `add-worktree`.

**Zsh gotcha driving that `declare -Ag`**: assigning *or even just reading* a subscript like
`wenv_dirs[worktree/foo]` when `wenv_dirs` isn't already declared as an associative array doesn't
error the way you'd expect — zsh silently treats it as a normal (integer-indexed) array and
evaluates the subscript string *arithmetically*. `worktree/foo` gets parsed as
`worktree` (undefined variable → `0`) divided by `foo` (undefined → `0`), i.e. `0/0`, which fails
with `division by zero` — a genuinely confusing error to hit from what looks like a plain
associative-array access. `add-worktrees-to-wenv-dirs` declaring `wenv_dirs` up front sidesteps
this for its own writes; `remove-worktree`'s existence check (`${wenv_dirs[worktree/$branch]+0}`)
is exposed to the same failure mode if `wenv_dirs` is *never* declared anywhere in the shell, but
in practice that can't happen once `git-worktree` has loaded at all, since loading it always runs
`add-worktrees-to-wenv-dirs` once.

All three key off one variable, `$GIT_WORKTREES`, which this extension never sets itself — it's
expected to already be exported by the time the extension loads. That expectation is the
integration point with `wenv_deps`: a shared wenv computes `$GIT_WORKTREES` once, and everything
that depends on it (directly or transitively) inherits the convention. Hypothetical example —
say you have several related wenvs (`myorg/service-a`, `myorg/service-b`, ...) that all want
worktrees for their respective repos organized under a common root, keyed by service name:

- `myorg/base` loads the `git-worktree` extension and sets
  `export GIT_WORKTREES="$SCRATCH/myorg/$SERVICE"`.
- Each per-project leaf wenv (`myorg/service-a`, `myorg/service-b`, ...) sets
  `SERVICE='service-a'` (etc.) **before** its own `only_load_wenv_vars` guard, and lists
  `myorg/base` as a dependency — possibly transitively, e.g. `service-a` depends on
  `myorg/shared-helpers`, which itself depends on `myorg/base`.
- `source_wenv_dependencies_recursively` (`wenv:246`) sources each dependency's *entire* file in
  the same shell. Because the leaf wenv's plain `SERVICE=...` assignment runs unconditionally
  (it's above that wenv's own guard, and is evaluated during the initial
  `only_load_wenv_vars=1 source` pass), `$SERVICE` is already set in the shell by the time
  `myorg/base`'s body is later sourced for real and evaluates its `$GIT_WORKTREES` line — so each
  project transparently gets its own worktree directory (`$SCRATCH/myorg/service-a`,
  `$SCRATCH/myorg/service-b`, etc.) without `base` needing to know about any specific project.
- There's no validation: a dependent wenv that forgets to set `SERVICE` before pulling in `base`
  just silently gets `$SCRATCH/myorg/` (empty `$SERVICE`) instead of a per-project directory.

## Developing/testing changes

There's no test suite or linter wired into this repo. To validate a change to `wenv`, `_wenv`,
`completion.bash`, `template`, or an extension:

- Re-source the modified file into a running shell (`source wenv`, or `exec zsh` if
  something is cached) and exercise the affected subcommand(s) directly.
- For anything touching `wenv_start`/`wenv_source`/tmux hookups, test inside an actual tmux
  session — the tmux session lifecycle and the `/tmp/wenv/start-*` handoff script can't be
  meaningfully verified outside of one.
- For completion changes, test both `_wenv` (Zsh, `compdef`-based) and `completion.bash` (Bash) —
  they are maintained independently and can drift.
- `shellcheck` is available locally and is reasonable to run manually against `wenv` and
  `extensions/*`, though it isn't wired into any CI (there is none).
