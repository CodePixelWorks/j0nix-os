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
Its payloads can now be sourced in four ways under `settings.programs.fusion360.protonInstaller.payloads.*`:
- `manual`: run `fusion360-setup /path/to/installer.exe` and provide the proprietary installer explicitly
- `runtime-download`: keep the current first-run download behavior
- `fetchurl`: pin the installer as a fixed-output Nix artifact with `url` + `hash`
- `requireFile`: require a locally supplied proprietary installer file with `fileName` + `hash`
The default j0nix path is now `manual`, so Fusion setup is an explicit operator action instead of an automatic login-time job.

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
