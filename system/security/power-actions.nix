{ lib, config, ... }:
let
  polkitRules = import ../lib/polkit-rules.nix { inherit lib; };
in
{
  config = lib.mkIf config.security.polkit.enable {
    # Allow local wheel users to trigger logind power actions without requiring
    # an interactive polkit prompt from the desktop shell.
    j0nix.desktop.security.polkit.extraConfigSnippets = [
      polkitRules.mkLoginPowerWheelRule
    ];
  };
}
