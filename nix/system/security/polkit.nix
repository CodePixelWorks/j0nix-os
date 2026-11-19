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
      # Workstation default: pin to the primary user (jonas) so password
      # prompts never name the second wheel account ("xin").
      default = "unix-user:jonas";
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
