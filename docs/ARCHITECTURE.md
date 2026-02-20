# j0nix-os Architecture

This document describes how `j0nix-os` is structured, how settings flow through the flake, and how runtime session selection works.

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
  B --> C[mkUserSettings for each user]
  C --> D[home-manager modules per user]
  B --> E[systemSettings aggregate]
  E --> F[nixosSystem profiles/<profile>/configuration.nix]
  D --> G[homeConfigurations.<user>]
  F --> H[nixosConfigurations.<hostname>]
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
  A[settings.users] --> B[users.users.<name> in system config]
  A --> C[home-manager.users.<name>]
  D[userSettings.<name>] --> B
  D --> C
  B --> E[login shell + unix groups]
  C --> F[per-user WM/editor/browser/shell config]
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
  F -->|darkmaterialshell| I[dank-material-shell greeter module]
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
  participant GR as Greeter (tuigreet/regreet/DMS greeter)
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
  else greeter = darkmaterialshell
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
  D[userSettings.<name>.hyprlandShell] --> E[user/wm/hyprland/default.nix]
  E --> F{shellStartupCommand}
  F -->|ags| G[ags]
  F -->|dank-material-shell| H[dms run]
  F -->|noctalia-shell| I[noctalia-shell]
```

## Gaming and Dev Stacks

```mermaid
flowchart LR
  A[settings.gaming] --> B[system/gaming/*]
  A --> C[user/gaming/*]
  D[settings.dev] --> E[system/dev/default.nix]
  D --> F[user/dev/*]
  G[settings.sysctlProfiles] --> H[system/tuning/sysctl/default.nix]
```

## Driver Stack

Drivers are controlled centrally via `settings.drivers.*` and applied in `system/drivers/*`.

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
  - `system/wm/<name>.nix`
  - `user/wm/<name>/default.nix` (optional)
- Add a new Hyprland shell:
  - `user/wm/hyprland/shells/<shell>/default.nix`
  - expose name via `settings.hyprlandShell` or `userSettings.<name>.hyprlandShell`
- Add a new feature domain:
  - `system/<domain>/...`
  - `user/<domain>/...`
  - toggle from `settings.nix`

## Operational Notes

- Evaluate safely:
  - `nix flake check --no-build`
- Build/apply:
  - `sudo nixos-rebuild switch --flake /home/<user>/nixos-dotfiles/j0nix-os#<hostname>`
- Prefer changing behavior through `settings.nix` first, then module code.
