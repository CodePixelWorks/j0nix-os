# User Roles

Role modules are workload/purpose-oriented building blocks (e.g. `gaming`, `developer`, `office`, `remote-work`, `video-editing`, `3d-creation`).

## Naming

- Use English `kebab-case` role names.
- Prefer purpose/workflow names over tool names (e.g. `video-editing` instead of `davinci`).
- Keep host/hardware concerns in `profiles/*`, not roles.

- `user-roles/system/*.nix`: system-side role effects (sysctl fragments, system packages, services)
- `user-roles/home/*.nix`: Home Manager role effects (home packages, user config)

Users can enable multiple roles via `settings.userSettings.<name>.roles = [ ... ];`.

Recommended modern baseline roles:
- `developer`
- `gaming`
- `office`
- `remote-work`
- `video-editing`
- `3d-creation`

Roles should append into central aggregators (e.g. `j0nix.software.*`, `j0nix.user.software.*`, `j0nix.desktop.sysctl.extraFragments`) instead of writing directly to final package/sysctl outputs.
