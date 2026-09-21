# QMLGreet Greeter Button Cleanup

Session: 2026-05-22 — cleaning up duplicated/dangling action buttons in qmlgreet login screen.

## Context

QMLGreet's `qml/main.qml` renders a bottom bar with power-action buttons.
Three hibernation variants (hibernate, hybridSleep, suspendThenHibernate) all use
the same icon (`system-suspend-hibernate`). They are visually indistinguishable
and produce confusing duplicate/ambiguous buttons.

## Inspecting Upstream Source

When patching a Nix-packaged Qt/QML app, source inspection is the first step:

```bash
# Derivation source lands in the store — access it without unpacking tarballs
nix eval --json '.#nixosConfigurations.<host>.pkgs.qmlgreet.src.outPath' \
  | xargs -I{} cat {}/qml/main.qml

# Also useful for .cpp / .h backend files
nix eval --json '.#<pkg>.src.outPath' | xargs -I{} find {} -type f
```

## The QML Button Row (upstream)

```qml
RowLayout {
  id: buttonRow
  StyledButton { iconName: "system-suspend";        visible: power.canSuspend();        onClicked: power.suspend() }
  StyledButton { iconName: "system-suspend-hibernate"; visible: power.canHibernate();      onClicked: power.hibernate() }
  StyledButton { iconName: "system-suspend-hibernate"; visible: power.canHybridSleep();    onClicked: power.hybridSleep() }
  StyledButton { iconName: "system-suspend-hibernate"; visible: power.canSuspendThenHibernate(); onClicked: power.suspendThenHibernate() }
  StyledButton { iconName: "system-reboot";          visible: power.canReboot();         onClicked: power.reboot() }
  StyledButton { iconName: "system-shutdown";        visible: power.canPowerOff();       onClicked: power.powerOff() }
}
```

## Fix: `postPatch` in Nix Derivation

Remove all three hibernate-variant lines with a single `sed`:

```nix
postPatch = ''
  sed -i '/StyledButton { iconName: "system-suspend-hibernate";/d' qml/main.qml
'';
```

Why not `substituteInPlace`? `substituteInPlace` is good for single, unique
matches. When three consecutive lines match the same pattern, `sed` with a
pattern delete is shorter and less error-prone than three separate
`substituteInPlace --replace` calls.

## Pitfall: Rebuild Verification

After adding `postPatch`, build the package directly (not the whole system)
to verify the derivation still compiles:

```bash
nix build --no-link .#nixosConfigurations.<host>.pkgs.qmlgreet
```

## Pitfall: `.gitignore` and Resurrection of Ignored Files

When removing a dead `.gitignore` rule for a deleted file (e.g. `nix-bug.txt`),
be careful: if files matching other rules in the same block (e.g. `/r.sh`,
`/RESUME.sh`) are still present in the working tree, removing the block
and running `git add -A` may add those previously-ignored files to the repo.

**Rule**: stage only the files you intend. Use `git add <specific-file>` rather
than `git add -A` when editing `.gitignore`, or inspect `git status` before
committing.

## Result

Bottom bar reduced from six to three buttons: suspend, restart, shutdown.
No visual ambiguity.

## Related Skills

- `nix-package-patching-patterns.md` — broader patching arsenal (`.patch` files,
  `substituteInPlace`, `sed`).
