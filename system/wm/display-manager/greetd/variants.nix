{ lib, pkgs, settings }:
let
  regreetPackage = if pkgs ? regreet then pkgs.regreet else pkgs.greetd.regreet;
  keyboardLayout = settings.keyboardLayout or "de";
  keyboardOptions = settings.keyboardOptions or "caps:escape";
  xkbEnv = "${pkgs.coreutils}/bin/env XKB_DEFAULT_LAYOUT=${lib.escapeShellArg keyboardLayout}"
    + " XKB_DEFAULT_OPTIONS=${lib.escapeShellArg keyboardOptions}";
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
        "${xkbEnv} ${lib.getExe pkgs.cage} -s -mlast -- ${lib.getExe regreetPackage}";
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
        "${xkbEnv} ${lib.getExe pkgs.cage} -s -mlast -- ${lib.getExe package} -c ${lib.escapeShellArg configPath}";
  };

  dmsGreeter = { command }: {
    user = "greeter";
    inherit command;
  };
}
