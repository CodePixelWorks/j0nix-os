# Error Transcript: "Cannot rewrite branches: You have unstaged changes"

**Context:** Running `scripts/publish-public-github.sh` in a Drone CI container for j0nix-os (Gitea → GitHub mirror).

## Symptom

```
Generated README.md.public (scope: public)
Cannot rewrite branches: You have unstaged changes.
Additionally, your index contains uncommitted changes.
```

## Timeline of Fixes

### Attempt 1: Sidecar in temp worktree (FAILED)
```bash
python3 scripts/regenerate-readme.py --scope public --output README.md.public
git add README.md.public          # <-- BUG: dirty index
```

Fix: remove `git add`, copy sidecar unstaged. But then:

### Attempt 2: Overwrite `$work_dir/README.md` after clone (FAILED)
```bash
git clone --local --no-hardlinks "$repo_root" "$work_dir"
cd "$work_dir"
python3 scripts/regenerate-readme.py --scope public --output README.md  # modifies tracked file
# filter-branch: "unstaged changes" because tracked file differs from HEAD
```

Fix considered: stage the change. But staging also blocks filter-branch.

### Attempt 3: Inject via absolute path from original repo root (WORKING)
```bash
readme_path="$repo_root/README.md.public"   # generate OUTSIDE the temp worktree
git clone --local --no-hardlinks "$repo_root" "$work_dir"
cd "$work_dir"
# worktree is 100% clean — identical to HEAD
tree_filter="cp -f '$repo_root/README.md.public' README.md 2>/dev/null || true"
rm -f "$repo_root/README.md.public"  # cleanup after successful run
```

This is the final working pattern. The key insight: **any modification or new file inside `$work_dir` after `git clone` can trigger the "unstaged changes" abort.** Generate artifacts outside the temp worktree entirely, and use the tree-filter's subshell (which can read the original repo via absolute path) to inject them.

## CI Container Lesson

`python3: command not found` also hit. Cascading fallback:

```bash
if command -v python3 >/dev/null 2>&1; then
    python3 ...
elif command -v nix >/dev/null 2>&1; then
    nix --extra-experimental-features 'nix-command flakes' run nixpkgs#python3 ...
else
    echo "ERROR: python3 not found and nix not available" >&2; exit 1
fi
```

`--extra-experimental-features 'nix-command flakes'` is REQUIRED in containers.
Without it: `error: experimental Nix feature 'nix-command' is disabled`.
