# Stale .gitignore Rule Cleanup

**Context**: `.gitignore` rules for deleted files can accidentally re-introduce working-tree copies when the rule is removed.

## Hazard

When a file is deleted from the repo but its `.gitignore` rule survives, cleaning the rule can accidentally promote the (still-existing) working-tree copy into an **untracked** file. If the user then runs `git add -A`, the file gets committed.

## Procedure

1. Before removing a `.gitignore` rule, check if the file still exists in the working tree:
   ```bash
   ls <ignored-file> 2>/dev/null && echo "STILL EXISTS"
   ```

2. If it exists and is a local-only scratch file (e.g. `/r.sh`, resume scripts):
   - **Keep the rule** but update the comment to be honest: `# Local scratch files — never commit`
   - OR delete the file from working tree first, then remove the rule

3. If it does not exist:
   - Safe to remove the rule

## Example

```
# Before
tmp/
.public-export/
public-export/
# AI session resume scripts
/r.sh
/RESUME.sh
nix-bug.txt

# After (nix-bug.txt deleted, resume scripts still exist locally)
tmp/
.public-export/
public-export/
# AI session resume scripts — never commit these
/r.sh
/RESUME.sh
```

## Cross-Check

After removing an ignore rule, always run:
```bash
git status
```
Verify no unexpected untracked files appeared.
   -- Learned from: j0nix-os session, commit e2f1efb
