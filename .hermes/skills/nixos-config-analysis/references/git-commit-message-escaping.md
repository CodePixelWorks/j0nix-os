# Git Commit Message Escaping for Nix/Technical Commits

**Scope**: Safe commit message writing when backticks, Nix interpolation, or other shell-sensitive characters are present.

## The Problem

When using `git commit -m "..."` inline, bash interprets backticks as command substitution and `$` as variable expansion:

```bash
# DANGEROUS — backticks trigger command substitution
git commit -m "feat(nix): add `pkgs.streambert` via overlay"
#           ^ bash runs 'pkgs.streambert' as a command!

# DANGEROUS — $ triggers variable expansion
git commit -m "fix(bambulab): resolve ${cfg.enable} default"
#           ^ bash expands $cfg (probably empty), mangling the message
```

## The Safe Pattern

Write the message to a file first, then commit with `-F`:

```bash
cat > /tmp/commit-msg.txt <<'EOF'
feat(nix): add Streambert via overlay

- wire pkgs.streambert in system/lib/flake/overlays.nix
- add HM module user/programs/streambert/default.nix
- settings contract: programs.streambert.enable = true/false
EOF
git commit -F /tmp/commit-msg.txt
```

**Why this works**: The `<<'EOF'` heredoc does NOT expand `$` or backticks. The file is passed to git verbatim, bash never sees the content.

## When to Use `-F` vs Inline `-m`

| Situation | Use `-F` | Use inline `-m` |
|-----------|----------|-----------------|
| Message contains backticks `` ` `` | ✅ | ❌ |
| Message contains `$(...)` or `${...}` | ✅ | ❌ |
| Message contains Nix interpolation `''${...}` | ✅ | ❌ |
| Multi-line body with blank lines | ✅ | `-m "subj" -m "body"` works but `-F` is cleaner |
| Simple single-line without special chars | Either | ✅ |

## Quick Template

For every NixOS/config commit, prepare the message file:

```bash
write_file("/tmp/msg.txt", """\
type(scope): short summary

- what changed
- why it changed
- follow-up notes
""")
# Then:
# git commit -F /tmp/msg.txt
```

**User preference**: The user explicitly expects `-F` for all commits in this repo when messages contain technical notation. Inline `-m` without special chars is acceptable for trivial one-liners.
