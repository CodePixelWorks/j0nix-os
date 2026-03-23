{
  lib,
  pkgs,
  hyprlandCfg,
}:
let
  minimizerCfg = hyprlandCfg.minimizer or { };
  minimizerVariant = minimizerCfg.variant or "denis";
  minimizerIsDenis = minimizerVariant == "denis";
  minimizerIsOrteip = minimizerVariant == "0rteip";
  minimizerPackage =
    if minimizerIsOrteip then
      if pkgs ? "hyprland-minimizer-orteip" then pkgs."hyprland-minimizer-orteip" else null
    else if pkgs ? "hyprland-minimizer" then
      pkgs."hyprland-minimizer"
    else
      null;
  minimizerDefaultCommand =
    if minimizerPackage != null then
      lib.getExe minimizerPackage
    else if minimizerIsOrteip then
      "hyprland-minimizer"
    else
      "hyprland-minimizer";
  minimizerCommand = minimizerCfg.command or minimizerDefaultCommand;
  minimizerOrteipCfg = minimizerCfg.orteip or { };
  minimizerBinds = minimizerCfg.binds or { };
in
{
  minimizerEnabled = minimizerCfg.enable or false;
  inherit minimizerVariant minimizerIsDenis minimizerIsOrteip;
  inherit minimizerPackage minimizerDefaultCommand minimizerCommand;
  inherit minimizerOrteipCfg;
  minimizerOrteipAppId = minimizerOrteipCfg.appId or "keepassxc";
  inherit minimizerBinds;
  minimizerToggleBind = minimizerBinds.toggle or "$mainMod CTRL, m";
  minimizerRestoreBind = minimizerBinds.restore or "$mainMod CTRL SHIFT, m";
  minimizerMenuBind = minimizerBinds.menu or "$mainMod CTRL, c";
  minimizerToggleCommand =
    if minimizerIsOrteip then
      "${minimizerCommand} ${minimizerOrteipCfg.appId or "keepassxc"}"
    else
      minimizerCommand;
  minimizerRestoreCommand =
    if minimizerIsDenis then "${minimizerCommand} --restore-last" else minimizerCommand;
  minimizerMenuCommand = if minimizerIsDenis then "${minimizerCommand} --menu" else minimizerCommand;
}
