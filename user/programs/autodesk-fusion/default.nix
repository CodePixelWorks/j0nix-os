{ lib, pkgs, settings, ... }:
let
  cfg = (settings.programs or { }).autodeskFusion or { };
in
{
  imports = [
    ../../../integrations/autodesk-fusion-nixos/modules/home-manager/autodesk-fusion.nix
  ];

  config = {
    programs.autodeskFusion = {
      enable = cfg.enable or false;
      package = pkgs.autodesk-fusion-linux;
      addToHomePackages = false;
      installMode = cfg.installMode or "wine";
      installDir = cfg.installDir or null;
      gpuMode = cfg.gpuMode or "dxvk";
      protonVersion = cfg.protonVersion or null;
      autoSetupOnLogin = cfg.autoSetupOnLogin or false;
      desktopEntry.enable = ((cfg.desktopEntry or { }).enable or true);
      urlHandler.enable = ((cfg.urlHandler or { }).enable or true);
    } // lib.optionalAttrs (cfg ? steamDirectory) {
      steamDirectory = cfg.steamDirectory;
    };

    j0nix.user.software.packages = lib.mkIf (cfg.enable or false) [ pkgs.autodesk-fusion-linux ];
  };
}
