# wd — named directory access via $env.wenv_dirs
# Usage: wd <key> — outputs the directory path
#        c <key>  — cd into the directory

export def wenv-complete-dirs [] {
    $env | get -o wenv_dirs | default {} | columns | each { |k| { value: $k, description: "" } }
}

export def wd [key?: string@wenv-complete-dirs] {
    if ($key | is-empty) {
        $env.WENV_DIR
    } else {
        let dirs = ($env | get -o wenv_dirs | default {})
        if ($key in $dirs) {
            let dir = ($dirs | get $key)
            if ($dir | str starts-with "/") or ($dir | str starts-with "~") {
                $dir | path expand
            } else {
                $"($env.WENV_DIR)/($dir)" | path expand
            }
        } else {
            error make { msg: $"no entry '($key)'" }
        }
    }
}

export def --env c [key?: string@wenv-complete-dirs] {
    let dir = (wd $key)
    cd $dir
}
