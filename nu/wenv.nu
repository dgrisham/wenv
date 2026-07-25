# wenv — working environment manager for Nushell
# Ported from the zsh version

$env.WENV_CFG = ($env | get -o XDG_CONFIG_HOME | default $"($env.HOME)/.config" | path join "wenv")
$env.WENV_EXT = $"($env.SRC)/wenv/nu/extensions"

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
            "tmux set-environment WENV $env.WENV"
            "startup_wenv"
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
        error make { msg: $"wenv '($wenv)' doesn't exist" }
    }
    let config = (wenv-load-vars $wenv)
    if ($config.dir | is-empty) {
        error make { msg: $"WENV_DIR not defined for wenv '($wenv)'" }
    }
    cd $config.dir
}

export def "wenv edit" [name?: string@wenv-complete-names] {
    let wenv = ($name | default ($env | get -o WENV | default ""))
    let file = $"($env.WENV_CFG)/nu-wenvs/($wenv).nu"
    if ($file | path exists) {
        run-external $env.EDITOR $file
    } else {
        error make { msg: $"wenv '($wenv)' doesn't exist" }
    }
}

export def "wenv rm" [name: string@wenv-complete-names] {
    if not (wenv-is-wenv $name) {
        error make { msg: $"wenv '($name)' doesn't exist" }
    }
    rm $"($env.WENV_CFG)/nu-wenvs/($name).nu"
}

export def "wenv mv" [old: string@wenv-complete-names, new: string] {
    let old_file = $"($env.WENV_CFG)/nu-wenvs/($old).nu"
    let new_file = $"($env.WENV_CFG)/nu-wenvs/($new).nu"
    let new_dir = ($new_file | path dirname)
    if not ($new_dir | path exists) {
        mkdir $new_dir
    }
    mv $old_file $new_file
}

export def "wenv new" [
    name: string
    --dir (-d): string
    --init (-i): string
] {
    if (wenv-is-wenv $name) {
        let answer = (input $"wenv '($name)' already exists. overwrite? [yN] ")
        if ($answer !~ '^[yY]') { return }
        rm -f $"($env.WENV_CFG)/nu-wenvs/($name).nu"
    }

    let wenv_dir = ($dir | default (pwd))
    let template = if ($init | is-not-empty) {
        $"($env.WENV_CFG)/nu-wenvs/($init).nu"
    } else {
        $"($env.WENV_CFG)/template.nu"
    }

    let wenv_file = $"($env.WENV_CFG)/nu-wenvs/($name).nu"
    let parent = ($wenv_file | path dirname)
    if not ($parent | path exists) {
        mkdir $parent
    }

    open $template
    | str replace --regex 'WENV_DIR = .*' $'WENV_DIR = "($wenv_dir)"'
    | save -f $wenv_file

    wenv edit $name
}

# Generate source script for a wenv. Since nushell can't dynamically source
# files at runtime, this writes the script and prints the command to run.
export def --env "wenv source" [
    name?: string@wenv-complete-names
    --cd (-c)
] {
    let wenv = ($name | default ($env | get -o WENV | default ""))
    if ($wenv | is-empty) {
        error make { msg: "no wenv arg provided and $env.WENV is empty" }
    }
    if not (wenv-is-wenv $wenv) {
        error make { msg: $"wenv '($wenv)' doesn't exist" }
    }

    let script = (wenv-generate-source-script $wenv)
    let script_with_cd = if $cd {
        let config = (wenv-load-vars $wenv)
        $"cd ($config.dir)\n($script)"
    } else {
        $script
    }

    $script_with_cd | save -f ~/.config/wenv/_source.nu

    # Set env vars that don't require source (these take effect immediately)
    let config = (wenv-load-vars $wenv)
    $env.WENV = $wenv
    $env.WENV_DIR = $config.dir
    $env.WENV_DEPS = $config.deps
    $env.WENV_EXTENSIONS = $config.extensions

    print "source ~/.config/wenv/_source.nu"
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
            tmux new-session -d -s $wenv /opt/homebrew/bin/nu --login --config ~/.config/nushell/config.nu --env-config ~/.config/nushell/env.nu

            mkdir /tmp/wenv
            let tmp_name = ($wenv | str replace --all "/" "-")
            let tmp_start = $"/tmp/wenv/start-($tmp_name).nu"

            let script = if $no_init {
                wenv-generate-source-script $wenv
            } else {
                wenv-generate-source-script $wenv --startup
            }
            $script | save -f $tmp_start

            # Send source command to the tmux pane (space prefix to avoid history)
            tmux send -t $wenv $" source ($tmp_start)" ENTER

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
        do { shutdown_wenv }
    }

    # Clear source script so new panes don't load the stopped wenv
    "# no active wenv\n" | save -f ~/.config/wenv/_source.nu
}

export def "wenv bootstrap" [name: string@wenv-complete-names] {
    if not (wenv-is-wenv $name) {
        error make { msg: $"wenv '($name)' doesn't exist" }
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
            error make { msg: $"'($ext)' not found in ($env.WENV_EXT)" }
        }
        $lines = ($lines | append $"source ($file)")
    }
    $lines | str join "\n" | save -f ~/.config/wenv/_source.nu
    print "source ~/.config/wenv/_source.nu"
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
            error make { msg: $"Extension '($ext)' does not exist" }
        }
        if $force { rm -f $file } else { rm $file }
    }
}
