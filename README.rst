.. default-role:: literal
.. sectnum::

wenv: A Shell Workflow Tool
===========================

.. contents:: Table of Contents

Introduction
------------

Working in the terminal is fun, but it can also be tedious and messy. The working
environment (wenv) project offloads the tedious work required to provide clean,
project-specific environments that allow users to easily leverage the power of
their shell. It acts as an extremely lightweight layer that connects tmux, Zsh,
and your other favorite shell tools.

The Story
~~~~~~~~~

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

The advantages that stem from this tool being 'lightweight' go beyond the usual
ideas of load time/etc. The art of shell scripting is slowly being lost to more
integrated and high-level tools. While those tools definitely have their place,
there are disadvantages to the lower resolution [*]_. The lightweight nature of
the wenv project aims to achieve many of the advantages that higher level tools
offer while staying at the level of abstraction of the shell. This means that
wenvs require minimal understand on the user's part beyond shell scripting -- if
you understand how shells work, then you're only a few steps from understanding
how wenvs work. And if you don't understand how shells work, using wenvs can help
you do so.

.. [*] For more on this topic, see the talk `Preventing the Collapse of Civilation
   by Jonathon Blow <https://www.youtube.com/watch?v=pW-SOdj4Kkk>`_.

Installation
------------

For now, the installation is manual -- fortunately, it's also relatively
painless. The following steps (or variations on them) should get the job done
(note that you may want to store this repo somewhere permanent and symlink to
its contents instead of copying to make updates easier):

1.  Clone this repository.
2.  Put the `wenv` file in a directory that's in your `PATH` (e.g.
    `$HOME/.local/bin`). `wenv` is a Zsh script that defines all of the
    relevant functionality.
3.  Create the directory `$XDG_CONFIG_HOME/wenv` (or `$HOME/.config/wenv`) and
    put the `template` file there and `extensions` directory there. Also, create
    a directory inside of that `wenv` directory called `wenvs`, which will store
    the wenv files for all of your projects. If you're in this repository, you
    can run the following lines to complete this step:

    .. code-block:: bash

        export wenv_cfg="${XDG_CONFIG_HOME:-$HOME/.config}/wenv"
        mkdir -p "$wenv_cfg/wenvs"
        ln -s <path-to-this-repo>/{template,extensions} "$wenv_cfg"

4.  In order for wenvs to work with `tmux`, the following line should be added
    to your `zshrc`:

    .. code-block:: bash

        eval "$ZSH_STARTUP_CMD"

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

Dependencies
~~~~~~~~~~~~

-   Zsh
-   tmux
-   Taskwarrior

Usage
-----

::

    USAGE
      wenv [-h] <cmd>

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
      extension <cmd>       Interact with wenv extensions.
      bootstrap <wenv>      Run <wenv>'s bootstrap function.

    Run `wenv <cmd> -h` for more information on a given subcommand <cmd>.

Wenv Environment Summary
~~~~~~~~~~~~~~~~~~~~~~~~

See the Walkthrough_ for further elaboration and examples.

**Variables**

-  `WENV_DIR`: The path to the base directory of this project.
-  `WENV_DEPS`: An array containing the names of the wenvs that this wenv is
   dependent on.
-  `WENV_PROJECT`: The value to use for the task's `project` attribute in
   Taskwarrior.
-  `WENV_TASK`: The wenv's current active task number.
-  `WENV_EXTENSIONS`: An array containing the names of the extensions to load
   for the wenv.

**Functions**

-   `startup_wenv()` is run whenever you start the wenv. This function is good
    for starting up any necessary daemons, setting up a tmux layout, opening
    programs (e.g. a text editor), etc. It will run inside `"$WENV_DIR"`.
-   `shutdown_wenv()` is run when you stop the wenv. This can be used to stop
    daemons started by `startup_wenv()`, and do any other cleanup.
-   `bootstrap_wenv()` sets up the environment that the wenv expects to exist.
    For example, this function might pull down a git repository for development
    or check to ensure that all packages required by this wenv are installed.
    You can run this function on a wenv `<wenv>` by running
    `wenv bootstrap <wenv>`.

Walkthrough
-----------

The utility of wenvs takes a bit of time to explain. This walkthrough gives the
basic configuration/commands for getting started while also explaining what I've
found them to be useful for. If you're experienced with shell scripting, you'll
see that much of the value of wenvs comes from allowing the user to leverage the
tools provided by shells. This project is less focused on forcing a specific
workflow for users and more focused on giving users a convenient environment in
which to define their own workflow unrestricted by the limitations of a single
terminal.

The example wenvs in the `examples`__ directory give concrete examples of wenv
definitions for general projects. Each example includes a comprehensive
description of the wenv's definition and features that are used to create a clean
and useful environment. I recommend going through these examples, as they
compliment this walkthrough.

__ examples/

Creating a wenv
~~~~~~~~~~~~~~~

Here's an example that creates a wenv for a project called 'hello-world':

.. code-block:: bash

    $ mkdir hello-world
    $ cd hello-world
    $ wenv new -d hello-world

The `wenv new` command will copy the wenv `template` file into a new wenv
file called `hello-world`. The template file provides a base structure for a new
wenv. On my machine, the above wenv command creates a new wenv file that starts
with the following function, called `wenv_def()`:

.. code-block:: bash

    wenv_def() {
        WENV_DIR="/home/grish/hello-world"
        WENV_DEPS=()
        WENV_PROJECT=''
        WENV_TASK=''
        WENV_EXTENSIONS=()

        startup_wenv() {}
        bootstrap_wenv() {}
        shutdown_wenv() {}
    }

A given project's wenv has two primary parts: its wenv definition, and any shell
aliases/functions that are specific to the project. A wenv's definition is
represented by its `wenv_def()` function, and the wenv's Zsh aliases/functions
are defined in the same file as its `wenv_def()`. When you initialize a new
wenv, you'll notice that a few Zsh environment variables and functions are

defined by default (more on those in `Predefined Functions`_).

The `wenv_dir()` function defines all of the parameters that the wenv framework
can use to help us work on a project. Let's focus on `WENV_DIR` for now.

`WENV_DIR`
~~~~~~~~~~

The `WENV_DIR` value represents the base directory of the project. When we
start a wenv with e.g. `wenv start hello-world`, we'll automatically `cd` into
the project's `WENV_DIR`. Further, whenever a wenv is active, we can run `wenv
cd` (without an argument) to `cd` into its base directory from anywhere. If we
want to `cd` into an inactive wenv's `WENV_DIR`, we can do so by passing the
wenv name as an argument -- e.g. `wenv cd hello-world`.

In the example in the previous section, `WENV_DIR`'s value was automatically
populated with our current working directory. That's because we passed the `-d`
flag to `wenv new` -- if we hadn't, the value would just be an empty string.

`startup_wenv()`
~~~~~~~~~~~~~~~~

Now let's talk about what you can do when starting a wenv. The `startup_wenv()`
function is run whenever you activate a wenv with `wenv start <wenv>`. This can
be useful for running startup commands, e.g.

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
we wanted to create a small vertical pane under the initial pane, show the active
Taskwarrior task, then refocus on the larger pane:

.. code-block:: bash

    startup_wenv() {
        wenv_tmux_split v
        tmux resize-pane -y 7
        task active
        tmux select-pane -U
    }

Note that `wenv start` will `cd` into `"$WENV_DIR"` before
`startup_wenv()` is run, so you can assume you'll be in the wenv's base
directory when writing your `startup_wenv()` functions. Additionally, your wenv
aliases will be sourced once `startup_wenv()` is called, so can take advantage
of any environment variables/functions defined outside of `wenv_def()`.

`shutdown_wenv()`
~~~~~~~~~~~~~~~~

This is essentially the opposite of `startup_wenv()` -- it runs whenver you
deactivate the current wenv with `wenv stop`. So, if we have a wenv whose
`startup_wenv()` function runs `sudo systemctl start docker`, our
`shutdown_wenv()` might be:

.. code-block:: bash

    shutdown_wenv() {
        sudo systemctl stop docker
    }

Note, however, that the `wenv stop` command doesn't deactivate the wenv if
`shutdown_wenv()` returns a non-zero exit code. You can always pass the `-f`
flag to `wenv stop` to close the wenv even if `shutdown_wenv()` fails.

`WENV_DEPS`
~~~~~~~~~~~

`WENV_DEPS` is an array of wenvs that this wenv is dependent on. Essentially,
every wenv in `WENV_DEPS` is sourced when starting the wenv. Let's take the
example of a wenv for IPTB (which we'll call `iptb`):

.. code-block:: bash

    wenv_def() {
        # ...
    }

    export IPTB_ROOT="$HOME/.iptb"

Let's say we wanted to create another wenv that also used IPTB, and therefore
also needs to set the `IPTB_ROOT` variable. We *could* initialize the new wenv
with the `iptb` wenv as a base using `wenv new -i iptb <new_wenv>`, so our new
wenv would have the same `export` command. However, this approach isn't
particularly maintainable -- e.g. if the IPTB developers decide to rename the
`IPTB_ROOT` variable, all wenvs that use IPTB would have to update that
variable's value. Alternatively, we could just source the `iptb` wenv and get
all of its environment variables every time we start any wenv that uses IPTB. To
do this, we'd add `iptb` to our `WENV_DEPS`:

.. code-block:: bash

    wenv_def() {
        # ...
        WENV_DEPS=('iptb')
    }

Taskwarrior Functionality
~~~~~~~~~~~~~~~~~~~~~~~~~

As mentioned in the introduction, I thought it would be useful to wrap
Taskwarrior commands within wenv commands. This would allow me to reduce mental
overhead of using Taskwarrior. Taskwarrior essentially maintains a global task
list and allows you to interact with subsets based on filters you provide. Since
the wenv environment contains information about the current project, wenv
commands can automatically pass the project name to Taskwarrior. This makes
adding and showing tasks related to the project easier, because you don't have
to type in the project name every time, and less error-prone, since the shell is
filling that field in for you.

Taskwarrior Config
++++++++++++++++++

If you're new to Taskwarrior, the following `taskrc` example should get you
started (there are many Taskwarrior features beyond what's used here):

.. code-block:: bash

    data.location=~/.task

    include /usr/share/doc/task/rc/dark-gray-256.theme

    color.active=black on white
    report.active.columns=id,project,description
    report.active.labels=ID,Project,Description

    report.project.columns=id,description
    report.project.labels=ID,Description
    report.project.filter=(status:pending or status:waiting)

This sets the two task reports used by wenvs: `active` and `project`. The
`active` report is used for showing all active tasks (which you can see by
running `task active`), while the `project` report shows all tasks related to
a given project.

Taskwarrior Wenv Commands
+++++++++++++++++++++++++

As an example, let's say the `hello-world` wenv is active and we want to add a
task for this project with the description 'add new feature'. We'd use the wenv
command:

.. code-block:: bash

    wenv task add 'add new feature'

This would consequently run the following Taskwarrior command:

.. code-block:: bash

    task add project:'hello-world' -- 'add new feature'

Then, if we want to show the tasks associated with the current wenv, we'd run
`wenv task show`. In this case, the output would look something like:

.. code-block:: bash

    $ wenv task show
    hello-world

    ID Description
    82 add new feature

    1 task

Note that simply running `wenv task` defaults to `wenv task show`.

By default, the Taskwarrior `project` attribute is set to the name of the wenv.
To override this with a different value, set `WENV_PROJECT` to the desired
string in `wenv_def()`.

Additionally, the wenv framework can automatically start and stop a project's
active tasks. This is done by filling in the `WENV_TASK` value in
`wenv_def()`. So, if we wanted to set the active task for our `hello-world`
project to our previously created task with `ID` value `82`, we'd set
`WENV_TASK=82`. Then `task start 82` will run the next time you run `wenv
start hello-world`. When you run `wenv stop`, `task stop 82` will run. This
further reduces interaction with Taskwarrior by automatically managing active
tasks based on the current project.

Extensions
~~~~~~~~~~

Wenv extensions define shell code that may be reused across multiple wenvs. A
wenv extension is nothing more than a shell file that you want to source in every
shell of a wenv. Extensions are stored in `"$WENV_CFG/extensions"`. To load an
extension, add its name to the `WENV_EXTENSIONS` array. For example, if we
wanted to load the `c` and `edit` extensions, our `wenv_def()` would look
like:

.. code-block:: bash

    wenv_def() {
        # ...
        WENV_EXTENSIONS=('c' 'edit')
    }

Then the files `"$WENV_CFG/extensions/c"` and `"$WENV_CFG/extensions/edit"`
would be sourced in every shell of our wenv. See the documentation for the `c`
and `edit` wenvs for more information on their usage -- this can easily be done
by running e.g. `wenv extension load c` then `c -h`, which will work
regardless of whether you're in an active wenv.

tmux
~~~~

A wenv that opens in tmux sets a few tmux keybindings for opening new
panes/windows and activating the current wenv in them. By default, these are
bound to:

-   `-`: Split window vertically
-   `\\`: Split window horizontally
-   `c`: New window

These are currently hardcoded in the `wenv_start()` function, so if you want to
change the bindings you'll have to edit that function.
