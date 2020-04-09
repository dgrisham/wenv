_wenv_comp() {
    COMPREPLY=( $(compgen -W "$1" -- ${word}) )
    if [[ ${#COMPREPLY[@]} == 1 && ${COMPREPLY[0]} == "--"*"=" ]]; then
        # If there's only one option, with =, then discard space
        complete -o nospace
    fi
}

_show_wenvs() {
    find "$WENV_CFG/wenvs" ! -type d -exec basename {} \;
}

_wenv_start() {
    if [[ $word == -* ]]; then
        _wenv_comp "-t -q -i -d -h"
    else
        _show_wenvs
    fi
}

_wenv_stop() {
    _wenv_comp "-s -h"
}

_wenv_cd() {
    if [[ $word == -* ]]; then
        _wenv_comp "-r -h"
    else
        _show_wenvs
    fi
}

_wenv_new() {
    if [[ ${prev} == "-i" ]]; then
        _show_wenvs
    elif [[ ${word} == -* ]]; then
        _wenv_comp "-i -d -h"
    fi
}

_wenv_task() {
    if [[ $word == -* ]]; then
        _wenv_comp "-h"
    else
        _wenv_comp "show add"
    fi
}

_wenv_task_add() {
    if [[ ${prev} == "-w" ]]; then
        _show_wenvs
    elif [[ ${word} == -* ]]; then
        _wenv_comp "-w -h"
    fi
}

_wenv_task_show() {
    if [[ ${prev} == "-w" ]]; then
        _show_wenvs
    elif [[ ${word} == -* ]]; then
        _wenv_comp "-w -h"
    fi
}

_wenv_edit() {
    _show_wenvs
}

_wenv_rm() {
    _wenv_remove
}

_wenv_remove() {
    if [[ $word == -* ]]; then
        _wenv_comp "-h"
    else
        _show_wenvs
    fi
}

_wenv_rename() {
    if [[ $word == -* ]]; then
        _wenv_comp "-h"
    else
        _show_wenvs
    fi
}

_wenv_mv() {
    _wenv_rename
}

_wenv_source() {
    if [[ $word == -* ]]; then
        _wenv_comp "-h"
    else
        _wenv_comp "load edit"
    fi
}

_wenv_extension() {
    if [[ $word == -* ]]; then
        _wenv_comp "-h"
    else
        _wenv_comp "load open remove"
    fi
}

_wenv_extension_load() {
    if [[ $word == -* ]]; then
        _wenv_comp "-h"
    else
        ls "$WENV_CFG/extensions"
    fi
}

_wenv_extension_open() {
    if [[ $word == -* ]]; then
        _wenv_comp "-h"
    else
        ls "$WENV_CFG/extensions"
    fi
}

_wenv_extension_remove() {
    if [[ $word == -* ]]; then
        _wenv_comp "-h"
    else
        ls "$WENV_CFG/extensions"
    fi
}

_wenv_bootstrap() {
    if [[ $word == -* ]]; then
        _wenv_comp "-h"
    else
        _show_wenvs
    fi
}

_wenv_exec() {
    if [[ $word == -* ]]; then
        _wenv_comp "-c -n -h"
    else
        _show_wenvs
    fi
}

_wenv() {
    COMPREPLY=()
    complete +o default # Disable default to not deny completion, see: http://stackoverflow.com/a/19062943/1216348

    local word="${COMP_WORDS[COMP_CWORD]}"
    local prev="${COMP_WORDS[COMP_CWORD-1]}"

    case "${COMP_CWORD}" in
        1)
            if [[ $word == -* ]]; then
                _wenv_comp '-h'
            else
                local opts="start stop cd new task edit rm mv source extension bootstrap exec"
                COMPREPLY=( $(compgen -W "${opts}" -- ${word}) )
            fi
            ;;
        2)
            local command="${COMP_WORDS[1]}"
            eval "_wenv_$command" 2> /dev/null
            ;;
        *)
            local command="${COMP_WORDS[1]}"
            local subcommand="${COMP_WORDS[2]}"
            eval "_wenv_${command}_${subcommand}" 2> /dev/null && return
            eval "_wenv_$command" 2> /dev/null
            ;;
    esac
}
complete -F _wenv wenv
