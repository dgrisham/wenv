# notes — per-wenv notes directory
# Should be loaded after the edit extension

$env.NOTES_DIR = $"($env.SCRATCH)/notes/($env | get -o WENV | default 'scratch')"
mkdir $env.NOTES_DIR

def active-notes [] {
    $"($env.NOTES_DIR)/notes.md"
}

# Add notes to wenv_files if defined
let files = ($env | get -o wenv_files | default {})
$env.wenv_files = ($files | merge { notes: (active-notes) })
