# j0nix-os .gitignore Policy

Repository-specific rule for the `j0nix-os` NixOS configuration repository.

## Rule

The root `.gitignore` **must NOT** list files that are required by `nix flake check` (or any other build/evaluation step). Specifically:

- `settings.nix` — required by `flake.nix`; the mirror pipeline replaces it with `.example` in the tree-filter
- `profiles/desktop/details.nix`
- `profiles/desktop/hardware-configuration.nix`
- `.sops.yaml`

These files are tracked in the **private source** repository. The public mirror pipeline strips or replaces them at publish time, so leaving them untracked (ignored) serves no purpose and only creates operational friction.

## Why this matters

If a required file is listed in `.gitignore` but not tracked in git, the working tree is permanently "dirty" from `git status`'s perspective when the file exists. `git filter-branch` will abort with:

```
Cannot rewrite branches: You have unstaged changes.
```

Even if the file is present on disk, an ignored-but-untracked required file can cause issues with tools that check repository cleanliness before running filter-branch.

## What `.gitignore` SHOULD cover

- Local-only overrides that never leave the developer machine (e.g. `settings.local.nix`, `profiles/desktop/details.local.nix`)
- Build artifacts, `.env` files, temporary downloads, caches
- IDE/editor droppings (`.vscode/`, `.idea/`)

## Validation

Before any mirror publish or `filter-branch` run:

```bash
git status --short          # must show nothing
git status --ignored        # must not list any required .nix files
```

If `settings.nix` or any required profile config appears under `--ignored`, remove it from `.gitignore` and commit the template/example version to the private repo.
