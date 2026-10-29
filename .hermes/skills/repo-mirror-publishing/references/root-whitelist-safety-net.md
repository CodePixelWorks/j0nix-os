# Root Whitelist for Mirror Safety Net

## Problem

A developer creates a temporary file in the repo root (e.g. `RESUME.sh`, `notes.txt`, `debug.env`) and forgets about it. When the mirror runs, `.mirror-blacklist` only removes explicitly-listed paths — unlisted root files leak into the public mirror.

## Root Cause

`.mirror-blacklist` is a deny-list: you must enumerate every bad thing. The root whitelist is an allow-list: only enumerated top-level files survive. Complementary approaches with different failure modes.

## Solution

Create `.mirror-root-whitelist` at repo root:

```text
# Files explicitly allowed in the repository root.
# Any top-level file not listed here is stripped from the public mirror.
# Directories under the root are not affected by this check.

.gitignore
.mirror-root-whitelist
.sops.yaml
AGENTS.md
LICENSE
Makefile
README.md
flake.lock
flake.nix
settings.nix
```

In the tree-filter, enforce it:

```bash
whitelist_path='${repo_root}/.mirror-root-whitelist'
if [ -f "\$whitelist_path" ]; then
    whitelist=""
    while IFS= read -r line; do
        [ -z "\$line" ] && continue
        case "\$line" in \#*) continue ;; esac
        whitelist="\$whitelist \$line"
    done < "\$whitelist_path"

    for entry in .* *; do
        case "\$entry" in \.'|'..') continue ;; esac
        [ -f "\$entry" ] || continue
        case " \$whitelist " in
            *" \$entry "*) ;;
            *) rm -f "\$entry" ;;
        esac
    done
fi
```

## Key Rules

1. Read the whitelist from the SOURCE repo (like `.mirror-blacklist`) so it applies retroactively
2. Only strip top-level REGULAR FILES — leave directories alone
3. Strip both `.mirror-blacklist` and `.mirror-root-whitelist` from the mirror itself
4. Document the whitelist in AGENTS.md so new contributors know why a new root file silently disappears from the public mirror
