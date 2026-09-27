# Autodesk Fusion: reproducible native-Wayland setup

Status: 2026-09-27

## Supported result

Jonas-PC uses the Lolig4 installer with CachyOS WineWayland Proton. Fusion starts as a native Wayland client (`PROTON_ENABLE_WAYLAND=1`), the Autodesk browser login returns to the running Identity Manager, and the managed j0nix launcher is the only supported entry point.

The setup is operationally reproducible: Nix declares the runtime, runner name, launcher, URI handler, GPU environment and Hyprland rules. A fresh prefix is created by `autodesk-fusion-install`; no old prefix is reused.

It is not a fully hermetic Nix build. Autodesk's payload, WebView2 and the custom Proton runner are downloaded at install time. The Lolig4 installer is pinned by SHA-256; an upstream change fails closed until `settings.programs.autodeskFusion.installerSha256` is intentionally reviewed and updated.

## Configuration contract

The source of truth is `settings.nix`:

```nix
settings.programs.autodeskFusion = {
  enable = true;
  installerMode = "proton";
  protonVersion = "cachyos-wineland-11.0-Fusion";
  installerSha256 = "...";
  virtualDesktop = false;
  noWmDecoration = true;
};
```

Implementation: `nix/user/programs/autodesk-fusion/default.nix`. Window rules: `nix/user/wm/hyprland/config/window-rules.nix`. NixOS `nix-ld` supplies the required i686 loader at `/lib/ld-linux.so.2`.

## Fresh installation

1. Apply the NixOS configuration.

   ```bash
   sudo nixos-rebuild switch --flake .#Jonas-PC
   ```

2. Ensure Steam is installed and has initialized its user directory. The Lolig4 installer obtains the named compatibility tool in Steam's `compatibilitytools.d` when necessary.

3. Create a clean parallel prefix.

   ```bash
   autodesk-fusion-install
   ```

4. Verify the active prefix, runner, WebView2, Vulkan and URI handler.

   ```bash
   autodesk-fusion-doctor
   ```

5. Start only through the managed desktop entry or command.

   ```bash
   autodesk-fusion
   ```

Never start the upstream `autodesk_fusion_launcher.sh` directly. Home Manager removes its duplicate desktop files and owns the canonical Fusion launcher and `adskidmgr:` handler.

## Login flow

The launcher starts Autodesk Identity Manager first, waits for its exact `SSO Server is ready` event, then starts Fusion. Fusion opens the system browser. The browser invokes `autodesk-fusion-adskidmgr.desktop` for the `adskidmgr:` callback.

Fusion runs inside `steam-run` for its FHS/Vulkan runtime and therefore has a private `/tmp`. The callback handler bridges only the live Wine SSO socket into a short-lived host-side Wine invocation, allowing the code to reach the already running Fusion instance. Do not copy OAuth URLs, codes, account addresses or session data into shell history, documentation, issues or commits.

## Window and menu behaviour

- Main Fusion window: native Wayland and kept out of compositor fullscreen.
- `Marking Menu`: a separate monitor-sized transparent WineWayland surface, not a second Fusion process.
- Hyprland disables blur and its border for that client (`no_blur`, `border_size = 0`).
- `PROTON_NO_WM_DECORATION=1` is enabled because it makes menu interaction work. It may leave a Wine-style client border; that border is not drawn by Hyprland.
- Wine virtual desktop was tested and is disabled; it does not contain Fusion's marking-menu surface.

## Repair and diagnostics

Save work, then use:

```bash
autodesk-fusion-kill
autodesk-fusion-repair
autodesk-fusion-doctor
```

Repair creates a fresh parallel prefix and updates the active-prefix contract; it does not mutate the current prefix in place. The doctor reads that contract and checks the selected Proton runner, rather than assuming the retired `wineprefixes` layout.

Record the installed runner build when debugging:

```bash
cat "$HOME/.local/share/Steam/compatibilitytools.d/cachyos-wineland-11.0-Fusion/version"
```

## Known limits and revalidation

Native WineWayland remains experimental. The Fusion marking menu is still a separate overlay, although it is usable with the managed rules. Autodesk may change payloads, login services or runner distribution; after a fresh installation run the doctor and one interactive login.

Before declaring a reinstall successful, confirm:

- `nix flake check --no-build` passes.
- Doctor reports the active Proton prefix and runner.
- `hyprctl clients -j` reports `xwayland: false` for Fusion.
- System-browser login returns to Fusion.
- 3D viewport, cloud sidebar and marking-menu input are usable.
