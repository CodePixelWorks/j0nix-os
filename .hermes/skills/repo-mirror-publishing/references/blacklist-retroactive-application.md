# Blacklist Not Applied to Older Commits

## Problem

Files listed in `.mirror-blacklist` still appeared in older commits of the public mirror.

Example: `nix-bug.txt` was committed long before `.mirror-blacklist` existed. After adding it to the blacklist and running `filter-branch`, the file remained visible in commits predating the blacklist file.

## Root Cause

The `tree-filter` was reading `.mirror-blacklist` from the **current commit** inside the temp worktree:

```bash
tree_filter="
    if [ -f .mirror-blacklist ]; then   # <-- checks THIS commit's tree
        while IFS= read -r line; do
            rm -rf \"\$line\"
        done < .mirror-blacklist
    fi
"
```

When `filter-branch` rewrote an old commit that did not yet contain `.mirror-blacklist`, the `[ -f .mirror-blacklist ]` check was false — nothing was stripped. The blacklist only affected commits created *after* the file was added.

## Fix

Read the blacklist from the **source repository** (outside the worktree) so the current blacklist applies retroactively to every commit:

```bash
# In the main script (before filter-branch), repo_root is known:
repo_root="$(git rev-parse --show-toplevel)"

# In the tree-filter, use the source repo's path:
tree_filter="
    blacklist_path='${repo_root}/.mirror-blacklist'
    if [ -f \"\$blacklist_path\" ]; then
        while IFS= read -r line; do
            [ -z \"\$line\" ] && continue
            case \"\$line\" in \#*) continue ;; esac
            rm -rf \"\$line\"
        done < \"\$blacklist_path\"
    fi
    rm -f .mirror-blacklist  # strip the file itself too
"
```

## Why this works

`git-filter-branch` runs the `tree-filter` in a subshell for **every commit**. The subshell inherits the main script's shell variables, so `$repo_root` resolves correctly even when processing commits from years ago. The `$repo_root/.mirror-blacklist` file lives on disk outside the rewritten history and is therefore available regardless of which commit is being processed.

## Lesson

> When using `filter-branch` to remove files across history, reference removal rules from a **stable external source** — not from the commit tree itself. The commit tree changes as you travel back in time; external files do not.
