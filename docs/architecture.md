# j0nix-os Architecture

This document describes how `j0nix-os` is structured, how settings flow through the flake, and how runtime session selection works.

Related deep dives:

- [QMLGreet Integration](./wm/qmlgreet.md)

## Design Goals

- Independent codebase (no local imports from sibling reference projects)
- Strong module boundaries (`profiles`, `system`, `user`)
- Multi-user by default with per-user overrides
- Hyprland-first but desktop-manager/session flexible
- Gaming and development as composable feature stacks

## High-Level Build Graph

```mermaid
flowchart TD
  A[settings.nix] --> B[flake.nix]
  B --> |mkNixosSystem<br>{ profileName = "desktop"; hostname = "Jonas-PC"; }| C[nixosSystem profiles/<profile>/configuration.nix]
  C --> D[nixosConfigurations.<hostname>]
  B --> |mkHomeManagerConfiguration| E[mkUserSettings per user]
  E --> F[home-manager modules per user]
  F --> G[homeConfigurations."user@hostname"]
```

## Module Layers

```mermaid
flowchart LR
  A[profiles/desktop] --> B[system/*]
  A --> C[user/* via home-manager]
  B --> D[system/wm]
  B --> E[system/gaming]
  B --> F[system/dev]
  B --> G[system/tuning]
  B --> H[system/drivers]
  C --> I[user/wm]
  C --> J[user/editors]
  C --> K[user/shells]
  C --> L[user/programs]
  C --> M[user/dev]
  C --> N[user/gaming]
```

## Settings Resolution

`flake.nix` merges:

1. Base settings from `settings.nix`
2. Per-user overrides from `userSettings.<name>`
3. Derived theme/profile details

This gives one resolved settings object per user.

```mermaid
flowchart TD
  A[settings.nix base] --> D[merge]
  B[userSettings.jonas] --> D
  C[theme/profile details] --> D
  D --> E[resolved user settings]
  E --> F[user module imports]
```

## Multi-User Model

```mermaid
flowchart TD
  A[settings.userSettings.<name>] --> B[users.users.<name>]
  A --> C[home-manager.users.<name>]
  B --> D[login shell + unix groups]
  C --> E[per-user WM/editor/browser/shell config]
```

## Display Manager and Session Flow

```mermaid
flowchart TD
  A[settings.displayManager] --> B{DM}
  B -->|sddm| C[services.displayManager.sddm]
  B -->|gdm| D[services.xserver.displayManager.gdm]
  B -->|greetd| E[services.greetd]
  E --> F{settings.greetd.greeter}
  F -->|tuigreet| G[tuigreet command]
  F -->|regreet| H[regreet with cage/hyprland]
  F -->|qmlgreet| I[qmlgreet with cage/hyprland]
  F -->|dms-greeter| J[dank-material-shell greeter module]
```

## Runtime Login Sequences

### SDDM -> Hyprland -> User Shell

```mermaid
sequenceDiagram
  actor U as User
  participant DM as SDDM
  participant DS as Session Resolver
  participant HY as Hyprland
  participant HM as Home Manager User Profile
  participant SH as Shell Process (AGS/DMS/Noctalia)

  U->>DM: Login (username + password)
  DM->>DS: Resolve session (.dmrc or DM default)
  alt useUWSM = true
    DS->>HY: Start hyprland-uwsm
  else useUWSM = false
    DS->>HY: Start hyprland
  end
  HY->>HM: Apply per-user HM config
  HM->>HY: exec-once startup entries
  HY->>SH: Start selected shell startup command
  SH-->>U: Desktop shell becomes active
```

### Greetd -> Greeter -> Hyprland Session

```mermaid
sequenceDiagram
  actor U as User
  participant G as greetd
  participant GR as Greeter (tuigreet/regreet/qmlgreet/DMS greeter)
  participant HY as Hyprland Session
  participant HM as Home Manager User Profile
  participant SH as Shell Process (AGS/DMS/Noctalia)

  G->>GR: Launch configured greeter
  U->>GR: Authenticate + pick session
  alt greeter = tuigreet and useUWSM = true
    GR->>HY: uwsm start hyprland-uwsm.desktop
  else greeter = tuigreet and useUWSM = false
    GR->>HY: start Hyprland
  else greeter = regreet
    GR->>HY: start-hyprland (or cage+regreet path)
  else greeter = qmlgreet
    GR->>HY: start-hyprland (or cage+qmlgreet path)
  else greeter = dms-greeter
    GR->>HY: DMS greeter compositor path
  end
  HY->>HM: Load user home-manager config
  HM->>HY: Apply Hyprland user settings
  HY->>SH: Run shell startup command
  SH-->>U: Session ready
```

## Hyprland + UWSM + Shell Selection

```mermaid
flowchart TD
  A[settings.hyprland.useUWSM] --> B[programs.hyprland.withUWSM]
  A --> C[default session name]
  D[userSettings.<name>.wmShell] --> E[user/wm/hyprland/default.nix]
  E --> F{shellStartupCommand}
  F -->|ags| G[ags]
  F -->|caelestia-shell| H[caelestia-shell]
  F -->|dank-material-shell| I[dms run]
  F -->|noctalia-shell| J[noctalia-shell]
```

## Gaming and Dev Stacks

```mermaid
flowchart LR
  A[profiles/desktop/modules/gaming.nix -> j0nix.desktop.gaming] --> B[system/gaming/*]
  A --> C[user/gaming/*]
  D[settings.dev] --> E[system/dev/default.nix]
  D --> F[user/dev/*]
  G[settings.sysctlProfiles] --> H[system/tuning/sysctl/default.nix]
```

## Driver Stack

Drivers are controlled centrally via `settings.drivers.*` and applied in `nix/system/drivers/*`.

```mermaid
flowchart TD
  A[settings.drivers.amdgpu] --> B[amd-drivers.nix]
  C[settings.drivers.intel] --> D[intel-drivers.nix]
  E[settings.drivers.nvidia] --> F[nvidia-drivers.nix]
  G[settings.drivers.nvidiaPrime] --> H[nvidia-prime-drivers.nix]
  I[settings.drivers.vmGuestServices] --> J[vm-guest-services.nix]
  K[settings.drivers.hardwareClockLocalTime] --> L[local-hardware-clock.nix]
```

## Key Extension Points

- Add a new desktop module:
  - `nix/system/wm/<name>.nix`
  - `nix/user/wm/<name>/default.nix` (optional)
- Add a new Hyprland shell:
  - `nix/user/wm/hyprland/shells/<shell>/default.nix`
  - expose name via `userSettings.<name>.wmShell` (legacy alias: `hyprlandShell`)
- Add a new feature domain:
  - `nix/system/<domain>/...`
  - `nix/user/<domain>/...`
  - toggle from `settings.nix`

## Operational Notes

- Evaluate safely:
  - `nix flake check --no-build`
- Build/apply:
  - `sudo nixos-rebuild switch --flake /home/<user>/nixos-dotfiles/j0nix-os#<hostname>`
- Prefer changing behavior through `settings.nix` first, then module code.
