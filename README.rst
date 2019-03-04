.. default-role:: literal

wenv: A Shell Workflow Tool
===========================

Perpetual WIP, likely to have bugs.

**Note**: This README is currently in development.

Introduction
------------

The working environment (wenv) framework is a tool for streamlining workflow in
the terminal. A wenv is associated with a single project and defines 1. its wenv
definition, which the wenv framework uses to make working on the project easier,
and 2. useful shell functionality specific to the project.

My (@dgrisham's) motivation for this project came from a desire to make working
in the terminal clean, easy, and fun. Zsh and tmux were ubiquitous in my
workflow, and over time I started to see potential in those tools that I wanted
to take advantage of. The wenv framework emerged from this potential. The actual
conception of this project formed as I tried to solve relatively disparate
problems. I'll start by describing some of those problems, then how they came
together to shape a single solution.

One of the issues I faced had to do with starting tmux with a given layout. Every
time I started to work, I'd have to go through the steps of setting up the
appropriate layout of panes and opening the relevant programs in those panes.
This seemed silly, given that I was working in the terminal and should be able to
automate such things. I saw advice like `this answer on Stack Overflow
<https://stackoverflow.com/a/5752901/4516052>`_, which recommends running a
sequence of tmux commands as a function that starts your desired development
environment. However, as I worked on projects, I found that I'd want different
tmux layouts depending on the project. Further, I wanted more than just a tmux
layout -- I also wanted to automatically run project-specific commands in certain
terminals in a given layout. This would require a bit more work than the shell
function the SO post.

At the same time, I'd set up a simple system for managing aliases with different
domains. For example, I had a Python aliases file that defined useful functions
for Python development (mainly creating and starting virtual environments). I
also wrote alias files specific to certain projects, e.g. the `IPTB
<https://github.com/ipfs/iptb>`_ development aliases defined the required
`IPTB_ROOT` environment variable and additional functions to simplify IPTB and
Docker startup, shutdown, and cleanup. Then I just had a few Zsh commands that
would let me easily create, edit, and source these alias files. Organizing
aliases in this way avoids putting a bunch of temporary or overly-specific
aliases in my general Zsh aliases file, which I'd rather be accessible and
general enough for people who might want to draw from it.

Eventually, I decided to integrate a solution to my varied-tmux-startup conundrum
with the alias files. That way, the entire definition for a project (both its
layout and its Zsh variables/functions) could exist in one place. This approach
also presented the possibility of having a project's aliases defined in every
tmux pane/window in a given session, which would

1.  be much nicer than having to manually source the aliases in every pane that
    I needed them, while
2.  maintaining a clean Zsh namespace by restricting the project's aliases to a
    single tmux session.

This emerging idea turned out to be more involved than I'd expected. Sourcing a
given aliases file in every pane of a tmux session required work on both the Zsh
end (to tell tmux which aliases file to source) and the tmux end (to actually
source the aliases in each pane).

Other useful features also quickly became apparent as I started working on this
approach. For example, the IPTB project I mentioned required a running Docker
daemon. I didn't want Docker to run unless I was working on the project, but I
didn't want to have to think about starting processes like that when I was about
to work. So, I thought it'd be nice if I could include something in the IPTB
project file that would let me automatically run commands like `sudo systemctl
start docker` when I started working on the project and `sudo systemctl stop
docker` when I was finished.

Another potential feature that came to mind was the ability to wrap `Taskwarrior
<https://taskwarrior.org/>`_ commands to show only the tasks associated with the
active project. Taskwarrior is a great tool, but I don't want to have to type out
and think about a project's name every time I want to add or show its tasks. I'd
rather have commands that mean "show me the tasks associated with the project I'm
working on" and "add a task for the active project with this description".

The wenv framework arose from this increasing complexity. However, it never left
the realm of Zsh scripting. A project's wenv is defined by Zsh environment
variables and functions, and the wenv 'framework' is just a bunch of Zsh
functions. This is convenient because much of the code is just sequences of
commands I'd run in the terminal anyway, and the rest maintain state in the Zsh
and tmux environments.

Installation
------------

For now, the installation is manual -- fortunately, it's also relatively
painless. The following steps (or variations on them) should get the job done:

1.  Clone this repository.
2.  Put the `wenv` file in a directory that's in your `PATH` (e.g.
    `$HOME/.local/bin`). `wenv` is a Zsh script that defines all of the
    relevant functionality.
3.  Create the directory `$XDG_CONFIG_HOME/wenv` (or `$HOME/.config/wenv`) and
    put the `template` file there. Also, create a directory inside of that
    `wenv` directory called `wenvs`, which will store the wenv files for all of
    your projects. If you're in this repository, you can run the following lines
    to complete this step:

    ::

        mkdir -p "${XDG_CONFIG_HOME:-$HOME/.config}/wenv/wenvs"
        cp template "${XDG_CONFIG_HOME:-$HOME/.config}/wenv

4.  In order for wenvs to work with `tmux`, the following line should be added
    to your `zshrc`:

    ::

        eval "$WENV_EXEC"

    This makes it so that the wenv associated with a given tmux session can be
    loaded whenever a new pane or window is opened within that session.
5.  Put the `completion.bash` file wherever you like, and add the following
    lines to source it in your Zsh profile (or another Zsh startup file):

    ::

        # enable bash completion functions
        autoload bashcompinit
        bashcompinit
        # source wenv completion file
        source <path-to-completion.bash>

dependencies
~~~~~~~~~~~~

-   Zsh
-   tmux
-   taskwarrior

Example
~~~~~~~

A given project's wenv is defined by `zsh` functions and environment variables.
As an example,

TODO: gif webm movie thing

Usage
~~~~~

::

    USAGE
      wenv [-h] <cmd> ...

    OPTIONS
      -h                    Display this help message.

    SUBCOMMANDS
      start <wenv>          Start the working environment <wenv>.
      stop                  Stop the current working environment.
      new                   Create a new working environment.
      edit <wenv>           Edit the wenv file for <wenv>.
      rename <old> <new>    Rename wenv <old> to <new>.
      remove <wenv>         Delete the wenv file for <wenv>.
      source <wenv>         Source <wenv>'s environment (excluding its wenv_def).
      cd <wenv>             Change to <wenv>'s base directory.
      task <cmd>            Access the project task list.
      bootstrap <wenv>      Run <wenv>'s bootstrap function.

    Run `wenv <cmd> --help` for more information on a given subcommand <cmd>.

