{ settings, ... }:
{
  # Transitional bridge: move host gaming policy out of `settings.nix` into this profile.
  # Consumers will be migrated from `settings.gaming` to `j0nix.desktop.gaming` in follow-up scopes.
  j0nix.desktop.gaming = settings.gaming or { };
}
