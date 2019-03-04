.. default-role:: literal

WENV -- A Simple Working Environment Framework
==============================================

Perpetual WIP, likely to have bugs.

**Note**: This README is unfinished.

Introduction
------------

Working environments (WENVs) are a tool for streamlining workflow in the
terminal. A WENV for a given project defines 1. what commands should be run to
start (and end) the project, and 2. the project-specific environment that should
be loaded. The WENV framework is a set of functions that help manage projects'
WENVs and use their environment information to provide other useful
functionality, like showing a todo list for a project.

Much of the reason I started working on WENVs was the result of taking the advice
in `this answer on Stack Overflow
<https://stackoverflow.com/a/5752901/4516052>`_, which recommends running a
sequence of tmux commands as a function that starts your desired development
environment. However, as I worked on projects, I found that I'd want different
tmux layouts depending on the project. But I wanted more than just a tmux layout
-- I also wanted to automatically run project-specific commands in certain
terminals when opening a layout. This would require a bit more work than the
shell function the SO post.

At the same time, I had a simple system set up for managing aliases for different
projects. Basically, I had a folder that contained projects' individual alias
files. Those files contained whatever Zsh environment variables/functions I
wanted to have defined for that project. This avoids putting a bunch of temporary
or highly-specific aliases in my general Zsh aliases file, which I'd rather be
accessible and general enough for people who might want to look at it. Then I
just wrote a few Zsh commands that would let me easily create, edit, and source
alias files.

Eventually, I decided to integrate a solution to my varied-tmux-startup conundrum
with the project alias files. That way, the entire definition for a project (both
its layout and its Zsh variables/functions) could be defined in one place. It
turned out to be much more involved than I expected, though. One of the big
reasons for this had to do with sourcing the project's alias in every pane/window
of the tmux session. This requires maintaining enough state in tmux to know which
aliases file to source, then running the proper commands to do so when a new pane
or window opens.

Other useful features also quickly became apparent to me as I started working on
this. For example, let's say I have a project that requires a running Docker
daemon. I'd prefer for Docker to only run while I'm working on the project, but I
don't really want to have to think about starting processes like that when I'm
about to work. So, I thought it'd be nice to include something in the project
file that automatically runs commands like `sudo systemctl start docker` when I
start working on the project and `sudo systemctl stop docker` when I'm done.

Another feature I quickly realized would be useful was the ability to wrap
`Taskwarrior <https://taskwarrior.org/>`_ commands to show only the tasks
associated with the active project. Taskwarrior is a great tool, but I don't want
to have to type out and think about a project's name every time I want to add or
show its tasks. I'd rather have commands that mean "show me the tasks associated
with the project I'm working on" and "add a task for the active project with this
description".

The WENV framework arose from this increasing complexity. However, it never left
the realm of Zsh scripting. A project's WENV is defined by Zsh environment
variables and functions, and the WENV 'framework' is just a bunch of Zsh
functions. This is convenient because many of the functions are just sequences of
commands I'd like to run in the terminal anyway, and the rest are maintaining
state in a way that shells are good at.

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

    ::

        eval "$WENV_EXEC"


    This makes it so that the WENV associated with a given tmux session can be
    loaded whenever a new pane or window is opened within that session.
5.  Put the `completion.bash` file wherever you like, and source it in one of
    your Zsh startup files. For example, you can add the following lines to your
    Zsh profile:

    ::

        autoload bashcompinit
        bashcompinit
        source <path-to-completion.bash>

The environment variable `WENVS` is used to specify the directory where all
projects' WENV files are stored. This can be overriden by setting the `WENVS`
value in your Zsh profile. `WENVS` will default to
`"${XDG_CONFIG_HOME}/wenv/wenvs` if `XDG_CONFIG_HOME` is set; otherwise, it's
set to `$HOME/.config/wenv/wenvs`.

dependencies
~~~~~~~~~~~~

-   Zsh
-   tmux
-   taskwarrior

Usage
~~~~~

**TODO: output usage from wenv functions themselves**

