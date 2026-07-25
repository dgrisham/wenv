$env.WENV_DIR = ""
$env.WENV_DEPS = []
$env.WENV_EXTENSIONS = ['wd']

def startup_wenv [] {}
def shutdown_wenv [] {}
def bootstrap_wenv [] {}

if ($env | get -o only_load_wenv_vars | default false) { return }

# --- aliases, functions, env vars below ---
