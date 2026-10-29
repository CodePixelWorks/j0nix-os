# Stripping Private Flake Inputs from Public Mirror

When a Nix flake depends on a private input (a Gitea-hosted identity
flake, a private source-patch repo, an unreleased package fork), the
input block in `flake.nix` AND the input node in `flake.lock` must both
be removed from any public mirror tree. Removing only `flake.lock`
leaves the `flake.nix` URL visible; removing only `flake.nix` makes
evaluation fail because `flake.lock` still references a node the
mirror has no source for.

## The three files that all need the same stripping logic

j0nix-os (and most NixOS flake repos that publish a public mirror) keep
this logic in **three** places:

| File | Role | Where the strip lives |
|---|---|---|
| `scripts/publish-public-github.sh` | Full history rewrite via `filter-branch` / `mirror-sync-*` | Inside the `tree-filter` heredoc |
| `scripts/export-public-github.sh` | Single tree export (no history) | A standalone Python block, run after copying files into `$tmp_dir` |
| `scripts/lib/mirror-sanitize.sh` | Shared engine consumed by both forward and backward sync | Inside `ms_apply_tree_filter` |

**Drift warning:** patch only one of these and the others will silently
leak the private input. Always update all three in the same commit.

## Stripping `flake.nix` (multi-line attrset block)

`flake.nix` inputs are multi-line attrsets that wrap a `url = ...;` line
and any `inputs.<other>.follows = ...` lines. `sed` line-based removal
breaks on the second line and leaves dangling braces; use a Python
regex that matches the block from `<name> = {` to the matching `};`:

```python
import re

# Match the named input attrset entry (single-line or block form).
# Anchored on a leading newline so the preceding comma / whitespace is
# consumed cleanly without leaving "}" artefacts.
pattern = re.compile(
    r'\n\s*' + re.escape(name) + r'\s*=\s*\{[^{}]*(?:\{[^{}]*\}[^{}]*)*\}\s*;\s*\n',
    re.MULTILINE,
)
src = pattern.sub('\n', src, count=1)
```

The `[^{}]*(?:\{[^{}]*\}[^{}]*)*` middle allows one level of nested
braces (for the `inputs.nixpkgs.follows = ...` form) without breaking
on the first `{` of the wrapper.

Run the substitution in a loop over every private input name:

```python
names = ('j0nix-identity-secrets', 'resolve-patch')  # etc.
for name in names:
    pattern = re.compile(
        r'\n\s*' + re.escape(name) + r'\s*=\s*\{[^{}]*(?:\{[^{}]*\}[^{}]*)*\}\s*;\s*\n',
        re.MULTILINE,
    )
    src = pattern.sub('\n', src, count=1)
```

## Stripping `flake.lock` (json node + every inputs reference)

`flake.lock` is JSON, so json manipulation is safer than sed/jq (jq
may be missing in minimal CI subshells):

```python
import json

with open('flake.lock') as f:
    d = json.load(f)

for name in ('j0nix-identity-secrets', 'resolve-patch'):
    # Remove the node entry entirely.
    d['nodes'].pop(name, None)
    # Remove the reference from EVERY inputs map — root and transitive
    # consumers (other flakes that declared `inputs.<name>.follows`).
    for node in d['nodes'].values():
        if isinstance(node, dict) and 'inputs' in node:
            node['inputs'].pop(name, None)

with open('flake.lock', 'w') as f:
    json.dump(d, f, indent=2)
    f.write('\n')
```

Iterating `d['nodes'].values()` and popping from each `inputs` map is
the correct way to handle transitive references. A naive `pop` from
just `d['nodes']['root']['inputs']` leaves dangling `follows` entries
in other consumers' lockfile nodes.

## Settings.nix must degrade gracefully when the input is removed

Removing the input is only safe when the consumer's `settings.nix`
defaults to an identity mode / sops source that does NOT depend on the
input. The pattern in j0nix-os:

```nix
# settings.nix
identityMode = "legacy"; # "legacy" | "shared-flake"

sshSopsFile =
  if identityMode == "shared-flake" then sharedSshSopsFile else legacyUserSopsFile;
```

After stripping the input, the evaluation must still succeed with the
default mode. Verify with `nix flake check --no-build` on a fresh
mirror snapshot.

### Operational default lives in `settings.nix.example`, NOT `settings.nix`

In j0nix-os the public mirror strips `settings.nix` and replaces it
with `settings.nix.example` at tree-filter time:

```bash
rm -f .sops.yaml settings.nix profiles/desktop/details.nix profiles/desktop/hardware-configuration.nix
cp -f settings.nix.example settings.nix 2>/dev/null || true
cp -f .sops.yaml.example .sops.yaml 2>/dev/null || true
```

This means **the operational default for the mirror lives in
`settings.nix.example`**. When you add a new setting that touches a
private flake input (an explicit `identityMode`, a `lib` reference, an
optional overlay), the safe-default value MUST be set in the
`.example` template, not in the real `settings.nix`. Reviewers
checking the public mirror will only see the `.example` content.

Common mistake: the real `settings.nix` carries `mode = "legacy"` for
the private maintainer, but `settings.nix.example` still has the
old default or is missing the `identity` block entirely. After the
mirror pipeline strips the real `settings.nix`, the public mirror
evaluates the `.example` content — which means a forgotten
`identity = { mode = "legacy"; }` line breaks `nix flake check` for
every downstream consumer.

Verification recipe:

```bash
# 1. Confirm settings.nix.example carries the safe default
grep -A2 'identity = {' settings.nix.example

# 2. Run the export and copy .example into the real path
bash scripts/export-public-github.sh /tmp/mirror-check
cp /tmp/mirror-check/settings.nix.example /tmp/mirror-check/settings.nix

# 3. Verify the mirror still evaluates with the stripped input
cd /tmp/mirror-check && git init -q && git add -A && \
    git -c user.email=ci@local -c user.name=ci commit -q -m 'test'
nix flake check --no-build
```

If step 3 fails because the `.example` is missing the safe default,
the public mirror has a latent leak that the source-repo eval would
not catch (because the source repo has the real `settings.nix`).

## Verification checklist

After updating all three scripts and stripping the input, run:

```bash
rm -rf /tmp/mirror-check
bash scripts/export-public-github.sh /tmp/mirror-check
```

Then verify:

```bash
# No leak in either flake file
for name in j0nix-identity-secrets resolve-patch; do
  echo "$name flake.nix:  $(grep -c "$name" /tmp/mirror-check/flake.nix)"
  echo "$name flake.lock: $(grep -c "$name" /tmp/mirror-check/flake.lock)"
done
# Both should be 0.

# Mirror still evaluates (after copying .example -> real files)
cd /tmp/mirror-check
git init -q && git add -A && git -c user.email=ci@local -c user.name=ci commit -q -m 'mirror test'
cp settings.nix.example settings.nix
cp .sops.yaml.example .sops.yaml
cp profiles/desktop/details.nix.example profiles/desktop/details.nix
# (copy any other .example files needed by your flake)
nix flake check --no-build
```

The final `nix flake check` is the most important guard: if the
mirror can't evaluate with `mode = "legacy"` after the input is
removed, your settings.nix is silently relying on the stripped
input and the public mirror will break for downstream users.
