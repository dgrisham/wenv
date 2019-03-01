WENV -- A Simple Working Environment Framework
==============================================

Perpetual WIP, likely to have bugs.

Introduction
------------

Working environments (WENVs) are a tool for streamlining workflow in the
terminal. A WENV for a given project defines 1. what commands should be run to
start the project, and 2. the project-specific environment that should be
loaded.

Currently, WENVs required Zsh as the primary shell. They are also most useful
with tmux, though some of the functionality can be used without tmux.

**Note**: This framework was written on the fly to implement the features I
(@dgrisham) wanted while working on projects. I did not research many solutions
to this (aside from trying
[`tmux-resurrect`](https://github.com/tmux-plugins/tmux-resurrect) for a short
time), and as such I do not have the experience or knowledge to compare it to
existing tools.

Example
~~~~~~~

A given project's WENV is defined by `zsh` functions and environment variables.
As an example,

TODO: gif webm movie thing

Installation
------------

For now, the installation is manual -- fortunately, it's also relatively
painless. The following steps (or variations on them) should get the job done:

1.  Clone this repository.
2.  Put the `wenv` file in a directory that's in your `PATH` (e.g.
    `$HOME/.local/bin`). `wenv` is a Zsh script that defines all of the relevant
     functionality.
3.  Make sure the directory `$XDG_CONFIG_HOME/wenv` (or `$HOME/.config/wenv`)
    exists, and put the `template` file there.
4.  In order for WENVs to work with `tmux`, the following line should be added
    to your `zshrc`:

    ```
    eval "$WENV_EXEC"
    ```

    This makes it so that the WENV associated with a given tmux session can be
    loaded whenever a new pane or window is opened within that session.
5.  Put the `completion.bash` file wherever you like, and source it in one of
    your Zsh startup files. For example, you can add the following lines to your
    Zsh profile:

    ```
    autoload bashcompinit
    bashcompinit
    source <path-to-completion.bash>
    ```

The environment variable `WENVS` is used to specify the directory where all
projects' WENV files are stored. This can be overriden by setting the `WENVS`
value in your Zsh profile. `WENVS` will default to
`"${XDG_CONFIG_HOME}/wenv/wenvs` if `XDG_CONFIG_HOME` is set; otherwise, it's
set to`$HOME/.config/wenv/wenvs`.

dependencies (optional or not)
~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~

-   taskwarrior (currently required)

Usage
~~~~~

**TODO: output usage from wenv functions themselves**

