{ pkgs, lib, settings, inputs, ... }:
let
  users = settings.users or [ settings.username ];
  userOverrides = settings.userSettings or { };
  allowedShells = [ "zsh" "fish" ];
  shellForUser = username: (userOverrides.${username}.shell or settings.shell);
  userShells = map shellForUser users;
  useZsh = builtins.elem "zsh" userShells;
  useFish = builtins.elem "fish" userShells;
  network = settings.network or { };
  tailscaleCfg = network.tailscale or { };
  tailscaleEnabled = tailscaleCfg.enable or false;
in {
  imports = [
    ./hardware-configuration.nix
    ./modules/boot.nix
    ./modules/binfmt.nix
    ./modules/audio.nix
    ./modules/kernel.nix
    ./modules/security.nix
    ./modules/storage.nix
    ../../system/apps/bambulab.nix
    ../../system/binfmt
    ../../system/audio
    ../../system/boot
    ../../system/kernel
    ../../system/security
    ../../system/storage
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

  networking.hostName = settings.hostname;
  networking.networkmanager.enable = true;
  services.dbus.implementation = "broker";
  services.tailscale.enable = tailscaleEnabled;

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

  programs.zsh.enable = useZsh;
  programs.fish.enable = useFish;
  services.getty.autologinUser = lib.mkForce null;

  users.users = lib.genAttrs users (username: {
    isNormalUser = true;
    shell = pkgs.${shellForUser username};
    description = username;
    extraGroups = [
      "wheel"
      "networkmanager"
      "audio"
      "video"
      "gamemode"
    ] ++ lib.optionals (((settings.dev or { }).docker or { }).enable or true) [
      "docker"
    ];
  });

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
  ]) ++ lib.optionals tailscaleEnabled [ pkgs.tailscale ];

  fonts.packages = [
    settings.themeDetails.fontPkg
    pkgs.noto-fonts-cjk-sans
    pkgs.noto-fonts-cjk-serif
  ];
  virtualisation.libvirtd.enable = true;

  assertions = [
    {
      assertion = lib.all (shell: builtins.elem shell allowedShells) userShells;
      message = "All resolved user shells must be one of: zsh, fish (from settings.shell or userSettings.<name>.shell)";
    }
  ];

  system.stateVersion = "25.11";
}
