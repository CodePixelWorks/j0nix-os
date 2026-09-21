# Nix Package Source Inspection and Patching

## When to Use

- A derivation produces a compiled binary (C++, Qt/QML, Go, Rust) and you need to understand upstream behavior that you cannot see in the built output (UI layout, hardcoded defaults, build scripts).
- You need to make a small upstream change (hide a UI element, change a hardcoded default, strip dead code) without forking the upstream repo.

## Technique

### 1. Discover Upstream Source in the Nix Store

Every Nix `fetch` produces a store path. The derivation's `src` attribute exposes it:

```bash
nix eval --json '.#nixosConfigurations.Jonas-PC.pkgs.qmlgreet.src.outPath' \
  | xargs -I{} find {} -type f | sort
```

Or directly read files:

```bash
nix eval --json '.#nixosConfigurations.Jonas-PC.pkgs.qmlgreet.src.outPath' \
  | xargs -I{} grep -rn "system-suspend" {}/qml
```

This also works for `fetchFromGitHub`, `fetchurl`, and path sources. The `src.outPath` is a plain directory in `/nix/store`.

### 2. Inspect Files That Drive the Bug

For UI bugs (QML-based greeters, GTK panels, etc.), the files of interest are usually `qml/*.qml`, `src/**/*.cpp`, or `data/*.xml`:

```bash
src=$(nix eval --json '.#foo.src.outPath' | tr -d '"')
cat "$src/qml/main.qml"
```

### 3. Apply a Patch in the Derivation

After confirming the pattern exists in the source, add a `postPatch` to the derivation:

```nix
postPatch = ''
  # Remove hibernation variants from the greeter bottom bar.
  # They share the same icon (system-suspend-hibernate) and are
  # visually indistinguishable in the UI.
  sed -i '/StyledButton { iconName: "system-suspend-hibernate";/d' qml/main.qml
'';
```

Rules for choosing the patch tool:
- **Single-line declarative blocks** (compact QML/GTK XML): `sed -i` with a simple pattern is fine.
- **Multi-line blocks or structured changes**: Use `substituteInPlace --replace` or a `patch -p1` with a known `.patch` file checked into the repo.
- **Build scripts, meson/CMake configs**: `substituteInPlace` is safer because it fails if the pattern disappears in an upstream update.

### 4. Rebuild and Verify

```bash
nix build --no-link .#nixosConfigurations.Jonas-PC.pkgs.qmlgreet
nix flake check --no-build
```

After the build completes, verify the store path no longer contains the undesired content:

```bash
nix eval --json '.#nixosConfigurations.Jonas-PC.pkgs.qmlgreet.src.outPath' \
  | xargs -I{} grep -c "system-suspend-hibernate" {}/qml/main.qml
# Expected: 0
```

## Pitfalls

1. **Binary output ≠ source visible in runtime**: A Qt/QML binary embeds QML files via `resources.qrc`; the QML source is compiled into the binary. You will NOT find `main.qml` in the runtime store path (only under `.src`).
2. **Store paths are read-only in runtime but writable during build**: `sed -i` works inside `postPatch` because it runs in the build sandbox; it will not work on `/nix/store/...` after the build.
3. **Pattern brittleness with upstream updates**: If upstream reformats the QML line (breaks single-line into multi-line), `sed` fails silently. For resilience, prefer `substituteInPlace` when the string is unique within the file.
4. **Changing the derivation invalidates all downstream closures**: Any change to `postPatch` changes the derivation hash and triggers a rebuild of everything that depends on this package.

## QML/QRC Specific Pitfalls

- **QML source compiled-in via `.qrc`**: Compilation embeds QML files into the binary. Inspecting `src.outPath` is the only way to see UI layout *before* build.
- **Icon name strings, not icon paths**: QML greeters reference icons by KDE icon theme name (e.g. `"system-suspend-hibernate"`), not by absolute path. Changing the icon requires patching the QML or the icon theme, not the package.
- **Row-based UI lists**: QML `RowLayout` with repeated `StyledButton` declarations is a classic duplication vector. When upstream adds variants with the same icon, users see "duplicate" buttons that are actually distinct functions.

## Related Analysis Patterns

- For session/UI duplication issues that are *not* source-patchable (list generated at runtime from config), see the __Greetd environment list__ anti-pattern: hardcoding both `hyprland.desktop` and `hyprland-uwsm.desktop` as separate entries when `hyprlandSessionName` already selects one.
- See also: `references/session-j0nix-os-greetd-session-duplication.md` — duplicate session entries in `greetdEnvironments` causing duplicate login screen buttons.

## Example from Session

**Problem**: qmlgreet greeter showed three visually identical hibernation buttons (`hibernate`, `hybridSleep`, `suspendThenHibernate`) all using the same `system-suspend-hibernate` icon.

**Investigation**:
```bash
nix eval --json '.#nixosConfigurations.Jonas-PC.pkgs.qmlgreet.src.outPath' \
  | xargs -I{} cat {}/qml/main.qml
```
Revealed 6 `StyledButton` lines in the bottom bar.

**Fix in** `system/software/pkgs/greetd/qmlgreet.nix`:
```nix
postPatch = ''
  sed -i '/StyledButton { iconName: "system-suspend-hibernate";/d' qml/main.qml
'';
```

**Result**: Only `suspend`, `reboot`, and `shutdown` action buttons remain. UI is clean.
