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
approach. For example, developing the aforementioned IPTB project required a
running Docker daemon. I didn't want Docker to run unless I was working on the
project, but I didn't want to have to think about starting processes like that
when I was about to work. So, I thought it'd be nice if I could include something
in the IPTB project file that would let me automatically run commands like `sudo
systemctl start docker` when I started working on the project and `sudo
systemctl stop docker` when I was finished.

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

    .. code-block:: bash

        mkdir -p "${XDG_CONFIG_HOME:-$HOME/.config}/wenv/wenvs"
        cp template "${XDG_CONFIG_HOME:-$HOME/.config}/wenv

4.  In order for wenvs to work with `tmux`, the following line should be added
    to your `zshrc`:

    .. code-block:: bash

        eval "$WENV_EXEC"

    This makes it so that the wenv associated with a given tmux session can be
    loaded whenever a new pane or window is opened within that session.
5.  Put the `completion.bash` file wherever you like, and add the following
    lines to source it in your Zsh profile (or another Zsh startup file):

    .. code-block:: bash

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

TODO: **need to explain tmux keybindings**

A given project's wenv has two primary parts: a wenv definition, and any shell
aliases/functions that are specific to the project. Let's start by creating a
new directory for our wenv, then initializing the wenv in that directory.

TODO: better to start wenv here then continue example from there?

.. code-block:: bash

    $ cd ~
    $ mkdir hello-world
    $ cd hello-world
    $ wenv new -d hello-world

Running this command will copy the wenv `template` file into a new wenv file
called `hello-world`. The template file provides a base structure for a new
wenv.

Let's look at the new wenv file that was just created. Notice the first function,
`wenv_def()`:

.. code-block:: bash

    wenv_def() {
        WENV_DIR="/home/grish/hello-world"
        WENV_DEPS=()
        WENV_PROJECT=''
        WENV_TASK=''

        startup_wenv() {}
        bootstrap_wenv() {}
        shutdown_wenv() {}
    }

This function defines all of the parameters that the wenv framework can use to
help us work on a project. Let's focus on `WENV_DIR` for now.

`WENV_DIR` (and `c()`/`wenv_dirs`)
++++++++++++++++++++++++++++++++++

Note that `WENV_DIR`'s value was automatically populated with our current
working directory. That's because we passed the `-d` flag to `wenv new` -- if
we hadn't, the value would just be an empty string.

The `WENV_DIR` variable has a few purposes. One is via the `wenv cd` command,
which is used to change into a given wenv's directory. When run without an
argument, this command will `cd` into the base directory of the active wenv.
So, in our case, running `wenv cd` would `cd` into `"~/hello-world". This
allows us to navigate to anywhere in the filesystem and always have a way to get
back to the base directory of our project. Further, if we wanted to browse to the
base directory of the `hello-world` wenv when it wasn't active, we could do so
by running `wenv cd hello-world`.

Another use of the `$WENV_DIR` value is within your wenv-specific variables and
functions. For example, take a look at the line that declares an associative
array called `wenv_dirs`, and also notice the provided `c()` function a few
lines below that. The `c()` function accepts any argument that is a key in
wenv_dirs and `cd`'s into the corresponding value. So, if `wenv_dirs` is
defined like so:

.. code-block:: bash

    declare -Ag wenv_dirs=(
        ['src']="$WENV_DIR/src"
    )

Then running `c src` will change to the `"$WENV_DIR/src"` directory. This is
meant to provide a shortcut for `cd`'ing into directories related to the project
other than `$WENV_DIR`. We can also, of course, add entries for directories
outside of the wenv:

.. code-block:: bash

    declare -Ag wenv_dirs=(
        ['src']="$WENV_DIR/src"
        ['http']="/srv/http"
    )

`c()` also comes with a predefined completion function for the keys of
`wenv_dirs`, so you can tab-complete all possible inputs (in this case, `src`
and `http`).

`edit()` and `wenv_files`
+++++++++++++++++++++++++

`c()` and `wenv_dirs` are meant to provide a convenient interface for nimbly
navigating frequently visited directories. `edit()` and `wenv_files` accomplish
a similar goal, but with opening sets of files in your text editor. For example,
if we had a `main.cpp` file that we wanted to open by running `edit main`, we'd
add the following entry to `wenv_files`:

.. code-block:: bash

    declare -Ag wenv_files=(
        ['main']='main.cpp'
    )

By default, the `edit()` function opens files from the project directory, so we
specify `main.cpp` instead of `"$WENV_DIR/main.cpp"`. We can also use
Zsh globs/expansions/etc., provided we enclose such entries with single-quotes:

.. code-block:: bash

    declare -Ag wenv_files=(
        ['main']='main.cpp'
        ['class']='class.{cpp,h}' # open the header and impl files for `class`
        ['cpp']='*.cpp' # open all cpp files
        ['cpp']='$(echo src/* | xargs -n1 | sort -r)' # open all files in `src`,
                                                      # sorted in reverse order
    )

Note that `edit()` expects your editor to be specified in the `EDITOR`
environment variable.

`startup_wenv()`
++++++++++++++++

Now let's talk about starting a wenv. The `startup_wenv()` function is run
whenever you activate a wenv with `wenv start <wenv>`. This can be useful for
running startup commands, e.g.

.. code-block:: bash

    startup_wenv() {
        sudo systemctl start docker
    }

Or opening programs like text editors:

.. code-block:: bash

    startup_wenv() {
        $EDITOR main.cpp
    }

Additionally, the utility function `wenv_tmux_split` can be used to define an
initial tmux layout for the project. `wenv_tmux_split` will create a new tmux
pane or window and load the active wenv's environment in the new pane/window. It
accepts two arguments:

1.  `h`, `v`, or `c` to specify whether to open a horizontal pane, vertical
    pane, or new window, resp.
2.  (Optional) The command to run in the newly opened pane/window.

So, we can start our wenv with a horizontal split with the startup function:

.. code-block:: bash

    startup_wenv() {
        wenv_tmux_split h
    }

We can also open a file in our text editor in the new pane:

.. code-block:: bash

    startup_wenv() {
        wenv_tmux_split h "$EDITOR main.cpp"
    }

Other tmux commands can be useful in specifying a layout as well. For example, if
we wanted to create a small vertical pane under the initial pane, show the
current active Taskwarrior task, then refocus on the larger pane:

.. code-block:: bash

    startup_wenv() {
        wenv_tmux_split v
        tmux resize-pane -y 7
        task active
        tmux select-pane -U
    }

Speaking of Taskwarrior...

`WENV_PROJECT` and `WENV_TASK`
++++++++++++++++++++++++++++++

# TODO

Summary
+++++++

**Variables**

-  `WENV_DIR`: The path to the base directory of this project.
-  `WENV_DEPS`: An array whose elements are the names of the wenvs that this
   wenv is dependent on.
-  `WENV_PROJECT`: The value to use for the task's `project` attribute in
   Taskwarrior.
-  `WENV_TASK`: The wenv's current primary task number.

**Functions**

-  `startup_wenv()` is run whenever you start the wenv. This function is good
    for starting up any necessary daemons, setting up a tmux layout, opening
    programs (e.g. a text editor), etc.
-  `shutdown_wenv()` is run when you stop the wenv. This can be used to stop
    daemons started by `startup_wenv()`, and do any other cleanup.
-   `bootstrap_wenv()` sets up the environment that the wenv expects to exist.
    For example, this function might pull down a git repository for development
    or check to ensure that all packages required by this wenv are installed.
    You can run this function on a wenv `<wenv>` by running
    `wenv bootstrap <wenv>`.

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

    Run `wenv <cmd> -h` for more information on a given subcommand <cmd>.

