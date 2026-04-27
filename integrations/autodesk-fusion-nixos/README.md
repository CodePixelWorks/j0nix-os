# Autodesk Fusion for NixOS

This integration packages the Linux-side runtime helpers for Autodesk Fusion on
Linux. It does not redistribute Autodesk Fusion and does not place Autodesk's
stateful Windows installation in the Nix store.

## Design

- The Nix package contains launch, install, diagnostic, and URL-handler tools.
- User state lives outside the Nix store, by default in
  `$XDG_DATA_HOME/autodesk-fusion` or `$HOME/.local/share/autodesk-fusion`.
- Home Manager owns desktop entries and the `adskidmgr:` URL handler needed for
  Autodesk login callbacks.
- The installer never uses `sudo`, `pkexec`, or `nix-env`; dependencies must be
  supplied declaratively.

## Commands

- `fusion360-install`: create/update the Wine prefix and install Fusion.
- `fusion360-launch`: launch Fusion from the active prefix.
- `fusion360-url-handler`: handle `adskidmgr:` login callback URLs.
- `fusion360-doctor`: check the local installation and desktop integration.
- `fusion360-fix-navbar`: apply the optional NavToolbar visibility workaround.

## Home Manager

```nix
programs.autodeskFusion = {
  enable = true;
  desktopEntry.enable = true;
  urlHandler.enable = true;
};
```

## Notes

Fusion requires an Autodesk account/license and downloads Autodesk's Windows
installer at setup time. Use `fusion360-doctor` after installation to verify the
prefix, launch target, and URL handler.
