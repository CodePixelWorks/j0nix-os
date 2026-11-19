{
  config,
  lib,
  ...
}:
let
  cfg = config.j0nix.desktop.security.polkit;
in
{
  options.j0nix.desktop.security.polkit = {
    extraConfigSnippets = lib.mkOption {
      type = lib.types.listOf lib.types.lines;
      default = [ ];
      description = "Additional Polkit JS rule snippets to append when Polkit is enabled.";
    };

    adminIdentities = lib.mkOption {
      type = lib.types.nullOr lib.types.str;
      # Derive the admin identity from the primary account (first user
      # in settings.userSettings, always a wheel member via
      # accounts.baseExtraGroups). Pinning the primary user instead of
      # the whole wheel group keeps password prompts on the logged-in
      # account even when a second wheel account exists.
      default = let
        primary = config.j0nix.desktop.accounts.primaryUser or null;
      in if primary != null then "unix-user:${primary}" else null;
      example = "unix-user:jonas";
      description = ''
        Pin security.polkit.adminIdentities (default upstream:
        "unix-group:wheel"). With a second wheel account polkit agents
        may resolve the admin identity to that other account, so
        password prompts read "authenticating for unix-user:xin"
        instead of the logged-in user. Pin the primary user here.
      '';
    };
  };

  config = lib.mkIf config.security.polkit.enable {
    security.polkit.adminIdentities = lib.mkIf (cfg.adminIdentities != null) [ cfg.adminIdentities ];

    # Append snippets so rules from other modules remain intact.
    security.polkit.extraConfig = lib.mkAfter (lib.concatStringsSep "\n\n" cfg.extraConfigSnippets);
  };
}
