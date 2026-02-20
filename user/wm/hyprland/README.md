# User Hyprland Module

Main user-side Hyprland module (`default.nix`) plus shell-specific variants.

## Core Responsibilities

- base Hyprland settings
- startup command dispatch (`dms-start`, `noctalia-start`, or AGS)
- debug quickshell guard handling

## Shell Selection

Modules under `shells/` are selected by `hyprlandShell` in resolved user settings.
