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
- multiple isolated instances via Element's `--profile` flag
- a launcher selection menu for configured instances
- optional default homeserver / identity server preconfiguration
- optional SSO redirect for unauthenticated users
- a wrapped launcher that forces `--password-store=gnome-libsecret` so Electron uses the Secret Service backend reliably on this setup

Profile notes:
- `profiles = [{ id = "default"; profile = null; ... }]` keeps using the normal Element profile
- `profiles = [{ id = "work"; profile = "Work"; ... }]` launches `element-desktop --profile Work`
- when several profiles are configured, the `element-desktop` desktop launcher opens a selector first
- direct CLI flags are passed through unchanged, so `element-desktop --profile Work` still works

Important limitation:
- safe declarative "username/password autologin" is not supported
- the supported production path is Element's normal session persistence
- if your homeserver uses SSO, `autoLogin.ssoRedirect = true` can skip the manual login picker and redirect unauthenticated users straight into SSO

`Windows EXE` integration is configured via `settings.programs.windowsExe.*` and provides:
- a managed default Bottles bottle (`winexe-prefix-init`)
- the nixpkgs `bottles` runtime for Windows application execution
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

`Autodesk Fusion` is configured via `settings.programs.autodeskFusion.*` and uses the maintained Lolig4 installer flow. The default `fusion-wine` runner installs a separate prefix in `~/.local/share/Autodesk-Unofficial`; the former `~/.autodesk_fusion` prefix is intentionally left untouched as a rollback source.

- `autodesk-fusion-install` creates a new Fusion prefix with Lolig4's patched Wine runner, DXVK/VKD3D, corrected Visual C++ override, and Wine-DX9 sidebar override.
- `autodesk-fusion-repair` creates another clean, parallel prefix rather than mutating a potentially broken installation.
- `autodesk-fusion` is a j0nix-owned launcher. It reads Lolig4's active-prefix contract but does not execute the mutable installer launcher.
- `autodesk-fusion-adskidmgr` delegates `adskidmgr:` callbacks to Lolig4's opener.
- `autodesk-fusion-renderer` is retained only for legacy-prefix diagnosis; the maintained flow selects its renderer during prefix creation.

The patched `fusion-wine` runner is required with modern Wine versions: upstream documents a black/white 3D canvas regression in Wine 11.11+ and includes the canvas plus owned-tool-window fixes in this runner. Its Wine-DX9 override for `AdCefWebBrowser.exe` is the corresponding sidebar/navigation fix.

The managed launcher preserves Lolig4's split renderer policy: DXVK/D3D11 renders the 3D canvas, while OpenGL renders Fusion's Qt/Chromium shell. Fusion can overwrite the shell setting with D3D11 in its roaming profile; the launcher restores the upstream OpenGL value before each start to avoid black panels.

The Autodesk payload, runner archive, WebView2 runtime, and license/session data are mutable user state. They are fetched only when the install or repair command is explicitly run, never during Nix evaluation.

### Fusion sign-in on Hyprland

Current Fusion builds authenticate through a top-level Wine/Xwayland window backed by Microsoft Edge WebView2. They do not reliably launch the system browser. The `adskidmgr` XDG handler remains necessary for a callback when Fusion does use an external flow, but it must not be treated as the primary sign-in launcher.

The managed Hyprland rule matches `fusion360.exe` with the title `Anmelden - Autodesk Fusion`, then floats and centers it. This keeps the login visible on the workspace where Fusion was started. Do not add `FUSION_IDSDK=false`: that was an old workaround for the retired login path and current Fusion versions ignore it while still starting the Identity Manager.

If sign-in appears stuck:

- Run `autodesk-fusion-doctor` and confirm WebView2 and the `adskidmgr` handler are present.
- Check `hyprctl -j clients` for `fusion360.exe` or `adskidentitymanager.exe`; the login dialog may be on the launch workspace.
- Close all Fusion, Identity Manager, WebView2, and Wine processes for this prefix before retrying, so an old instance cannot retain the login session.

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
