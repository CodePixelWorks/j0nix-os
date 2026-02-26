# User Roles

Role modules are workload-oriented building blocks (e.g. `gaming`, `dev`, `videocutter`, `3dengineer`).

- `user-roles/system/*.nix`: system-side role effects (sysctl fragments, system packages, services)
- `user-roles/home/*.nix`: Home Manager role effects (home packages, user config)

Users can enable multiple roles via `settings.userSettings.<name>.roles = [ ... ];`.

Roles should append into central aggregators (e.g. `j0nix.software.*`, `j0nix.desktop.sysctl.extraFragments`) instead of writing directly to final package/sysctl outputs.
