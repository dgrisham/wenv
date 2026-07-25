# edit — named file access via $env.wenv_files
# Usage: edit <key> [<key> ...] — opens files in $EDITOR

def wenv-edit [
    ...keys: string
    --rename (-r)  # rename tmux window to first key
] {
    if ($keys | is-empty) { return }

    let files = ($keys | each {|key|
        let file_map = ($env | get -o wenv_files | default {})
        if ($key in $file_map) {
            let file = ($file_map | get $key)
            if ($file | str starts-with "/") {
                $file
            } else {
                $"($env.WENV_DIR)/($file)" | path expand
            }
        } else {
            error make { msg: $"no entry '($key)'" }
        }
    })

    if $rename {
        tmux rename-window ($keys | first)
    }
    run-external $env.EDITOR ...$files
}
