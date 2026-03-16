# User Program Modules

Common user program configs shared across shells/WMs.

## Files

- `default.nix`: aggregation entrypoint
- `alacritty/default.nix`
- `betterdiscord/default.nix`
- `element-desktop/default.nix`
- `fastfetch/default.nix`
- `keepassxc/default.nix`
- `windows-apps/default.nix`
- `windows-apps/packages/*.nix`
- `windows-exe/default.nix`
- `wlogout/default.nix`

Program toggles should be wired through `settings.programs.*`.

`AAGL GTK on Nix` is configured via `settings.programs.aagl.*` and imports the upstream NixOS module from `ezKEa/aagl-gtk-on-nix`. The j0nix contract controls whether the launcher bundle is enabled at all and which launcher frontends are installed:
- `animeGame`
- `animeGames`
- `honkers`
- `honkersRailway`
- `sleepy`
- `wavey`

`Element Desktop` (Matrix client) is configured via `settings.userSettings.<name>.programs.elementDesktop.*` and supports:
- declarative package installation
- a managed `~/.config/Element/config.json`
- optional default homeserver / identity server preconfiguration
- optional SSO redirect for unauthenticated users
- a wrapped launcher that forces `--password-store=gnome-libsecret` so Electron uses the Secret Service backend reliably on this setup

Important limitation:
- safe declarative "username/password autologin" is not supported
- the supported production path is Element's normal session persistence
- if your homeserver uses SSO, `autoLogin.ssoRedirect = true` can skip the manual login picker and redirect unauthenticated users straight into SSO

`Windows EXE` integration is configured via `settings.programs.windowsExe.*` and provides:
- a managed default Bottles bottle (`winexe-prefix-init`)
- the patched `bottles-j0nix` runtime for consistent runner execution
- optional preferred runner pin (`runner = "kron4ek-wine-11.2-amd64"`)
- automatic bottle creation plus j0nix template seeding for first use
- optional auto-bootstrap service on login (`autoBootstrapOnLogin = true`)
- periodic retry timer (`winexe-bottle-bootstrap.timer`) to ensure the default bottle is eventually created
- optional suppression of Bottles sandbox warning popup (`removeWarningPopup = true`)
- `winexe-run <file.exe|file.msi>` helper
- optional default MIME handler for `.exe`/`.msi` style payloads

Note: Bottles component downloads are runtime/user-state operations and are not part of deterministic Nix build steps.
`winexe-run` uses `bottles-cli run` with an absolute executable path and the configured default bottle/runner.
New j0nix-managed bottles are seeded from a Nix-generated template after creation. Existing unmanaged default bottles are migrated once by merging a curated set of safe runtime fields while preserving installed programs, dependencies and other bottle state.

`Windows app packages` are configured via `settings.userSettings.<name>.programs.windowsApps.packages = [ ... ];`.
The infrastructure separates:
- immutable Nix-managed runtime/payload artifacts
- per-app desktop entries and MIME handlers
- minimal user-session provisioning for mutable bottle/prefix state

Current first-party package:
- `fusion360-proton`

`Fusion 360` remains a managed exception: installer/runtime wrappers are declarative, but Proton/Wine prefix creation and Autodesk login state are user-state and therefore provisioned via user systemd, not built into the Nix store.
The current setup path is intentionally based on the upstream `cryinkfly/Autodesk-Fusion-360-on-Linux` installer project:
- Project: `https://codeberg.org/cryinkfly/Autodesk-Fusion-360-on-Linux`
- Upstream setup script: `files/setup/autodesk_fusion_installer_x86-64.sh`
- j0nix vendors that script as a fetched artifact and drives its install functions from a local wrapper instead of maintaining a separate installer implementation.

Important upstream behavior we currently rely on:
- it creates the Fusion data structure under the selected install root
- it downloads the tested helper payloads itself (`winetricks`, `WebView2`, patched `Qt6WebEngineCore.dll`, patched `siappdll.dll`, launcher assets, optional extensions)
- it applies the known post-install DLL patches and desktop launcher generation
- it supports both plain Wine and Steam-Proton execution modes

Local j0nix deviations from upstream:
- package-manager mutations from the upstream script are disabled; Nix provides the runtime dependencies instead
- the setup wrapper may stage a manually supplied Autodesk installer EXE into the managed install root before invoking the upstream flow
- the known `Fusion Client Downloader.exe` bootstrapper is rejected; the supported manual payload is the real admin installer
- the setup wrapper does not auto-open the upstream partner page or auto-launch Fusion at the end of installation

Its payloads can now be sourced in four ways under `settings.programs.fusion360.protonInstaller.payloads.*`:
- `manual`: run `fusion360-setup /path/to/Fusion\ Admin\ Install.exe`; absolute and relative paths are both supported. The wrapper validates that the argument is a Windows `.exe`, rejects the known `Fusion Client Downloader.exe` bootstrapper, stages the accepted installer into the managed Fusion install root, records a SHA256 manifest, and only then continues with setup
- `runtime-download`: follow the upstream default and let the setup wrapper download the Autodesk admin installer itself
- `fetchurl`: pin the installer as a fixed-output Nix artifact with `url` + `hash`
- `requireFile`: require a locally supplied proprietary installer file with `fileName` + `hash`
The default j0nix path is now `runtime-download`, but setup is still an explicit operator action. j0nix does not auto-run the Fusion installer on login.

`KeePassXC` is user-scoped via `settings.userSettings.<name>.programs.keepassxc.*` and supports:
- optional autostart
- optional startup database path
- optional secret-backed key file deployment (`keyFileSecretName`)
- optional workspace integration (`workspace.mode = special-workspace|minimizer`)
- optional unlock modes (`autoUnlock.mode = strict|balanced|convenient|full-auto`)
- autostart via user systemd (`graphical-session.target`), which is reliable on Hyprland

Installed helper commands:
- `keepassxc-startup`: start KeePassXC with configured unlock/workspace behavior
- `keepassxc-toggle`: toggle Keepass visibility (special workspace or minimizer mode)
- `keepassxc-doctor`: print effective runtime checks (db/keyfile/keyring/secret)
- `keepassxc-secret-set [entry]`: store KeePass database password in keyring for convenient mode

If `settings.userSettings.<name>.hyprland.minimizer.enable = true` and `workspace.mode = \"minimizer\"`,
KeePassXC startup prefers the minimizer workflow over `--minimized`.
