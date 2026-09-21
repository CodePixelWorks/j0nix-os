# Systemd Service + Managed Mount Integration in NixOS

Pattern for wiring a systemd service (e.g. Docker, Plex, databases) to wait for its data directory's mount unit before starting. Applicable when the data directory lives on an external drive declared in `settings.storage.systemMounts`.

## Problem

When a service's `dataRoot` is on a mount with `automount = true`, the service may start before the mount is triggered. If the mount is missing, the service creates its data directory on the root filesystem, leading to silent root-fs consumption and data loss after the real mount appears.

```bad
# settings.nix
storage.systemMounts = [{
  mountPoint = "/mnt/LinuxData";
  automount = true;       # mounts on access, not at boot
  # ...
}];

dev.docker.dataRoot = "/mnt/LinuxData/docker";  # FAILS: Docker starts before mount
```

## Solution

Derive the systemd mount unit name from the declarative mount configuration and inject `After`/`Requires` only when the parent mount is automount-managed.

### Generic Implementation

```nix
{ lib, utils, settings, ... }:
let
  dockerDataRoot = (settings.dev or {}).docker.dataRoot or null;
  systemMounts   = (settings.storage or {}).systemMounts or [];

  isPathUnderMount = mountPoint: dataRoot:
    let
      mp = lib.removeSuffix "/" mountPoint;
      dr = lib.removeSuffix "/" dataRoot;
    in dr == mp || lib.hasPrefix "${mp}/" dr;

  parentMount = lib.findFirst
    (m: (m.enable or true) && isPathUnderMount m.mountPoint dockerDataRoot)
    null
    systemMounts;

  parentMountUnit =
    if parentMount != null && (parentMount.automount or false) then
      "${utils.escapeSystemdPath (lib.removeSuffix "/" parentMount.mountPoint)}.mount"
    else
      null;
in
{
  systemd.services.myservice = lib.mkIf (dockerDataRoot != null) {
    after    = lib.optional (parentMountUnit != null) parentMountUnit;
    requires = lib.optional (parentMountUnit != null) parentMountUnit;

    serviceConfig.ExecStartPre = [
      (pkgs.writeShellScript "data-root-check" ''
        parent=$(dirname "${dockerDataRoot}")
        if [ ! -d "$parent" ]; then
          echo "ERROR: data-root parent $parent is not mounted"
          exit 1
        fi
        ${pkgs.coreutils}/bin/mkdir -p "${dockerDataRoot}"
      '')
    ];
  };
}
```

### Key Rules

1. **Only add `After`/`Requires` for `automount = true` mounts.** Fixed boot-time mounts (`automount = false`) are already present when systemd reaches `multi-user.target`; extra deps are unnecessary.
2. **Always add the `ExecStartPre` guard.** Even for non-automount mounts, the guard prevents root-fs contamination if the mount fails or is temporarily disconnected.
3. **Use `utils.escapeSystemdPath`** (available in NixOS modules via `specialArgs` or module args) to translate mount paths to systemd unit names. `/mnt/LinuxData` → `mnt-LinuxData.mount`.
4. **Accept `utils` in the module args.** `nixosSystem.specialArgs` does NOT include `utils`; it is injected by the module system's base arguments. Your module signature must accept it explicitly:
   ```nix
   { config, lib, pkgs, utils, settings, ... }:
   ```

### Why Not Hardcode?

Hardcoding `mnt-LinuxData.mount` works once, but breaks when:
- The user changes the mount path (e.g. `/mnt/Backup`)
- The feature is ported to a different host with different storage layout
- Multiple mounts need the same treatment (e.g. `/mnt/Games/steam`, `/mnt/Media/plex`)

Deriving from `settings.storage.systemMounts` keeps the module self-configuring.

### Pitfalls

- **Missing `utils` in module args:** Leads to `attribute 'utils' missing` during eval.
- **lib.findFirst returns `null` when no mount matches:** Always handle with `parentMount != null` before accessing `.automount`.
- **Trailing slashes:** `lib.hasPrefix "/mnt/LinuxData/" "/mnt/LinuxData"` is `false`. Strip trailing slashes with `lib.removeSuffix "/"`.
- **Automount unit vs mount unit:** When `automount = true`, NixOS creates both `.automount` and `.mount` units. The service should depend on the `.mount` unit (the actual mount), not `.automount` (the trigger).

## Related References

- `nixos-config-analysis` SKILL.md — Directory structure and settings/profiles boundary
- `references/nixos-lab-vm-workflow-pitfalls.md` — `lib.mkForce` and systemd unit naming traps
- `references/session-settings-vs-profiles-boundary.md` — Host-specific mount UUIDs belong in profiles, generic data-root policy in settings
