# User Program Modules

Common user program configs shared across shells/WMs.

## Files

- `default.nix`: aggregation entrypoint
- `alacritty/default.nix`
- `betterdiscord/default.nix`
- `element-desktop/default.nix`
- `fastfetch/default.nix`
- `keepassxc/default.nix`
- `autodesk-fusion/default.nix`
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

`Autodesk Fusion` is configured via `settings.programs.autodeskFusion.*` and provides a managed Wine runtime environment for the cryinkfly installer:
- `autodesk-fusion-install` downloads and runs the upstream installer into user state (`~/.autodesk_fusion` by default)
- `autodesk-fusion-repair` reruns the patched install-fix path
- `autodesk-fusion` launches the installed Fusion prefix through Xwayland-oriented environment defaults
- `autodesk-fusion-doctor` checks Wine, DXVK/Vulkan, prefix paths, WebView2, and the `adskidmgr` login URL handler

The Autodesk payload, WebView2 runtime, cryinkfly installer payloads, and license/session data are runtime user state and are not fetched during Nix evaluation or vendored into the Nix store.

`Windows app packages` are configured via `settings.userSettings.<name>.programs.windowsApps.packages = [ ... ];`.
The infrastructure separates:
- immutable Nix-managed runtime/payload artifacts
- per-app desktop entries and MIME handlers
- minimal user-session provisioning for mutable bottle/prefix state

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
