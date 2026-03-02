{ lib }:
let
  validDisplayManagers = [ "greetd" "sddm" "gdm" ];
  validGreetdGreeters = [ "tuigreet" "regreet" "dms-greeter" ];
  validRegreetCompositors = [ "cage" "hyprland" ];
in
{
  inherit validDisplayManagers validGreetdGreeters validRegreetCompositors;

  resolveDisplayManager = settings:
    settings.displayManager or "sddm";

  resolveGreetdGreeter = settings:
    let
      raw = (settings.greetd or { }).greeter or "tuigreet";
    in
    if raw == "darkmaterialshell" then "dms-greeter" else raw;

  resolveRegreetCompositor = settings:
    (settings.greetd or { }).regreetCompositor or "hyprland";
}
