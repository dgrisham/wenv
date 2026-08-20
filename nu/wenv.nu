# wenv — working environment manager for Nushell
# Ported from the zsh version

$env.WENV_DIR = $"($env.SRC)/wenv"
$env.WENV_CFG = ($env | get -o XDG_CONFIG_HOME | default $"($env.HOME)/.config" | path join "wenv")
$env.WENV_EXT = $"($env.SRC)/wenv/nu/extensions"
$env.NOTES_DIR = $"($env.SCRATCH)/notes/wenv"
# Generated scripts (pane/hook/regen files) live here rather than /tmp: tmux hooks
# reference these paths for the life of the tmux session, but /tmp is subject to
# periodic OS cleanup — if a referenced file gets swept, `run-shell` fails with
# "returned 127" on every new pane until `wenv start` re-registers the hook.
$env.WENV_CACHE = ($env | get -o XDG_CACHE_HOME | default $"($env.HOME)/.cache" | path join "wenv")

def startup_wenv [] {}
def shutdown_wenv [] {}
def bootstrap_wenv [] {}

if ($env | get -o only_load_wenv_vars | default false) { return }

# ---- helpers ----

# Resolve wenv_sources entries: expand globs, resolve relative paths against wenv dir
# Returns {files: list<string>, errors: list<string>}
def wenv-resolve-source-entries [entries: list<string>, dir: string] {
    mut resolved = []
    mut errors = []
    for entry in $entries {
        let full = if ($entry | str starts-with "/") { $entry } else { $"($dir)/($entry)" }
        if ($full =~ '[*?\[]') {
            let result = (try { glob $full | to nuon } catch { "ERROR" })
            if ($result == "ERROR") {
                $errors = ($errors | append $"failed to expand glob '($entry)' \(($full)\)")
            } else {
                $resolved = ($resolved | append ($result | from nuon))
            }
        } else {
            $resolved = ($resolved | append $full)
        }
    }
    {files: $resolved, errors: $errors}
}

def wenv-is-wenv [name: string] {
    ($"($env.WENV_CFG)/nu-wenvs/($name).nu" | path exists)
}

# Load just the config vars from a wenv file (runs in subprocess)
def wenv-load-vars [name: string] {
    let file = $"($env.WENV_CFG)/nu-wenvs/($name).nu"
    let cmd = ([
        "$env.only_load_wenv_vars = true"
        $"source ($file)"
        "{dir: $env.WENV_DIR, deps: ($env | get -o wenv_deps | default []), extensions: ($env | get -o wenv_extensions | default []), sources: ($env | get -o wenv_sources | default []), overlays: ($env | get -o wenv_overlays | default [])} | to nuon"
    ] | str join "; ")
    nu --no-config-file -c $cmd | from nuon
}

# Recursively resolve a wenv + its dependencies (depth-first), returning:
#   cmds:     ordered list of nushell command strings to run (source/overlay use/errors)
#   sources:  flat list of every resolved wenv_sources file (own + all deps)
#   overlays: flat list of every resolved wenv_overlays entry (own + all deps)
#   has_errors: whether any wenv_sources glob failed to resolve, anywhere in the chain
def wenv-resolve-config [name: string] {
    let config = (wenv-load-vars $name)
    mut cmds = []
    mut all_sources = []
    mut all_overlays = []
    mut has_errors = false

    # Resolve deps first (depth-first) — each dep's own sources/overlays are included too
    for dep in $config.deps {
        let dep_result = (wenv-resolve-config $dep)
        $cmds = ($cmds | append $dep_result.cmds)
        $all_sources = ($all_sources | append $dep_result.sources)
        $all_overlays = ($all_overlays | append $dep_result.overlays)
        $has_errors = ($has_errors or $dep_result.has_errors)
    }

    # Add extensions
    for ext in $config.extensions {
        let ext_file = $"($env.WENV_EXT)/($ext).nu"
        if ($ext_file | path exists) {
            $cmds = ($cmds | append $"source ($ext_file)")
        }
    }

    # Add the wenv itself
    $cmds = ($cmds | append $"source ($env.WENV_CFG)/nu-wenvs/($name).nu")

    # Include this wenv's own wenv_sources — resolve relative paths and expand globs
    let source_result = (wenv-resolve-source-entries $config.sources $config.dir)
    if ($source_result.errors | is-not-empty) {
        $has_errors = true
        for err in $source_result.errors {
            let escaped = ($err | str replace --all '"' '\"')
            $cmds = ($cmds | append $"print -e \"wenv_sources: ($escaped)\"")
        }
    } else {
        $all_sources = ($all_sources | append $source_result.files)
        for src in $source_result.files {
            $cmds = ($cmds | append $"source ($src)")
        }
    }

    # Include this wenv's own wenv_overlays — overlay use with --reload
    for entry in $config.overlays {
        let file = if ($entry.file | str starts-with "/") { $entry.file } else { $"($config.dir)/($entry.file)" }
        let alias = ($entry | get -o as | default "")
        $all_overlays = ($all_overlays | append {file: $file, as: $alias})
        if ($alias | is-not-empty) {
            $cmds = ($cmds | append $"overlay use ($file) as ($alias) --prefix --reload")
        } else {
            $cmds = ($cmds | append $"overlay use ($file) --reload")
        }
    }

    {cmds: $cmds, sources: $all_sources, overlays: $all_overlays, has_errors: $has_errors}
}

# Generate a source script that loads a wenv + deps + extensions
def wenv-generate-source-script [name: string, --startup] {
    mkdir $env.WENV_CACHE
    let config = (wenv-load-vars $name)
    let resolved = (wenv-resolve-config $name)

    mut lines = [
        $"$env.WENV = '($name)'"
        $"$env.WENV_DIR = '($config.dir)'"
        $"$env.WENV_DEPS = ($config.deps | to nuon)"
        $"$env.WENV_EXTENSIONS = ($config.extensions | to nuon)"
    ]

    $lines = ($lines | append $resolved.cmds)

    # Reflect the fully-merged (own + deps) sources/overlays so `wenv reload` can see all of them
    $lines = ($lines | append $"$env.wenv_sources = ($resolved.sources | to nuon)")
    $lines = ($lines | append $"$env.wenv_overlays = ($resolved.overlays | to nuon)")

    if $startup {
        $lines = ($lines | append [
            $"cd ($config.dir)"
            "tmux set-environment WENV $env.WENV"
            "try { startup_wenv }"
        ])
        if not $resolved.has_errors {
            $lines = ($lines | append "clear")
        }
    } else if not $resolved.has_errors {
        $lines = ($lines | append "clear -k")
    }

    $lines | str join "\n"
}



# ---- completions ----

export def wenv-complete-names [] {
    glob $"($env.WENV_CFG)/nu-wenvs/**/*.nu" --no-dir
    | each { str replace $"($env.WENV_CFG)/nu-wenvs/" "" | str replace ".nu" "" }
    | sort
}

export def wenv-complete-extensions [] {
    glob $"($env.WENV_EXT)/*.nu" --no-dir
    | each { path basename | str replace ".nu" "" }
    | sort
}

# ---- subcommands ----

export def "wenv" [...args: string] {
    if ($args | is-not-empty) {
        print -e $"unknown command: wenv ($args | str join ' ')"
    }
    print "Usage: wenv <command>

Commands:
  ls                List all wenvs
  start <wenv>      Start a wenv (tmux session)
  stop              Stop the current wenv
  source <wenv>     Source a wenv in the current shell
  cd [wenv]         cd into a wenv's directory
  edit [wenv]       Edit a wenv file
  new <name>        Create a new wenv
  rm <wenv>         Remove a wenv
  mv <old> <new>    Rename a wenv
  bootstrap <wenv>  Run a wenv's bootstrap function
  extension         Manage extensions (load/edit/remove)"
}

export def "wenv ls" [] {
    glob $"($env.WENV_CFG)/nu-wenvs/**/*.nu" --no-dir
    | each { str replace $"($env.WENV_CFG)/nu-wenvs/" "" | str replace '.nu' '' }
    | sort
}

export def --env "wenv cd" [name?: string@wenv-complete-names] {
    let wenv = ($name | default ($env | get -o WENV | default ""))
    if ($wenv | is-empty) {
        if ($env | get -o WENV_DIR | is-not-empty) {
            cd $env.WENV_DIR
        }
        return
    }
    if not (wenv-is-wenv $wenv) {
        print -e $"wenv '($wenv)' doesn't exist"
        return
    }
    let config = (wenv-load-vars $wenv)
    if ($config.dir | is-empty) {
        print -e $"WENV_DIR not defined for wenv '($wenv)'"
        return
    }
    cd $config.dir
}

export def "wenv edit" [name?: string@wenv-complete-names] {
    let wenv = ($name | default ($env | get -o WENV | default ""))
    let file = $"($env.WENV_CFG)/nu-wenvs/($wenv).nu"
    if ($file | path exists) {
        run-external $env.EDITOR $file
    } else {
        print -e $"wenv '($wenv)' doesn't exist"
    }
}

export def "wenv rm" [name: string@wenv-complete-names] {
    if not (wenv-is-wenv $name) {
        print -e $"wenv '($name)' doesn't exist"
        return
    }
    rm $"($env.WENV_CFG)/nu-wenvs/($name).nu"
}

export def "wenv mv" [old: string@wenv-complete-names, new: string] {
    let old_file = $"($env.WENV_CFG)/nu-wenvs/($old).nu"
    let new_file = $"($env.WENV_CFG)/nu-wenvs/($new).nu"

    if not ($old_file | path exists) {
        print -e $"wenv '($old)' does not exist"
        return
    }

    mut actual_old = $old_file

    if ($new_file | path dirname | path exists) and ($new_file | path dirname | path type) == "dir" {
        let new_dir = ($new_file | path dirname)
        # check if old lives inside new's directory path — collapse intermediate dirs
        if ($old_file | str starts-with $"($new_dir)/") or ($old_file | str starts-with $"($new_file)/") {
            let old_tmp = $"($new_file).tmp"
            mv $old_file $old_tmp
            # clean empty subdirs
            do { ^find $new_dir -depth -type d -empty -delete } | complete
            if ($new_file | path exists) {
                mkdir ($old_file | path dirname)
                mv $old_tmp $old_file
                print -e $"directory '($new)' is not empty - cannot move"
                return
            }
            $actual_old = $old_tmp
        } else if ($new_file | path dirname) == $old_file or (($new_file | path dirname) | str starts-with $"($old_file)/") {
            # new lives inside old — move old to temp first
            let old_tmp = $"($old_file).tmp"
            mv $old_file $old_tmp
            $actual_old = $old_tmp
        }
    }

    if ($new_file | path exists) and ($new_file | path type) == "dir" {
        do { ^find ($new_file) -depth -type d -empty -delete } | complete
        if ($new_file | path exists) {
            if $actual_old != $old_file {
                # restore from temp
                mkdir ($old_file | path dirname)
                mv $actual_old $old_file
            }
            print -e $"directory '($new)' is not empty - cannot move"
            return
        }
    } else if ($new_file | path exists) {
        print -e $"wenv '($new)' already exists"
        return
    }

    mkdir ($new_file | path dirname)
    let _actual_old = $actual_old
    try {
        mv $_actual_old $new_file
    } catch {
        if $_actual_old != $old_file {
            print -e $"move failed - original wenv saved at ($_actual_old)"
        }
        print -e "move failed"
    }
}

export def "wenv new" [
    name: string
    --dir (-d): string
    --init (-i): string
] {
    let wenv_path = $"($env.WENV_CFG)/nu-wenvs/($name).nu"

    if (wenv-is-wenv $name) {
        let answer = (input $"wenv '($name)' already exists. overwrite? [yN] ")
        if ($answer !~ '^[yY]') { return }
        rm -f $wenv_path
    } else if ($wenv_path | path exists) and ($wenv_path | path type) == "dir" {
        do { ^find $wenv_path -depth -type d -empty -delete } | complete
        if ($wenv_path | path exists) {
            print -e $"directory '($wenv_path)' is not empty - cannot create wenv"
            return
        }
    }

    let wenv_dir = ($dir | default (pwd))
    let template = if ($init | is-not-empty) {
        $"($env.WENV_CFG)/nu-wenvs/($init).nu"
    } else {
        $"($env.WENV_CFG)/template.nu"
    }

    let parent = ($wenv_path | path dirname)
    if not ($parent | path exists) {
        mkdir $parent
    }

    open $template
    | str replace --regex 'WENV_DIR = .*' $'WENV_DIR = "($wenv_dir)"'
    | save -f $wenv_path

    wenv edit $name
}

# Reload a wenv. Regenerates pane file and sources it.
# For reloading updated defs in specific files, use `wenv reload`.
export def --env "wenv source" [
    name?: string@wenv-complete-names
    --cd (-c)
] {
    let wenv = ($name | default ($env | get -o WENV | default ""))
    if ($wenv | is-empty) {
        print -e "no wenv arg provided and $env.WENV is empty"
        return
    }
    if not (wenv-is-wenv $wenv) {
        print -e $"wenv '($wenv)' doesn't exist"
        return
    }

    # Regenerate pane file
    mkdir $env.WENV_CACHE
    let tmp_name = ($wenv | str replace --all "/" "-")
    let pane_file = $"($env.WENV_CACHE)/pane-($tmp_name).nu"
    (wenv-generate-source-script $wenv) | save -f $pane_file

    let pane = (^tmux display-message -p '#{session_name}:#{window_index}.#{pane_index}' | str trim)
    let config = (wenv-load-vars $wenv)

    # Build commands: all lines from pane file as direct REPL entries (so defs reload)
    let pane_content = (open $pane_file | lines | where { |l| ($l | str trim) != "" and ($l | str trim) != "clear -k" and ($l | str trim) != "clear" })
    mut cmds = []
    if $cd {
        $cmds = ($cmds | append $"cd ($config.dir)")
    }
    $cmds = ($cmds | append $pane_content)
    # Overlays are already in the pane file, no need to add again

    # Paste all commands atomically using bracket paste mode (-p)
    $cmds = ($cmds | append "clear -k")
    let joined = (" " + ($cmds | str join "; "))
    let reload_script = $"($env.WENV_CACHE)/source-cmd-($tmp_name).sh"
    let buf_file = $"($env.WENV_CACHE)/source-buf-($tmp_name).txt"
    let buf_name = $"wenv-($tmp_name)"
    $joined | save -f $buf_file
    let lines = [
        "#!/bin/sh"
        "sleep 0.05"
        $"tmux load-buffer -b '($buf_name)' '($buf_file)'"
        $"tmux paste-buffer -p -b '($buf_name)' -t '($pane)'"
        $"tmux send-keys -t '($pane)' Enter"
    ]
    ($lines | str join "\n") | save -f $reload_script
    ^chmod +x $reload_script
    ^tmux run-shell -b $reload_script
}

# Completer for wenv reload: returns expanded wenv_sources relative to WENV_DIR
def wenv-complete-sources [] {
    let dir = ($env | get -o WENV_DIR | default "")
    if ($dir | is-empty) { return [] }
    let sources = ($env | get -o wenv_sources | default [])
    let result = (wenv-resolve-source-entries $sources $dir)
    $result.files | each { |f|
        let rel = ($f | str replace $"($dir)/" "")
        $rel
    }
}

# Reload specific source files to pick up updated defs.
# Each file is sourced as a separate REPL entry so defs are replaced.
export def --env "wenv reload" [
    ...patterns: string@wenv-complete-sources
] {
    let dir = ($env | get -o WENV_DIR | default "")
    if ($dir | is-empty) {
        print -e "no active wenv"
        return
    }

    # Resolve patterns to files
    mut files = []
    if ($patterns | is-empty) {
        # No args = reload all wenv_sources
        let sources = ($env | get -o wenv_sources | default [])
        let result = (wenv-resolve-source-entries $sources $dir)
        if ($result.errors | is-not-empty) {
            for err in $result.errors { print -e $"wenv reload: ($err)" }
            return
        }
        $files = $result.files
    } else {
        for pat in $patterns {
            let full = if ($pat | str starts-with "/") { $pat } else { $"($dir)/($pat)" }
            if ($full =~ '[*?\[]') {
                let result = (try { glob $full | to nuon } catch { "ERROR" })
                if ($result == "ERROR") {
                    print -e $"wenv reload: failed to expand glob '($pat)'"
                    return
                }
                $files = ($files | append ($result | from nuon))
            } else {
                $files = ($files | append $full)
            }
        }
    }

    if ($files | is-empty) {
        print -e "no files to reload"
        return
    }

    let pane = (^tmux display-message -p '#{session_name}:#{window_index}.#{pane_index}' | str trim)
    let tmp_name = ($env.WENV | str replace --all "/" "-")

    # Batch all source commands + clear into one paste-buffer
    let cmds = ($files | each { |f| $"source ($f)" } | append "clear -k")
    let joined = (" " + ($cmds | str join "; "))
    let reload_script = $"($env.WENV_CACHE)/reload-($tmp_name).sh"
    let buf_file = $"($env.WENV_CACHE)/reload-buf-($tmp_name).txt"
    let buf_name = $"wenv-reload-($tmp_name)"
    $joined | save -f $buf_file
    let lines = [
        "#!/bin/sh"
        "sleep 0.05"
        $"tmux load-buffer -b '($buf_name)' '($buf_file)'"
        $"tmux paste-buffer -p -b '($buf_name)' -t '($pane)'"
        $"tmux send-keys -t '($pane)' Enter"
    ]
    ($lines | str join "\n") | save -f $reload_script
    ^chmod +x $reload_script
    ^tmux run-shell -b $reload_script
}

export def --env "wenv start" [
    ...names: string@wenv-complete-names
    --no-init (-i)
    --detach (-d)
] {
    if ($names | is-empty) { return }

    let flag_d = $detach or ($names | length) > 1

    for wenv in $names {
        if not (wenv-is-wenv $wenv) {
            print -e $"wenv '($wenv)' does not exist"
            continue
        }

        let config = (wenv-load-vars $wenv)

        let sessions = (do { tmux list-sessions } | complete)
        let running = ($sessions.stdout | str contains $"($wenv):")

        # Always regenerate source files and hooks (even if session exists)
        mkdir $env.WENV_CACHE
        let tmp_name = ($wenv | str replace --all "/" "-")
        let pane_file = $"($env.WENV_CACHE)/pane-($tmp_name).nu"
        (wenv-generate-source-script $wenv) | save -f $pane_file

        # Generate a standalone regen script (runs with nu --no-config-file)
        let regen_file = $"($env.WENV_CACHE)/regen-($tmp_name).nu"
        let xdg = ($env | get -o XDG_CONFIG_HOME | default "")
        let xdg_cache = ($env | get -o XDG_CACHE_HOME | default "")
        mut regen_lines = [
            $"$env.HOME = '($env.HOME)'"
            $"$env.SRC = '($env.SRC)'"
            $"$env.SCRATCH = '($env.SCRATCH)'"
        ]
        if ($xdg | is-not-empty) {
            $regen_lines = ($regen_lines | append $"$env.XDG_CONFIG_HOME = '($xdg)'")
        }
        if ($xdg_cache | is-not-empty) {
            $regen_lines = ($regen_lines | append $"$env.XDG_CACHE_HOME = '($xdg_cache)'")
        }
        $regen_lines = ($regen_lines | append [
            $"source ($env.SRC)/wenv/nu/wenv.nu"
            $"\(wenv-generate-source-script '($wenv)'\) | save -f ($pane_file)"
        ])
        ($regen_lines | str join "\n") | save -f $regen_file

        let nu_bin = (which nu | first | get path)

        if not $running {
            tmux new-session -d -s $wenv $nu_bin --login --config ~/.config/nushell/config.nu --env-config ~/.config/nushell/env.nu

            # Generate startup script (includes cd, startup_wenv, clear)
            let start_file = $"($env.WENV_CACHE)/source-($tmp_name).nu"
            if $no_init {
                (wenv-generate-source-script $wenv) | save -f $start_file
            } else {
                (wenv-generate-source-script $wenv --startup) | save -f $start_file
            }

            tmux send -t $wenv $"source ($start_file)" ENTER
        }

        # Set tmux hooks so new panes auto-source the wenv
        # Use a wrapper script so run-shell gets a single clean argument
        let hook_script = $"($env.WENV_CACHE)/hook-($tmp_name).sh"
        ([
            "#!/bin/sh"
            $"($nu_bin) --no-config-file ($regen_file) 2>/dev/null"
            $"tmux send-keys -t \"$TMUX_PANE\" 'source ($pane_file)' Enter"
        ] | str join "\n") | save -f $hook_script
        ^chmod +x $hook_script
        tmux set-hook -t $wenv after-split-window $"run-shell ($hook_script)"
        tmux set-hook -t $wenv after-new-window $"run-shell ($hook_script)"

        if not $running {
            if $flag_d {
                print $"started wenv '($wenv)'"
                continue
            }
        } else {
            if $flag_d {
                print $"wenv '($wenv)' already running"
                continue
            }
        }

        if ($env | get -o TMUX | is-not-empty) {
            tmux switch -t $wenv
        } else {
            tmux attach-session -t $wenv
        }
    }
}

export def --env "wenv stop" [
    --force (-f)
    --no-shutdown (-s)
] {
    let wenv = ($env | get -o WENV | default "")
    if ($wenv | is-empty) { return }

    wenv cd

    if not $no_shutdown {
        try { shutdown_wenv }
    }

    # Clean up per-session tmux hooks and source files
    if ($env | get -o TMUX | is-not-empty) {
        do { ^tmux set-hook -u -t $wenv after-split-window } | complete
        do { ^tmux set-hook -u -t $wenv after-new-window } | complete
        ^tmux set-environment -u WENV
    }

    let tmp_name = ($wenv | str replace --all "/" "-")
    rm -f $"($env.WENV_CACHE)/source-($tmp_name).nu"
    rm -f $"($env.WENV_CACHE)/pane-($tmp_name).nu"

    hide-env -i WENV WENV_DIR WENV_DEPS WENV_EXTENSIONS
}

export def "wenv bootstrap" [name: string@wenv-complete-names] {
    if not (wenv-is-wenv $name) {
        print -e $"wenv '($name)' doesn't exist"
        return
    }
    let file = $"($env.WENV_CFG)/nu-wenvs/($name).nu"
    # Run bootstrap in subprocess since we can't source dynamically
    nu --no-config-file -c $"source ($file); bootstrap_wenv"
}

export def "wenv extension load" [...extensions: string@wenv-complete-extensions] {
    if ($extensions | is-empty) { return }
    # Generate source script for extensions
    mkdir $env.WENV_CACHE
    mut lines = []
    for ext in $extensions {
        let file = $"($env.WENV_EXT)/($ext).nu"
        if not ($file | path exists) {
            print -e $"'($ext)' not found in ($env.WENV_EXT)"
            return
        }
        $lines = ($lines | append $"source ($file)")
    }
    let tmp_file = $"($env.WENV_CACHE)/ext-load.nu"
    $lines | str join "\n" | save -f $tmp_file
    print $"source ($tmp_file)"
}

export def "wenv extension edit" [...extensions: string@wenv-complete-extensions] {
    if ($extensions | is-empty) { return }
    let files = ($extensions | each {|ext|
        let file = $"($env.WENV_EXT)/($ext).nu"
        if not ($file | path exists) {
            "# wenv extension\n" | save -f $file
        }
        $file
    })
    run-external $env.EDITOR ...$files
}

export def "wenv extension remove" [
    ...extensions: string@wenv-complete-extensions
    --force (-f)
] {
    for ext in $extensions {
        let file = $"($env.WENV_EXT)/($ext).nu"
        if not ($file | path exists) {
            print -e $"Extension '($ext)' does not exist"
            return
        }
        if $force { rm -f $file } else { rm $file }
    }
}
