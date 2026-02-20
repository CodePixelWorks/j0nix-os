# System Modules

System-level NixOS modules, imported from the selected profile.

## Structure

- `wm/`: display manager + window manager system modules
- `gaming/`: Steam/Proton/performance/controller system config
- `dev/`: Docker/build tooling
- `tuning/`: sysctl and kernel/userland tuning
- `drivers/`: GPU/guest/clock driver stack

## Rule

Behavior should be controlled via `settings.nix` switches, not hardcoded per host.
