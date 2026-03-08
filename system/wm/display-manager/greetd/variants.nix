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

  qmlgreet = {
    package,
    compositor,
    configPath,
    hyprlandCommand ? null,
  }: {
    user = "greeter";
    command =
      if compositor == "hyprland" then
        hyprlandCommand
      else
        "${lib.getExe pkgs.cage} -s -mlast -- ${lib.getExe package} -c ${lib.escapeShellArg configPath}";
  };

  dmsGreeter = { command }: {
    user = "greeter";
    inherit command;
  };
}
