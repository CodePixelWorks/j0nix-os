# User Hyprland Module

Main user-side Hyprland module (`default.nix`) plus shell-specific variants.

## Core Responsibilities

- base Hyprland settings
- startup command dispatch (`noctalia-start`/AGS always, `dms-start` only when `settings.dms.startup.mode = "exec-once"`)
- debug quickshell guard handling

## Shell Selection

Modules under `shells/` are selected by global `wmShell` (legacy alias: `hyprlandShell`).
