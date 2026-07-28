# wenv — working environment manager for Nushell
# Ported from the zsh version

$env.WENV_DIR = $"($env.SRC)/wenv"
$env.WENV_CFG = ($env | get -o XDG_CONFIG_HOME | default $"($env.HOME)/.config" | path join "wenv")
$env.WENV_EXT = $"($env.SRC)/wenv/nu/extensions"
$env.NOTES_DIR = $"($env.SCRATCH)/notes/wenv"

def startup_wenv [] {}
def shutdown_wenv [] {}
def bootstrap_wenv [] {}

if ($env | get -o only_load_wenv_vars | default false) { return }

# ---- helpers ----

def wenv-is-wenv [name: string] {
    ($"($env.WENV_CFG)/nu-wenvs/($name).nu" | path exists)
}

# Load just the config vars from a wenv file (runs in subprocess)
def wenv-load-vars [name: string] {
    let file = $"($env.WENV_CFG)/nu-wenvs/($name).nu"
    let cmd = ([
        "$env.only_load_wenv_vars = true"
        $"source ($file)"
        "{dir: $env.WENV_DIR, deps: ($env | get -o wenv_deps | default []), extensions: ($env | get -o wenv_extensions | default [])} | to nuon"
    ] | str join "; ")
    nu --no-config-file -c $cmd | from nuon
}

# Recursively resolve all dependencies, returning a flat list of file paths to source (in order)
def wenv-resolve-sources [name: string] {
    let config = (wenv-load-vars $name)
    mut sources = []

    # Resolve deps first (depth-first)
    for dep in $config.deps {
        let dep_sources = (wenv-resolve-sources $dep)
        $sources = ($sources | append $dep_sources)
    }

    # Add extensions
    for ext in $config.extensions {
        let ext_file = $"($env.WENV_EXT)/($ext).nu"
        if ($ext_file | path exists) {
            $sources = ($sources | append $ext_file)
        }
    }

    # Add the wenv itself
    $sources = ($sources | append $"($env.WENV_CFG)/nu-wenvs/($name).nu")

    $sources
}

# Generate a source script that loads a wenv + deps + extensions
def wenv-generate-source-script [name: string, --startup] {
    mkdir /tmp/wenv
    let sources = (wenv-resolve-sources $name)
    let config = (wenv-load-vars $name)

    mut lines = [
        $"$env.WENV = '($name)'"
        $"$env.WENV_DIR = '($config.dir)'"
        $"$env.WENV_DEPS = ($config.deps | to nuon)"
        $"$env.WENV_EXTENSIONS = ($config.extensions | to nuon)"
    ]

    for src in $sources {
        $lines = ($lines | append $"source ($src)")
    }

    if $startup {
        $lines = ($lines | append [
            $"cd ($config.dir)"
            "tmux set-environment WENV $env.WENV"
            "try { startup_wenv }"
            "clear"
        ])
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

# Generate source script for a wenv and source it via tmux send-keys.
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

    let script = (wenv-generate-source-script $wenv)
    let script_with_cd = if $cd {
        let config = (wenv-load-vars $wenv)
        $"cd ($config.dir)\n($script)"
    } else {
        $script
    }

    mkdir /tmp/wenv
    let tmp_name = ($wenv | str replace --all "/" "-")
    let tmp_file = $"/tmp/wenv/source-($tmp_name).nu"
    $script_with_cd | save -f $tmp_file

    # Send the source command to the current pane via tmux so it executes
    # at the REPL top level (a def can't source into its caller's scope).
    let pane = (^tmux display-message -p '#{session_name}:#{window_index}.#{pane_index}' | str trim)
    ^tmux send -t $pane $"source ($tmp_file)" Enter
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

        let sessions = (do { tmux list-sessions } | complete)
        let running = ($sessions.stdout | str contains $"($wenv):")

        if not $running {
            let nu_bin = (which nu | first | get path)
            tmux new-session -d -s $wenv $nu_bin --login --config ~/.config/nushell/config.nu --env-config ~/.config/nushell/env.nu

            mkdir /tmp/wenv
            let tmp_name = ($wenv | str replace --all "/" "-")
            let tmp_start = $"/tmp/wenv/source-($tmp_name).nu"

            let script = if $no_init {
                wenv-generate-source-script $wenv
            } else {
                wenv-generate-source-script $wenv --startup
            }
            $script | save -f $tmp_start

            # Also write a non-startup version for new panes (no startup_wenv/clear)
            let pane_script = (wenv-generate-source-script $wenv)
            let pane_start = $"/tmp/wenv/pane-($tmp_name).nu"
            $pane_script | save -f $pane_start

            # Set tmux hooks so new panes/windows in this session auto-source the wenv
            let send_cmd = $"send-keys 'source ($pane_start); clear' Enter"
            tmux set-hook -t $wenv after-split-window $send_cmd
            tmux set-hook -t $wenv after-new-window $send_cmd

            # Send source command to the first pane
            tmux send -t $wenv $"source ($tmp_start)" ENTER

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
    rm -f $"/tmp/wenv/source-($tmp_name).nu"
    rm -f $"/tmp/wenv/pane-($tmp_name).nu"

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
    mkdir /tmp/wenv
    mut lines = []
    for ext in $extensions {
        let file = $"($env.WENV_EXT)/($ext).nu"
        if not ($file | path exists) {
            print -e $"'($ext)' not found in ($env.WENV_EXT)"
            return
        }
        $lines = ($lines | append $"source ($file)")
    }
    let tmp_file = "/tmp/wenv/ext-load.nu"
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
