{
  pkgs,
  lib,
  settings,
  inputs,
  ...
}:
let
  resolveEnabledWms = import ../../system/lib/enabled-wms.nix { inherit lib; };
  enabledWms = resolveEnabledWms settings;
in
{
  imports = [
    ./hardware-configuration.nix
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
    ./modules/gaming.nix
    ./modules/security.nix
    ./modules/storage.nix
    ./modules/accounts.nix
    ./modules/virtualisation.nix
    ./modules/thermal.nix
    ./modules/drivers.nix
    ./modules/support-drivers.nix
    ../../system/apps/bambulab.nix
    ../../system/apps/ollama.nix
    ../../system/apps/syncthing.nix
    ../../system/software
    ../../user-roles/system
    ../../system/accounts
    ../../system/binfmt
    ../../system/audio
    ../../system/boot
    ../../system/locale
    ../../system/fonts
    ../../system/printing
    ../../system/scanning
    ../../system/kernel
    ../../system/nix
    ../../system/network
    ../../system/security
    ../../system/storage
    ../../system/virtualisation
    ../../system/drivers
    ../../system/drivers/support.nix
    ../../system/dev
    ../../system/tuning
    ../../system/gaming
  ]
  ++ (map (wm: ../../system/wm/${wm}.nix) enabledWms);

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
