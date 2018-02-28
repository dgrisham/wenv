_wenv_comp() {
    COMPREPLY=( $(compgen -W "$1" -- ${word}) )
    if [[ ${#COMPREPLY[@]} == 1 && ${COMPREPLY[0]} == "--"*"=" ]] ; then
        # If there's only one option, with =, then discard space
        complete -o nospace
    fi
}

_show_aliases() {
    ls "$ALIASES" | sed 's/_aliases//g'
}

_wenv_start() {
    _show_aliases
}

_wenv_cd() {
    _show_aliases
}

_wenv_remove() {
    _show_aliases
}

_wenv_edit() {
    _show_aliases
}

_wenv_rename() {
    _show_aliases
}

_wenv_mv() {
    _wenv_rename
}

_wenv_exec() {
    if [[ $word == -* ]] ; then
        _wenv_comp "-c -n"
    else
        _show_aliases
    fi
}

_wenv_task() {
    _wenv_comp "show add"
}

_wenv_task_add() {
    if [[ ${prev} == "-w" ]] ; then
        _show_aliases
    elif [[ ${word} == -* ]] ; then
        _wenv_comp "-w"
    fi
}

_wenv_task_show() {
    if [[ ${prev} == "-w" ]] ; then
        _show_aliases
    elif [[ ${word} == -* ]] ; then
        _wenv_comp "-w"
    fi
}

_wenv_new() {
    if [[ ${prev} == "-i" ]] ; then
        _show_aliases
    elif [[ ${word} == -* ]] ; then
        _wenv_comp "-i -d"
    fi
}

_wenv() {
    COMPREPLY=()
    complete +o default # Disable default to not deny completion, see: http://stackoverflow.com/a/19062943/1216348

    local word="${COMP_WORDS[COMP_CWORD]}"
    local prev="${COMP_WORDS[COMP_CWORD-1]}"

    case "${COMP_CWORD}" in
        1)
            local opts="start stop reset task cd new edit rm remove \
                        source_aliases exec mv"
            COMPREPLY=( $(compgen -W "${opts}" -- ${word}) );;
        2)
            local command="${COMP_WORDS[1]}"
            eval "_wenv_$command" 2> /dev/null ;;
        *)
            local command="${COMP_WORDS[1]}"
            local subcommand="${COMP_WORDS[2]}"
            eval "_wenv_${command}_${subcommand}" 2> /dev/null && return
            eval "_wenv_$command" 2> /dev/null ;;
    esac
}
complete -F _wenv wenv
