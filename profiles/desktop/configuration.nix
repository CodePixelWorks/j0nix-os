{ pkgs, lib, settings, inputs, ... }:
let
  users = settings.users or [ settings.username ];
in {
  imports = [
    ./hardware-configuration.nix
    ./modules/boot.nix
    ./modules/binfmt.nix
    ./modules/audio.nix
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
    ../../system/kernel
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

  nixpkgs.config.allowUnfree = true;

  nix.settings = {
    experimental-features = [ "nix-command" "flakes" ];
    substituters = [
      "https://attic.xuyh0120.win/lantian"
      "https://hyprland.cachix.org"
    ];
    trusted-public-keys = [
      "lantian:EeAUQ+W+6r7EtwnmYjeVwx5kOGEBpjlBfPlzGlTNvHc="
      "hyprland.cachix.org-1:a7pgxzMz7+chwVL3/pzj6jIBMioiJM7ypFP8PwtkuGc="
    ];
    trusted-users = [ "root" ] ++ users;
  };
  nix.gc = {
    automatic = true;
    dates = "weekly";
    options = "--delete-older-than 14d";
  };
  nix.optimise.automatic = true;

  services.dbus.implementation = "broker";

  time.timeZone = settings.timezone;
  services.chrony.enable = true;

  i18n.defaultLocale = settings.locale;
  i18n.extraLocaleSettings = {
    LANG = settings.locale;
    LC_ALL = settings.locale;
    LANGUAGE = settings.locale;
  };

  console = {
    useXkbConfig = true;
  };

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

  fonts.packages = [
    settings.themeDetails.fontPkg
    pkgs.noto-fonts-cjk-sans
    pkgs.noto-fonts-cjk-serif
  ];
  assertions = [
  ];

  system.stateVersion = "25.11";
}
