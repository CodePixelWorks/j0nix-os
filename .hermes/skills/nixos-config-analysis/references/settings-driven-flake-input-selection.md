# Settings-Driven Flake Input Selection

When a NixOS flake exposes the same upstream project through multiple flake inputs (e.g. `stable` vs `dev` channels), the active input is usually chosen by a setting in `settings.nix`, not by the flake input name alone. Updating the wrong input produces no runtime change and looks like a silent no-op.

## General Discovery Pattern

1. **Find the user-facing selector in `settings.nix`**. Look for a `channel`, `branch`, `runtime`, or `source` field under the relevant program block.

   Example (`programs.caelestia.channel`):
   ```nix
   programs.caelestia = {
     channel = "dev";          # "stable" | "dev"
     quickshellRuntime = "wrapped"; # "wrapped" | "upstream"
   };
   ```

2. **Map the selector to a flake input name in the module**. The module that consumes the input translates the selector into the actual `inputs.<name>` reference.

   Example (`nix/user/wm/hyprland/shells/caelestia-shell/default.nix`):
   ```nix
   caelestiaChannel = caelestiaSettings.channel or "stable";
   caelestiaInputName = if caelestiaChannel == "dev" then "caelestia-shell-dev" else "caelestia-shell";
   ```

3. **Update only the active input** (unless the user explicitly asks to refresh both). Run:
   ```bash
   nix flake lock --update-input <active-input-name>
   ```

4. **Validate with the fast no-build check**:
   ```bash
   nix flake check --no-build
   ```

5. **Commit only the lock-file change** for that input. Do not stage unrelated working-tree changes that were present before the update.

## Common Variations

| Variation | Where it lives | Typical fields |
|-----------|---------------|----------------|
| Channel selector | `settings.nix` under the program block | `channel`, `branch`, `edition` |
| Runtime selector | Same program block or module | `quickshellRuntime = "wrapped" \| "upstream"` |
| Input name mapping | Module consuming the input | `if channel == "dev" then "foo-dev" else "foo"` |
| Helper script | `scripts/` | `scripts/update-shell-inputs.sh` may update a default set |

## Pitfalls

- **Updating the stable input while the user runs the dev channel**: The lock file changes, but the installed package stays the same. Always read `settings.nix` first.
- **Committing unrelated changes**: A dirty working tree often contains unrelated edits. Stage only `flake.lock` unless the user asked for a broader commit.
- **Assuming one input per project**: Forked inputs (`foo` vs `foo-dev`, `quickshell-stable` vs `quickshell-dev`) are common for shells, WMs, and rapidly moving upstreams.
- **Forgetting transitive inputs**: Some inputs pull in their own dependencies (e.g. `caelestia-shell-dev` also updates `caelestia-cli`). `nix flake lock --update-input` updates the named input and its transitive flake inputs automatically.

## Example: caelestia-shell

```bash
# settings.nix says programs.caelestia.channel = "dev"
nix flake lock --update-input caelestia-shell-dev
nix flake check --no-build
git add flake.lock
git commit -F /tmp/msg.txt
```

If the channel were `"stable"`, the correct input would be `caelestia-shell` instead.
