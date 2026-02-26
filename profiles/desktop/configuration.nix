{ pkgs, lib, settings, inputs, ... }:
let
  users = settings.users or [ settings.username ];
  userOverrides = settings.userSettings or { };
  allowedShells = [ "zsh" "fish" ];
  shellForUser = username: (userOverrides.${username}.shell or settings.shell);
  userShells = map shellForUser users;
  useZsh = builtins.elem "zsh" userShells;
  useFish = builtins.elem "fish" userShells;
  audio = settings.audio or { };
  audioBackend = audio.backend or "pipewire";
  usePipeWire = audioBackend == "pipewire";
  usePulseAudio = audioBackend == "pulseaudio";
  audioBt = audio.bluetooth or { };
  enableHiFiCodecs = audioBt.enableHiFiCodecs or true;
  enableMsbc = audioBt.enableMsbc or true;
  bluetoothCodecs =
    audioBt.codecs
    or [
      "sbc"
      "sbc_xq"
      "aac"
      "aptx"
      "aptx_hd"
      "ldac"
    ];
  hasPulseAudioBtModules = builtins.hasAttr "pulseaudio-modules-bt" pkgs;
  network = settings.network or { };
  tailscaleCfg = network.tailscale or { };
  tailscaleEnabled = tailscaleCfg.enable or false;
in {
  imports = [
    ./hardware-configuration.nix
    ./modules/boot.nix
    ./modules/kernel.nix
    ./modules/security.nix
    ./modules/storage.nix
    ../../system/apps/bambulab.nix
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
    # boot policy (tmp/loader/resume/kernel modules/modprobe/binfmt) is defined via
    # `j0nix.desktop.boot` in `profiles/desktop/modules/boot.nix` and applied by `system/boot`.
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

  services.pipewire = {
    enable = usePipeWire;
    pulse.enable = usePipeWire;
    alsa.enable = usePipeWire;
    alsa.support32Bit = usePipeWire;
    wireplumber.enable = usePipeWire;
  };
  security.rtkit.enable = true;

  services.pipewire.wireplumber.extraConfig = lib.mkIf (usePipeWire && enableHiFiCodecs) {
    "51-bluez-codecs" = {
      "monitor.bluez.properties" = {
        "bluez5.codecs" = bluetoothCodecs;
        "bluez5.enable-msbc" = enableMsbc;
        "bluez5.enable-sbc-xq" = builtins.elem "sbc_xq" bluetoothCodecs;
        "bluez5.enable-hw-volume" = true;
        "bluez5.roles" = [
          "hsp_hs"
          "hsp_ag"
          "hfp_hf"
          "hfp_ag"
          "a2dp_sink"
          "a2dp_source"
        ];
      };
    };
  };

  services.pulseaudio = {
    enable = usePulseAudio;
    support32Bit = true;
    package = lib.mkIf usePulseAudio pkgs.pulseaudioFull;
  };

  hardware.bluetooth.enable = true;
  hardware.bluetooth.powerOnBoot = true;
  hardware.bluetooth.settings = lib.mkMerge [
    {
      Policy = {
        AutoEnable = true;
      };
    }
    (lib.mkIf enableHiFiCodecs {
      General = {
        Experimental = true;
      };
    })
  ];
  services.blueman.enable = true;
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
  ]) ++ lib.optionals tailscaleEnabled [
    pkgs.tailscale
  ] ++ lib.optionals (usePulseAudio && hasPulseAudioBtModules && enableHiFiCodecs) [
    pkgs."pulseaudio-modules-bt"
  ];

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
    {
      assertion = builtins.elem audioBackend [ "pipewire" "pulseaudio" ];
      message = "settings.audio.backend must be one of: pipewire, pulseaudio";
    }
    {
      assertion = (!enableHiFiCodecs) || ((builtins.length bluetoothCodecs) > 0);
      message = "settings.audio.bluetooth.codecs must not be empty when enableHiFiCodecs=true";
    }
  ];

  system.stateVersion = "25.11";
}
