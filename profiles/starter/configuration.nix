{
  lib,
  settings,
  ...
}:
let
  resolveEnabledWms = import ../../nix/system/lib/enabled-wms.nix { inherit lib; };
  enabledWms = resolveEnabledWms settings;
  hardwareConfigurationFile =
    if builtins.pathExists ./hardware-configuration.nix then
      ./hardware-configuration.nix
    else
      throw ''
        profiles/starter/hardware-configuration.nix is required for this profile.

        Generate it with:
          sudo nixos-generate-config --show-hardware-config > profiles/starter/hardware-configuration.nix
      '';
in
{
  imports = [
    hardwareConfigurationFile
    ../../nix/system/apps
    ../../nix/system/software
    ../../nix/roles/system
    ../../nix/system/accounts
    ../../nix/system/binfmt
    ../../nix/system/audio
    ../../nix/system/boot
    ../../nix/system/locale
    ../../nix/system/fonts
    ../../nix/system/theme/stylix.nix
    ../../nix/system/logging
    ../../nix/system/printing
    ../../nix/system/scanning
    ../../nix/system/kernel
    ../../nix/system/nix
    ../../nix/system/network
    ../../nix/system/security
    ../../nix/system/storage
    ../../nix/system/virtualisation
    ../../nix/system/dev
    ../../nix/system/tuning
    ../../nix/system/gaming
  ]
  ++ (map (wm: ../../nix/system/wm/${wm}.nix) enabledWms);

  services.dbus.implementation = "broker";
  services.chrony.enable = true;
  system.stateVersion = "25.11";
}
