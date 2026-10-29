# README Generation Pitfalls in filter-branch Workflows

## Problem: "Cannot rewrite branches: You have unstaged changes"

**Symptom:** `git-filter-branch` fails immediately with:
```
Cannot rewrite branches: You have unstaged changes.
Additionally, your index contains uncommitted changes.
```

## Root Causes and Fixes

### Cause A: Generating inside the temp worktree dirties the tree
If you generate or copy a new file into `$work_dir/` after `git clone`,
`filter-branch` sees the worktree as dirty and aborts — even if the file
is unstaged.

**Fix:** Generate the public README completely outside the temp worktree,
into the original repo root or `/tmp`. The `tree-filter` then injects it
into each rewritten commit via absolute path.

```bash
readme_path="$repo_root/README.md.public"   # outside $work_dir!
python3 "$repo_root/scripts/regenerate-readme.py" --scope public --output "$readme_path"

git clone --local --no-hardlinks "$repo_root" "$work_dir"
cd "$work_dir"
# $work_dir is 100% clean — filter-branch will accept it

tree_filter="cp -f '$repo_root/README.md.public' README.md 2>/dev/null || true"
```

### Cause B: `git add` of a generated sidecar inside the worktree
Staged changes in the temp clone also block filter-branch.

**Fix:** Do not `git add` anything in the temp clone before filter-branch.

## Final Working Pattern (j0nix-os)

1. **Generate outside worktree:**
   ```bash
   readme_path="$repo_root/README.md.public"
   python3 "$repo_root/scripts/regenerate-readme.py" --scope public --output "$readme_path"
   ```

2. **Clone into temp workspace (clean):**
   ```bash
   work_dir="$(mktemp -d)"
   git clone --local --no-hardlinks "$repo_root" "$work_dir"
   cd "$work_dir"
   ```

3. **Inject via tree-filter using absolute path:**
   ```bash
   tree_filter="cp -f '$repo_root/README.md.public' README.md 2>/dev/null || true"
   ```

4. **Cleanup after push:**
   ```bash
   rm -f "$readme_path"
   ```

## Why this works

`git-filter-branch` examines `$work_dir` for cleanliness BEFORE it starts.
Because the README was generated into `$repo_root` (the original repo),
`$work_dir` remains exactly as `git clone` left it — no untracked files,
no modified tracked files, no staged changes. The `tree-filter` runs in a
subshell that can read `$repo_root` via the absolute path, injecting the
public README into every commit without ever touching the pre-rewrite
worktree state.

## Deprecated Patterns

| Pattern | Why it failed |
|---------|---------------|
| `git add README.md.public` in temp clone | Dirty index → filter-branch aborts |
| Overwrite `$work_dir/README.md` after clone | Modified tracked file → "unstaged changes" |
| Generate into `/tmp`, copy into `$work_dir/` unstaged | Untracked file in worktree → filter-branch aborts (some versions) |

## Lessons
- **Keep the temp worktree untouched after `git clone`.** Any file creation or modification inside `$work_dir` risks aborting filter-branch.
- **Use the original repo root as staging ground for generated artifacts** that need to survive into the tree-filter. The tree-filter can read anywhere the shell has access to.
- **Always run `git status` inside `$work_dir` before `filter-branch`** when debugging "unstaged changes" errors.
