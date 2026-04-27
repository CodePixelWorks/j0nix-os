{ config, lib, pkgs, ... }:
let
  cfg = config.programs.autodeskFusion.systemIntegration;
in
{
  options.programs.autodeskFusion.systemIntegration = {
    enable = lib.mkEnableOption "system dependencies for Autodesk Fusion on Linux";

    enableSpaceMouse = lib.mkOption {
      type = lib.types.bool;
      default = true;
      description = "Enable spacenavd for 3Dconnexion SpaceMouse support.";
    };
  };

  config = lib.mkIf cfg.enable {
    environment.systemPackages = [
      pkgs.autodesk-fusion-linux
      pkgs.cabextract
      pkgs.p7zip
      pkgs.winetricks
      (pkgs.wineWow64Packages.stagingFull or pkgs.wineWow64Packages.staging)
      pkgs.xdg-utils
      pkgs.desktop-file-utils
    ] ++ lib.optionals cfg.enableSpaceMouse [ pkgs.spacenavd ];

    assertions = [
      {
        assertion = pkgs.stdenv.hostPlatform.system == "x86_64-linux";
        message = "Autodesk Fusion on Linux is only supported on x86_64-linux.";
      }
    ];
  };
}
