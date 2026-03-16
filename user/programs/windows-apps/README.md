# Windows Apps

## Fusion 360

`fusion360-proton` is currently implemented as a thin j0nix wrapper around the
upstream `cryinkfly/Autodesk-Fusion-360-on-Linux` project:

- Project: `https://codeberg.org/cryinkfly/Autodesk-Fusion-360-on-Linux`
- Upstream setup script:
  `https://codeberg.org/cryinkfly/Autodesk-Fusion-360-on-Linux/raw/branch/main/files/setup/autodesk_fusion_installer_x86-64.sh`

### What j0nix reuses from upstream

- creation of the Fusion install root layout
- WebView2 download/install
- patched `Qt6WebEngineCore.dll`
- patched `siappdll.dll`
- upstream launcher script generation
- upstream desktop-file generation
- optional Steam-Proton install mode

### What j0nix overrides locally

- no package-manager mutations from the upstream script
- no automatic Wine installation from the upstream script
- no partner-page browser open after setup
- no auto-launch of Fusion after setup
- optional manual staging of a supplied Autodesk installer EXE before the
  upstream flow starts

### Manual installer requirement

For the manual path, use the real Autodesk admin installer:

```bash
fusion360-setup /path/to/Fusion\ Admin\ Install.exe
```

Do not use:

```bash
Fusion Client Downloader.exe
```

That file only bootstraps the webdeploy launcher and does not produce a full
`Fusion360.exe` installation in the managed prefix.
