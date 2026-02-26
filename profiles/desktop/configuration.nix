{ pkgs, lib, settings, inputs, ... }:
{
  imports = [
    ./hardware-configuration.nix
    ./modules/boot.nix
    ./modules/binfmt.nix
    ./modules/audio.nix
    ./modules/locale.nix
    ./modules/fonts.nix
    ./modules/nix.nix
    ./modules/network.nix
    ./modules/kernel.nix
    ./modules/security.nix
    ./modules/storage.nix
    ./modules/accounts.nix
    ./modules/virtualisation.nix
    ../../system/apps/bambulab.nix
    ../../system/accounts
    ../../system/binfmt
    ../../system/audio
    ../../system/boot
    ../../system/locale
    ../../system/fonts
    ../../system/kernel
    ../../system/nix
    ../../system/network
    ../../system/security
    ../../system/storage
    ../../system/virtualisation
    ../../system/drivers
    ../../system/dev
    ../../system/tuning
    ../../system/gaming
  ] ++ (map (wm: ../../system/wm/${wm}.nix) settings.wms);

  boot = {
    # boot policy (tmp/loader/resume/swap) is defined via `j0nix.desktop.boot`
    # in `profiles/desktop/modules/boot.nix` and applied by `system/boot`.
  };

  services.dbus.implementation = "broker";

  services.chrony.enable = true;

  services.printing.enable = true;

  programs.nix-ld.enable = true;
  programs.nix-ld.libraries = with pkgs; [ stdenv.cc.cc ];

  environment.systemPackages = (with pkgs; [
    home-manager
    nix-index
    git
    wget
    curl
    vim
    pciutils
    usbutils
    ntfs3g
    inetutils
    lsof
    lm_sensors
    vulkan-tools
  ]);

  assertions = [
  ];

  system.stateVersion = "25.11";
}
