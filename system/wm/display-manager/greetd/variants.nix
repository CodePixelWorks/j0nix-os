{ lib, pkgs }:
let
  regreetPackage = if pkgs ? regreet then pkgs.regreet else pkgs.greetd.regreet;
in
{
  tuigreet = { user, sessionCommand }: {
    inherit user;
    command = "${lib.getExe pkgs.tuigreet} --time --cmd ${lib.escapeShellArg sessionCommand}";
  };

  regreet = { compositor, hyprlandCommand ? null }: {
    user = "greeter";
    command =
      if compositor == "hyprland" then
        hyprlandCommand
      else
        "${lib.getExe pkgs.cage} -s -mlast -- ${lib.getExe regreetPackage}";
  };

  dmsGreeter = { command }: {
    user = "greeter";
    inherit command;
  };
}
