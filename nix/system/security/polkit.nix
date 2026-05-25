{ config, lib, ... }:
let
  cfg = config.j0nix.desktop.security.polkit;
in
{
  options.j0nix.desktop.security.polkit.extraConfigSnippets = lib.mkOption {
    type = lib.types.listOf lib.types.lines;
    default = [ ];
    description = "Additional Polkit JS rule snippets to append when Polkit is enabled.";
  };

  config = lib.mkIf (config.security.polkit.enable && cfg.extraConfigSnippets != [ ]) {
    # Append snippets so rules from other modules remain intact.
    security.polkit.extraConfig = lib.mkAfter (lib.concatStringsSep "\n\n" cfg.extraConfigSnippets);
  };
}
