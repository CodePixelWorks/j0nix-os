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
- when Fusion is enabled for any user, j0nix enables `spacenavd` system-wide
  and installs the host-side command set expected by the upstream diagnostics
  (`bc`, `cabextract`, `curl`, `gawk`, `lsb_release`, `glxinfo`, `mokutil`,
  `7z`, `wbinfo`, `xrandr`, `xdg-open`, plus a compatibility `samba` wrapper)

### Default operator flow

The default j0nix mode now follows the upstream script more closely:

```bash
fusion360-setup
```

That uses the upstream admin-installer download path and keeps setup as an
explicit operator action instead of a login-time auto-setup job.

### Troubleshooting and logging

`fusion360-setup` now always writes an orchestration log to:

```bash
~/.autodesk_fusion/logs/fusion360-setup.log
```

For shell-level tracing of the wrapper and upstream steps:

```bash
FUSION360_SETUP_TRACE=1 fusion360-setup
```

That additionally writes:

```bash
~/.autodesk_fusion/logs/fusion360-setup-trace.log
```

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
