{
  pkgs,
  lib,
  settings,
  inputs,
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
        profiles/desktop/hardware-configuration.nix is required for this host profile.

        Generate it with:
          sudo nixos-generate-config --show-hardware-config > profiles/desktop/hardware-configuration.nix
      '';
in
{
  imports = [
    hardwareConfigurationFile
    ./modules/boot.nix
    ./modules/binfmt.nix
    ./modules/audio.nix
    ./modules/custom.nix
    ./modules/locale.nix
    ./modules/fonts.nix
    ./modules/printing.nix
    ./modules/scanning.nix
    ./modules/nix.nix
    ./modules/network.nix
    ./modules/kernel.nix
    ./modules/logging.nix
    ./modules/gaming.nix
    ./modules/security.nix
    ./modules/storage.nix
    ./modules/accounts.nix
    ./modules/virtualisation.nix
    ./modules/thermal.nix
    ./modules/drivers.nix
    ./modules/support-drivers.nix
    ../../nix/system/apps
    ../../nix/system/software
    ../../nix/roles/system
    ../../nix/system/accounts
    ../../nix/system/binfmt
    ../../nix/system/audio
    ../../nix/system/boot
    ../../nix/system/locale
    ../../nix/system/fonts
    ../../nix/system/logging

    ../../nix/system/printing
    ../../nix/system/scanning
    ../../nix/system/kernel
    ../../nix/system/nix
    ../../nix/system/network
    ../../nix/system/security
    ../../nix/system/storage
    ../../nix/system/virtualisation
    ../../nix/system/drivers
    ../../nix/system/drivers/support.nix
    ../../nix/system/dev
    ../../nix/system/tuning
    ../../nix/system/gaming
  ]
  ++ (map (wm: ../../nix/system/wm/${wm}.nix) enabledWms);

  boot = {
    # boot policy (tmp/loader/resume/swap) is defined via `j0nix.desktop.boot`
    # in `profiles/desktop/modules/boot.nix` and applied by `system/boot`.
  };

  services.dbus.implementation = "broker";

  services.chrony.enable = true;

  assertions = [
  ];

  system.stateVersion = "25.11";
}
