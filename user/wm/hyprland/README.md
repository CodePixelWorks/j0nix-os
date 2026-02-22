# User Hyprland Module

Main user-side Hyprland module (`default.nix`) plus shell-specific variants.

## Core Responsibilities

- base Hyprland settings
- startup command dispatch (`noctalia-start`/AGS always, `dms-start` only when `settings.dms.startup.mode = "exec-once"`)
- debug quickshell guard handling

## Shell Selection

Modules under `shells/` are selected by global `wmShell` (legacy alias: `hyprlandShell`).

## Hyprland Rule Syntax Notes (0.53.2+)

- Older window rule syntax is parsed much more strictly.
- `windowrulev2`-style configs from older dotfiles may fail hard.
- `windowrule` rules require explicit values for flags (for example `float 1`, `center 1`).
- Use snake_case fields (`no_blur`, `initial_title`).
- `idleinhibit` window rule was removed; configure idle behavior via `hypridle`.
