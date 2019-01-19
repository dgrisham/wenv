WENV -- A Simple Working Environment Framework
==============================================

Perpetual WIP, likely to have bugs. Needs documentation.

Requirements:

-   Add to `.zshrc`.
    -   `eval ZSH_INIT`
    -   `ORIGINAL_PS1="$PS1"`
-   Add to `tmux.conf`

    ## set window split
    bind-key - split-window -c "#{pane_current_path}" 'ZSH_INIT="unset WENV; wenv exec -c \"$WENV\"" zsh -i'
    bind-key \ split-window -h -c "#{pane_current_path}" 'ZSH_INIT="unset WENV; wenv exec -c \"$WENV\"" zsh -i'
    ## set window creation
    bind-key c new-window -c "#{pane_current_path}" 'ZSH_INIT="unset WENV; wenv exec -c \"$WENV\"" zsh -i'
