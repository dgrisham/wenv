# git-worktree — manage git worktrees with wenv_dirs integration

def add-worktree [...patterns: string] {
    for pattern in $patterns {
        let branches = (git branch --format='%(refname:short)' --list $pattern | lines)
        for b in $branches {
            let worktree_dir = $"($env.GIT_WORKTREES)/($b)"
            git worktree add $worktree_dir $b
            let dirs = ($env | get -o wenv_dirs | default {})
            $env.wenv_dirs = ($dirs | merge { $"worktree/($b)": $worktree_dir })
        }
    }
}

def remove-worktree [...patterns: string] {
    for pattern in $patterns {
        let worktrees = (git worktree list | lines | each { split row " " | first } | where { str contains $"($env.GIT_WORKTREES)/($pattern)" })
        for worktree_dir in $worktrees {
            let branch = ($worktree_dir | str replace $"($env.GIT_WORKTREES)/" "")
            let answer = (input $"remove worktree '($branch)'? [yN] ")
            if ($answer =~ '^[yY]') {
                git worktree remove --force $worktree_dir
                let dirs = ($env | get -o wenv_dirs | default {})
                $env.wenv_dirs = ($dirs | reject $"worktree/($branch)")
            }
        }
    }
    git worktree prune
}

def add-worktrees-to-wenv-dirs [] {
    let worktrees = (git worktree list | lines | each { split row " " | first } | where { str contains $env.GIT_WORKTREES })
    mut dirs = ($env | get -o wenv_dirs | default {})
    for worktree_dir in $worktrees {
        let branch = ($worktree_dir | str replace $"($env.GIT_WORKTREES)/" "")
        $dirs = ($dirs | merge { $"worktree/($branch)": $worktree_dir })
    }
    $env.wenv_dirs = $dirs
}
