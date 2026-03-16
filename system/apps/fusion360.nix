{ lib, pkgs, settings, ... }:
let
  sambaCompat = pkgs.writeShellScriptBin "samba" ''
    if [ -x "${pkgs.samba}/bin/samba" ]; then
      exec "${pkgs.samba}/bin/samba" "$@"
    fi

    if [ -x "${pkgs.samba}/bin/samba-tool" ]; then
      exec "${pkgs.samba}/bin/samba-tool" "$@"
    fi

    if [ -x "${pkgs.samba}/bin/smbd" ]; then
      exec "${pkgs.samba}/bin/smbd" "$@"
    fi

    echo "No Samba executable was found in ${pkgs.samba}" >&2
    exit 1
  '';
  userSettings = builtins.attrValues (settings.userSettings or { });
  windowsAppsEnable =
    lib.any
      (userCfg:
        lib.elem "fusion360-proton" ((((userCfg.programs or { }).windowsApps or { }).packages or [ ])))
      userSettings;
  fusionEnable =
    lib.any (userCfg: (((userCfg.programs or { }).fusion360 or { }).enable or false)) userSettings;
  enabled = windowsAppsEnable || fusionEnable;
in
{
  config = lib.mkIf enabled {
    j0nix.software.systemPackages = with pkgs; [
      bc
      cabextract
      curl
      gawk
      lsb-release
      mesa-demos
      mokutil
      p7zip
      samba
      sambaCompat
      wget
      xdg-utils
      xrandr
    ];

    hardware.spacenavd.enable = true;
  };
}
