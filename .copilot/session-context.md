# Wenv Nushell Migration — Session Context

## Status as of 2026-08-12

### What's Done

- **wenv.nu** fully ported: `wenv start`, `wenv source`, `wenv reload`, `wenv cd`, `wenv edit`, `wenv new`, `wenv rm`, `wenv mv`, `wenv ls`, extensions
- **`wenv_sources`**: supports relative paths + globs, resolved against WENV_DIR
- **`wenv_overlays`**: `overlay use --prefix --reload` via tmux `paste-buffer -p` (bracket paste mode)
- **`wenv source`** pastes ALL commands (env setup + source lines + overlay use lines) directly into REPL via bracket paste — this ensures def reloading works
- **`wenv reload`** exists for reloading specific source files (also uses paste-buffer)
- **Module conversion done** for: vantage-api.nu, vantage-core.nu, vantage-engine.nu, vantage-identity.nu, wayfinder.nu, vsm.nu
- **Cross-module deps**: vsm.nu imports from vantage-api.nu via `use ./vantage-api.nu [list-route-versions, get-route-version]`
- **mod.nu** cleaned up — no longer re-exports API files (they're overlays now)
- **Hook scripts** for new tmux panes: `run-shell` regenerates pane file then sources it (overlays inside work on first load)
- **Git history cleaned up**: the 6 commits on `impl/nushell` authored with the work email (`david_grisham1@homedepot.com`) were rewritten to `dmgrisham@gmail.com` via `git filter-branch --env-filter`, verified byte-identical trees, and force-pushed to `origin/impl/nushell`. A local safety-net branch `backup/impl-nushell-pre-email-fix` still exists (delete once confident: `git branch -D backup/impl-nushell-pre-email-fix`). Note: local `git config user.email` was NOT changed — new commits in this repo will still use whatever is currently configured.
- **Fixed wenv_deps not inheriting a dependency's sources/overlays** (see below) — currently **uncommitted** in `nu/wenv.nu`.
- **Fixed generated scripts living in `/tmp/wenv`** causing intermittent `'/tmp/wenv/hook-<wenv>.sh' return 127` in new panes after a wenv session had been running for a while (see below) — currently **uncommitted** in `nu/wenv.nu`.

### Dependency resolution fix (uncommitted)

**Bug**: a wenv depending on another wenv (e.g. `home-depot/vantage-service-management` depends on `home-depot/api-testing-helpers`) only inherited the dependency's core module + extensions — NOT the dependency's own `wenv_sources` (glob-resolved files) or `wenv_overlays` (overlay modules). Concretely, `vantage-service-management` never got `api-testing-helpers`'s `nu/*.nu` files or its 6 overlay modules (vapi/core/engine/identity/wf/vsm).

Root cause: this is nushell-port-specific. The original zsh `wenv` just re-`source`s a dependency's *entire* file recursively (`source_wenv_dependencies_recursively` in `/Users/NSY867X/src/wenv/wenv:246`), so any inline `source` calls written directly in that file ran naturally every time. The nushell port replaced inline sourcing with declarative `wenv_sources`/`wenv_overlays` fields, but the recursive dependency walker (`wenv-resolve-sources`) was never updated to pull those fields from each level of the dependency chain — it only read them from the top-level wenv's own config.

**Fix applied**: replaced `wenv-resolve-sources` with `wenv-resolve-config` in `nu/wenv.nu` (~line 53). It recurses depth-first through `wenv_deps` and merges `sources`/`overlays`/generated `cmds` from every dependency, not just the top-level wenv. `wenv-generate-source-script` now uses that merged result, and also writes the merged `$env.wenv_sources`/`$env.wenv_overlays` into the generated script (previously these only ever reflected the top wenv's own — now-empty for `vantage-service-management` — values, which also silently broke `wenv reload` for anything relying on a dependency's sources).

**Verified end-to-end**: sourced the generated script for `vantage-service-management` in a fresh `nu` process — confirmed all 7 of `api-testing-helpers`'s `nu/*.nu` source files loaded (`$env.wenv_sources | length` == 7) and all 6 overlay modules loaded (`$env.wenv_overlays | length` == 6, and the `vsm` overlay alone contributed 5 subcommands via `scope commands`).

**Not yet done**: this fix has NOT been tested through the actual `wenv source`/`wenv start` command flow (tmux pane + paste-buffer) — only verified by directly invoking `wenv-resolve-config` / `wenv-generate-source-script` via `nu -c`. Also not yet committed.

### `/tmp/wenv` → `~/.cache/wenv` fix (uncommitted)

**Symptom reported**: after a wenv had been running for a while, opening a new pane/window showed `'/tmp/wenv/hook-<wenv>.sh' return 127` and the wenv didn't get sourced into the new shell — but `wenv source` run manually still worked fine.

**Root cause**: `wenv start` registers a tmux hook (`after-split-window`/`after-new-window`) that points at a fixed file path, `/tmp/wenv/hook-<name>.sh`. That `tmux set-hook` registration lives in the tmux server for the life of the session — but `/tmp` contents are not guaranteed to persist that long (periodic OS tmp-cleaning, disk cleanup tools, etc. can sweep it). Once the hook script (or the `regen-*.nu`/`pane-*.nu` files it depends on) is gone, `run-shell` fails with exit 127 ("command not found") on every new pane, and nothing regenerates it since only `wenv start` (re-)writes that file. `wenv source`, by contrast, regenerates and immediately uses its own scratch files fresh on every invocation, so it's unaffected.

**Fix applied**: added `$env.WENV_CACHE` (defaults to `$XDG_CACHE_HOME/wenv` or `~/.cache/wenv`) at the top of `nu/wenv.nu`, and replaced every `/tmp/wenv` reference (pane/hook/regen/source/reload/ext-load scripts, ~15 call sites) with `$env.WENV_CACHE`. Also propagated `XDG_CACHE_HOME` into the hook's `regen-*.nu` bootstrap lines (mirroring the existing `XDG_CONFIG_HOME` handling) so the hook's subprocess reconstructs the same cache path. `~/.cache` isn't subject to OS tmp-sweeping the way `/tmp` is, so the hook script now survives for the life of the tmux session.

**Verified**: parse-checked the file, confirmed `$env.WENV_CACHE` resolves to `~/.cache/wenv` by default, confirmed `wenv-generate-source-script` still produces a correct merged script (7 sources / 6 overlays for `vantage-service-management`) writing into the new cache dir. NOT yet tested through a real `wenv start` + tmux hook firing.

**Operational note**: any currently-running wenv tmux sessions have hooks still pointing at the old `/tmp/wenv/hook-*.sh` paths — they need `wenv start <wenv>` run once more (after this fix lands) to re-register the hook against the new `~/.cache/wenv` path. Old files can be left in `/tmp/wenv` (harmless) or manually cleaned up.

### Key Files

| File | Purpose |
|------|---------|
| `/Users/NSY867X/src/wenv/nu/wenv.nu` | Main wenv implementation |
| `~/.config/wenv/nu-wenvs/home-depot/api-testing-helpers.nu` | Example wenv config (has all overlays; `wenv_deps = ["home-depot/base"]`) |
| `~/.config/wenv/nu-wenvs/home-depot/vantage-service-management.nu` | Depends on api-testing-helpers; good test case for dep resolution |
| `/Users/NSY867X/src/home-depot/api-testing-helpers/nu/api/*.nu` | Converted overlay modules |
| `/Users/NSY867X/src/home-depot/api-testing-helpers/nu/mod.nu` | Module file (stripped of API re-exports) |
| `~/.cache/wenv/pane-*.nu` | Generated pane files (was `/tmp/wenv/`, moved due to tmp-sweeping bug above) |
| `~/.cache/wenv/hook-*.sh` | tmux hook scripts for new panes |
| `~/.cache/wenv/regen-*.nu` | Standalone regen scripts the hook runs to rebuild the pane file |
| `/Users/NSY867X/src/wenv/wenv` | Original zsh implementation (reference for intended semantics) |

### Key Technical Decisions

1. **paste-buffer -p** (bracket paste) for atomic command injection — no user interruption, no length limit
2. **`wenv_sources`** = flat namespace via `source`, for env/config/utility files
3. **`wenv_overlays`** = namespaced via `overlay use --prefix`, for command modules
4. **`export def main`** in overlay files shows subcommand list via `scope commands | where name =~ '^<alias> ' | select name description | print`
5. **`return` in nushell functions returns null** — don't pipe directly, use `get -o` or check emptiness
6. **Cannot `help <alias>` and show subcommands when `main` is defined** — accepted tradeoff
7. **`sleep 0.05`** in paste-buffer scripts — minimal delay before paste
8. **`wenv-resolve-config` merges deps recursively** (sources + overlays + cmds), depth-first, so a chain of deps loads fully bottom-up before the requesting wenv's own file
9. **Naming convention — `WENV_DIR` (uppercase) vs `wenv_deps`/`wenv_extensions` (lowercase)**: intentional, carried over from the zsh original. Lowercase = config-input vars a user declares in their wenv file (unexported local vars in zsh). Uppercase = the framework's resolved/exported runtime state for the active wenv (literally `export`ed in zsh, e.g. `export WENV_DEPS=("$wenv_deps[@]")`).
10. **Generated scripts go in `$env.WENV_CACHE` (`~/.cache/wenv`), never `/tmp`** — anything a long-lived tmux hook references by path must outlive normal OS tmp-cleaning; `/tmp` is not that place.

### Remaining TODO

- [ ] Test the new dependency-resolution fix through the real `wenv source`/`wenv start` flow (tmux paste-buffer), not just direct `nu -c` invocation
- [ ] Test the `/tmp/wenv` → `~/.cache/wenv` fix through a real `wenv start`, confirm the hook fires correctly on `after-split-window`/`after-new-window` and survives over time
- [ ] Re-run `wenv start <wenv>` for any currently-active wenv tmux sessions to pick up the new `~/.cache/wenv` hook path (old sessions still point at `/tmp/wenv/hook-*.sh`)
- [ ] Test `wenv source` with pane-content pasting (still marked untested from before)
- [ ] Test that `wenv reload` still works, especially now that `$env.wenv_sources`/`wenv_overlays` reflect the merged dep set
- [ ] Consider removing `wenv reload` if `wenv source` handles everything (user expressed preference for single command)
- [ ] Verify startup of fresh `wenv start` with all 6 overlays
- [ ] Commit all changes (the dep-resolution fix in `nu/wenv.nu` is currently uncommitted)
- [ ] Port remaining wenvs (only home-depot/api-testing-helpers is done)
- [ ] Optional cleanup: delete local `backup/impl-nushell-pre-email-fix` branch once confident in the rewritten history

### Nushell Limitations to Remember

- `source` inside a sourced file doesn't reload existing defs
- `overlay use --reload` inside a sourced file doesn't reload either
- Both must be direct REPL entries to reload
- `try/catch` closures can't mutate outer scope variables
- `def --env` functions can't be in overlays easily
- tmux `send-keys` sends char-by-char (slow, interruptible); `paste-buffer -p` is atomic
- `help <alias>` only shows module subcommands when `main` is NOT defined

### Misc Session Notes

- This session was renamed to "wenv-nu" via `/rename`.
- Git email rewrite used `git filter-branch --env-filter` (not `git-filter-repo`, which wasn't installed) — fine for this repo's small size (362 total commits, only 6 needed rewriting). Backup branch `backup/impl-nushell-pre-email-fix` and git's own `refs/original/refs/heads/impl/nushell` ref were left in place as safety nets.
