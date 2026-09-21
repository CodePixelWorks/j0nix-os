---
name: nixos-desktop-session-config
description: |
  Patterns for authoring and modifying NixOS desktop session components:
  window manager scripts, storage mounts, desktop application integrations,
  and user secret management.
trigger: |
  When the user asks to change, add, or fix something in a NixOS desktop
  environment configuration (Hyprland, GNOME, Sway, etc.), including
  keybinds, window rules, mounting disks, installing desktop apps, or
  managing user secrets.
---

# NixOS Desktop Session Configuration

## Window Manager Scripts

### Creating a script and binding it

Scripts are declared with `pkgs.writeShellScriptBin` in the Hyprland module
(typically `nix/user/wm/hyprland/default.nix`) and added to the package list
so they land in the user profile `bin/` directory.

```nix
hyprlandToggleFloatResizeScript = pkgs.writeShellScriptBin "wm-toggle-float-resize" ''
  hyprctl_bin="${hyprctlExec}"
  [ -x "$hyprctl_bin" ] || exit 0
  # ... script body ...
'';

# In packages list:
++ [ hyprlandToggleFloatResizeScript ];
```

Keybinds reference them via `${homeBinDir}/script-name` (typically
`$HOME/.nix-profile/bin/`).

### Hyprland Dispatcher Pitfalls

| Dispatcher | Behavior | Use when... |
|---|---|---|
| `resizeactive` | Resizes **relatively** (delta) | You want to grow/shrink by N pixels |
| `resizewindowpixel` | Resizes **absolutely** to exact pixel dimensions | You know the target width/height |

Common mistake: `resizeactive exact 1400 920` — `exact` is ignored and
Hyprland treats 1400×920 as delta, growing the window massively.

Correct absolute resize:
```bash
hyprctl dispatch resizewindowpixel exact 1400 920
```

Query window state after a toggle (there's a brief moment where state may
not have propagated):
```bash
floating="$(hyprctl activewindow -j | jq -r '.floating // false')"
```

### Hyprland 0.55+ Dispatch Syntax (Lua Parsed)

In Hyprland 0.55+, arguments to `hyprctl dispatch` are parsed as **Lua
code**. Legacy space-separated dispatcher strings (e.g. `submap global`,
`dpms on`, `exit`) may fail because they are no longer interpreted as
Hyprlang but as Lua expressions.

**Migration rules:**

1. **If a native `hl.dsp.*` API exists, use it:**
   ```bash
   # Old                            # New
   hyprctl dispatch exit            hyprctl dispatch 'hl.dsp.exit()'
   hyprctl dispatch dpms on         hyprctl dispatch 'hl.dsp.dpms({state = "on"})'
   hyprctl dispatch workspace 5     hyprctl dispatch 'hl.dsp.focus({ workspace = "5" })'
   ```

2. **If no native API exists, wrap with `hl.dsp.exec_cmd`:**
   ```bash
   # Old                            # New
   hyprctl dispatch moveworkspacetomonitor "wsname DP-1"
   hyprctl dispatch 'hl.dsp.exec_cmd("hyprctl dispatch moveworkspacetomonitor wsname DP-1")'
   ```

3. **Known native equivalents used in j0nix:**
   | Legacy | Lua Equivalent |
   |---|---|
   | `exit` | `hl.dsp.exit()` |
   | `dpms on` | `hl.dsp.dpms({state = "on"})` |
   | `workspace <name>` | `hl.dsp.focus({workspace = "<name>"})` |
   | `submap <name>` | `hl.dsp.submap("<name>")` |
   | `exec [workspace <n> silent] cmd` | `hl.dsp.exec_cmd("[workspace <n> silent] cmd")` |
   | `togglefloating` | `hl.dsp.window.float({action = "toggle"})` |
   | `resizewindowpixel exact W H` | `hl.dsp.window.resize({x = W, y = H})` |
   | `centerwindow` | manual: calc `(mon_w - win_w)/2` then `hl.dsp.window.move({x = cx, y = cy})` |
   | `killactive` | `hl.dsp.window.close()` |
   | `movefocus <dir>` | `hl.dsp.focus({direction = "<dir>"})` |
   | `fullscreen 0` | `hl.dsp.window.fullscreen({mode = "fullscreen", action = "toggle"})` |
   | `fullscreen 1` | `hl.dsp.window.fullscreen({mode = "maximized", action = "toggle"})` |

4. **Bootstrap contexts may still need legacy syntax:**
   The `exec = hyprctl dispatch submap global` line inside the Caelestia
   submap config block (`95-shell.conf`) runs through Hyprland's native
   config loader, not the Lua `dispatch` wrapper, so the legacy `submap`
   dispatcher is still correct there. Do not blindly migrate every
   `hyprctl dispatch` occurrence — evaluate whether the call site goes
   through the 0.55 Lua parser first.

## Storage Mounts

### Adding a declarative mount

Add an entry to `settings.nix` → `storage.systemMounts`:

```nix
{
  name = "my-data";
  enable = true;
  mountPoint = "/mnt/Data";
  device = "/dev/disk/by-uuid/XXXX-XXXX";
  fsType = "btrfs";
  options = [ "rw" "nofail" "noatime" "compress=zstd" ];
  gvfsShow = true;
  gvfsName = "MY DATA";
}
```

### Permission overrides vs read-only mounts  

When `group`, `mode`, `aclEntries`, or `defaultAclEntries` are set, a
`j0nix-mount-permissions-<path>.service` is generated that runs
`chown`/`chmod`/`setfacl` on the mount point.

⚠️ **Pitfall:** These services **always fail on read-only mounts**.
If `options` contains `"ro"`, remove all permission override fields or the
`nixos-rebuild switch` will abort with:

```
chown: changing group of '/mnt/...': Read-only file system
```

Either keep the mount `rw` and use permission overrides, or use `ro` and
drop them entirely. Do not mix.

## Desktop Application Extensions

### Old CMake compatibility

Some upstream projects (e.g. `nautilus-admin`) ship `cmake_minimum_required(VERSION 2.6)`,
which modern CMake rejects outright.

Fix by forcing policy minimum:
```nix
cmakeFlags = [
  "-DCMAKE_POLICY_VERSION_MINIMUM=3.5"
  # ... other flags ...
];
```

Also patch hardcoded `/usr/share/...` install paths to `$out/share/...` when
building extensions that install into application-specific directories.

## SOPS User Secrets

### Updating a password hash

1. Generate hash: `mkpasswd -m yescrypt`
2. Edit encrypted file: `sops secrets/users/<name>.yaml`
3. Replace `hashedPassword:` value
4. Rebuild system

Prerequisite: `sops` CLI and age private key (`~/.config/sops/age/keys.txt`)
on the current machine. If missing, install temporarily: `nix run nixpkgs#sops`.

## Per-process environment overrides (LD_PRELOAD tools)

When you need to fudge something the host kernel normally controls (clock, /dev/urandom, hostname, /etc/resolv.conf) for a single process tree — without touching the host — `LD_PRELOAD` an interception library. Pattern is:

```bash
LD_PRELOAD=/path/to/<lib>.so.1 <env-vars> <command>
```

Use case seen in j0nix-os:
- **Game time hacks** (No Man's Sky, etc.) — `libfaketime` + `FAKETIME=+4h`. See `references/libfaketime-game-time-hack.md` for the full wrapper pattern, Steam launch options integration, and the NixOS → Home Manager config-propagation pitfall.

## Low-latency streaming (Sunshine/Moonlight) on a bridged LAN

When a streaming host and its client share one L2 (e.g. both on the same
OPNsense bridge), keep mDNS discovery on exactly ONE interface of that L2 —
Avahi multi-homing on two interfaces of one bridge breaks client discovery
(duplicate conflicting records). After restarting avahi, restart Sunshine
too (user unit) or it loses its service registration. See
`references/sunshine-streaming-session-2026-09.md` for the full discovery fix,
the OPNsense REST firewall-automation recipe (flat-enum rule payloads,
snake_case endpoints, sloppy/no-state streaming rules), the
`security.wrappers` capability-string pitfall (`cap_from_text` accepts only
one flag group per string), and the NVENC API-version gate (driver 610+
needed for Sunshine 2026.906; KMD/UMD mismatch persists until reboot).

## Reference files

- `references/libfaketime-game-time-hack.md` — `libfaketime` wrapper pattern, Steam launch options integration, and the NixOS → Home Manager config-propagation pitfall when settings set in a profile module are not visible to consuming user modules.
- `references/sunshine-streaming-session-2026-09.md` — Sunshine discovery fix, OPNsense firewall REST automation, security-wrapper caps, NVENC driver-version gate.
