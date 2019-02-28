WENV -- A Simple **W**orking **Env**ironment Framework
======================================================

Perpetual WIP, likely to have bugs.

## Introduction

Working environments (WENVs) are a tool for streamlining workflow in the
terminal. A WENV for a given project defines 1. what commands should be run to
start the project, and 2. the project-specific environment that should be
loaded.

TODO: make a note that tmux is not required, but it does provide a lot of the
useful functionality

### Example

A given project's WENV is defined by `zsh` functions and environment variables.
As an example,

TODO: oH SHIT the `wenv` WENV is dependent on the `x` wenv.

TODO: gif webm movie thing

## Installation

Clone this repository (TODO: deal with the $SRC thing, that should change)

The environment variable `WENVS` is used to specify the directory where all
projects' WENV files are stored. Create the directory and define the `WENVS`
variable in your `zsh` profile.

If you want the name of the active WENV to be prepended to your prompt, add
the following lines to your `.zshrc`

    ```
    eval ZSH_INIT
    ORIGINAL_PS1="$PS1"
    ```

TODO: example of this happening

In order to run WENVs in `tmux` sessions (which is the intended use), the
following command should be run whenever a new pane or window is opened:
`"#{pane_current_path}" 'ZSH_INIT="unset WENV; wenv exec -c "$WENV"" zsh -i'`.
So, for example, your `tmux.conf` should have lines that look like:

    ```
    ## set window split
    bind-key - split-window -c "#{pane_current_path}" 'ZSH_INIT="unset WENV; wenv exec -c \"$WENV\"" zsh -i'
    bind-key \ split-window -h -c "#{pane_current_path}" 'ZSH_INIT="unset WENV; wenv exec -c \"$WENV\"" zsh -i'
    ## set window creation
    bind-key c new-window -c "#{pane_current_path}" 'ZSH_INIT="unset WENV; wenv exec -c \"$WENV\"" zsh -i'
    ```

These will make it so that every pane and window in a given `tmux` session
associated with a WENV will load that WENV.

### dependencies (optional or not)

-   taskwarrior (currently required)

## Commands


