# Wenv: Zsh → Nushell Migration Guide

## Overview

The wenv system was ported from zsh to nushell. This doc covers how to transform existing command files to work with the new overlay-based module system.

---

## Wenv Config File (`~/.config/wenv/nu-wenvs/<name>.nu`)

### Structure

```nushell
$env.WENV_DIR = "/path/to/project"
$env.wenv_deps = ["parent/dep"]          # optional, other wenvs to load first
$env.wenv_extensions = ["wd" "edit"]     # optional, from nu/extensions/
$env.wenv_sources = [
    "nu/*.nu"                            # relative paths/globs resolved against WENV_DIR
]

$env.wenv_overlays = [
    {file: "nu/api/my-service.nu", as: "svc"}   # loaded via `overlay use ... --prefix --reload`
]

if ($env | get -o only_load_wenv_vars | default false) { return }

# Everything below here only runs when sourced normally (not when loading vars)
def startup_wenv [] {}
def shutdown_wenv [] {}
def bootstrap_wenv [] {}

# env vars, aliases, helper functions, etc.
```

### Key rules

- `wenv_sources`: list of relative paths or globs (resolved against `$env.WENV_DIR`). Absolute paths also work. These are loaded via `source` — flat namespace, all defs available globally.
- `wenv_overlays`: list of `{file, as}` records. Each becomes `overlay use <file> as <alias> --prefix --reload`. Commands are namespaced under the alias (e.g., `svc list-items`).
- The `if ... only_load_wenv_vars ... return` guard **must** exist — it allows the system to extract config vars without executing side effects.

---

## Converting Command Files to Overlay Modules

Files listed in `wenv_overlays` must follow nushell module format.

### Before (zsh-style defs, sourced flat):

```nushell
export def "svc list-items" [...] { ... }
export def "svc get-item" [...] { ... }
export def "svc create-item" [...] { ... }
```

### After (module format for overlay):

```nushell
# Module doc comment
# Subcommand pattern: `svc list-items`, `svc get-item`, etc.

use ../config.nu [some-helper]    # relative `use` for deps within the project
use ../http.nu [http-get]

# Shows subcommand list when user types just the alias with no subcommand
export def main [] { scope commands | where name =~ '^svc ' | select name description | print }

export def "list-items" [...] { ... }
export def "get-item" [...] { ... }
export def "create-item" [...] { ... }
```

### Transformation steps:

1. **Strip the command prefix** from all `export def` names:
   - `export def "svc list-items"` → `export def "list-items"`
   - `export def "svc get-item"` → `export def "get-item"`

2. **Rename the root help def to `main`** (or create one):
   - If you had `export def svc [] { help svc }` → remove it
   - Add: `export def main [] { scope commands | where name =~ '^<alias> ' | select name description | print }`
   - Replace `<alias>` with what you'll use in `wenv_overlays` `as` field

3. **Do NOT export a def with the same name as the file** (nushell restriction):
   - File `foo.nu` cannot have `export def foo [...]` — use `export def main` instead

4. **Add relative `use` imports** for dependencies:
   - If the file calls functions from other source files, add explicit `use` at the top
   - Format: `use ../http.nu [http-get]` or `use ../util.nu *`

5. **Cross-module dependencies** (one overlay calling another overlay's commands):
   - Add `use ./other-module.nu [command-name]` at the top
   - Use the **unprefixed** name (as defined in the module), e.g.:
     ```nushell
     use ./other-module.nu [list-items, get-item]
     ```
   - Then call directly: `list-items --flag $val`

6. **Remove any `help <old-name>` calls** — they won't resolve inside modules

---

## Wenv Sources vs Overlays: When to Use Which

| Feature | `wenv_sources` | `wenv_overlays` |
|---------|---------------|-----------------|
| Namespace | Flat (global) | Prefixed (`alias cmd`) |
| Def reload on `wenv source` | ✅ Yes | ✅ Yes |
| Can use `def --env` | ✅ Yes | ⚠️ Limited |
| Module format required | No | Yes |
| Tab completion on prefix | N/A | ✅ `svc <tab>` |

**Use `wenv_sources` for:**
- Config/env setup files
- Utility functions used everywhere
- Files with `def --env` (environment mutation)

**Use `wenv_overlays` for:**
- Command modules (many commands under one prefix)
- Anything you want namespaced to avoid collisions
- Files where reload-on-change matters most

---

## Nushell Gotchas

- **`return` in a function returns `null`** — downstream pipeline steps still run. Use `error make {msg: "..."}` to stop the pipeline, or guard with `get -o` / `is-not-empty` checks on the caller side.
- **`help <alias>` shows module info only if `main` is NOT defined.** With `main` defined, `help <alias>` shows command help instead. Tradeoff: without `main`, typing `<alias>` alone errors.
- **`source` inside a sourced file won't reload existing defs.** That's why `wenv source` pastes commands directly into the REPL via tmux paste-buffer.
- **`overlay use --reload` inside a sourced file also won't reload.** Must be a direct REPL entry.
- **Globs in `wenv_sources`** support `*`, `?`, `[...]` patterns (e.g., `nu/*.nu`, `lib/**/*.nu`).
