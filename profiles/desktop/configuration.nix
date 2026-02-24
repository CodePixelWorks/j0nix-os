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
  storage = settings.storage or { };
  autoMountWindows = storage.autoMountWindows or true;
  noPasswordMounts = storage.noPasswordMounts or true;
  gamesDisk = storage.gamesDisk or { };
  gamesDiskEnabled = gamesDisk.enable or false;
  gamesDiskMountPoint = gamesDisk.mountPoint or "/mnt/Games";
  gamesDiskUuid = gamesDisk.uuid or "";
  gamesDiskFsType = gamesDisk.fsType or "ntfs3";
  gamesDiskGvfsShow = gamesDisk.gvfsShow or true;
  gamesDiskGvfsName = gamesDisk.gvfsName or "GAMES";
  gamesDiskOnDemandAutomount = gamesDisk.onDemandAutomount or false;
  gamesDiskIdleTimeout = gamesDisk.idleTimeout or "5min";
  gamesDiskForceDirtyNtfsMount = gamesDisk.forceDirtyNtfsMount or false;
  network = settings.network or { };
  tailscaleCfg = network.tailscale or { };
  tailscaleEnabled = tailscaleCfg.enable or false;
in {
  imports = [
    ./hardware-configuration.nix
    ../../system/drivers
    ../../system/dev
    ../../system/tuning
    ../../system/gaming
  ] ++ (map (wm: ../../system/wm/${wm}.nix) settings.wms);

  boot = {
    # Keep kernel selection centralized in the desktop profile.
    # CachyOS variants already include BORE scheduler support.
    kernelPackages = pkgs.cachyosKernels.linuxPackages-cachyos-latest-x86_64-v4;
    tmp = {
      useTmpfs = false;
      tmpfsSize = "30%";
    };
    loader.systemd-boot.enable = true;
    loader.efi.canTouchEfiVariables = true;
    # Help NVIDIA HDMI/DP audio endpoints appear reliably on some setups/TVs.
    kernelModules = [
      "snd_hda_intel"
      "snd_hda_codec_hdmi"
    ];
    # USB Bluetooth adapters/controllers can become unreliable after autosuspend.
    extraModprobeConfig = ''
      options btusb enable_autosuspend=0
    '';
  };

  nixpkgs.overlays = [
    inputs.nix-cachyos-kernel.overlays.pinned
  ];
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

  networking.hostName = settings.hostname;
  networking.networkmanager.enable = true;
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
  services.flatpak.enable = true;

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
  services.gvfs.enable = true;
  services.udisks2.enable = autoMountWindows;
  services.dbus.implementation = "broker";

  security.polkit.enable = true;
  security.polkit.extraConfig = lib.mkIf noPasswordMounts ''
    polkit.addRule(function(action, subject) {
      var allowed = [
        "org.freedesktop.udisks2.filesystem-mount",
        "org.freedesktop.udisks2.filesystem-mount-system",
        "org.freedesktop.udisks2.filesystem-mount-other-seat",
        "org.freedesktop.udisks2.filesystem-unmount-others",
        "org.freedesktop.udisks2.encrypted-unlock",
        "org.freedesktop.udisks2.eject-media"
      ];

      if (allowed.indexOf(action.id) >= 0 && subject.isInGroup("wheel")) {
        return polkit.Result.YES;
      }
    });
  '';

  virtualisation.libvirtd.enable = true;

  # Keep the Windows games disk consistently available at a stable path.
  fileSystems = lib.optionalAttrs gamesDiskEnabled {
    "${gamesDiskMountPoint}" = {
      device = "/dev/disk/by-uuid/${gamesDiskUuid}";
      fsType = gamesDiskFsType;
      options = [
        "rw"
        "uid=1000"
        "gid=100"
        "umask=0022"
        "nofail"
      ]
      ++ lib.optionals gamesDiskGvfsShow [
        "x-gvfs-show"
        "x-gvfs-name=${gamesDiskGvfsName}"
      ]
      ++ lib.optionals gamesDiskOnDemandAutomount [
        "x-systemd.automount"
        "x-systemd.idle-timeout=${gamesDiskIdleTimeout}"
      ]
      ++ lib.optionals gamesDiskForceDirtyNtfsMount [
        # Emergency-only workaround for NTFS dirty volumes. Prefer running chkdsk on Windows.
        "force"
      ];
    };
  };

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
    {
      assertion = builtins.isBool autoMountWindows && builtins.isBool noPasswordMounts;
      message = "settings.storage.autoMountWindows and settings.storage.noPasswordMounts must be booleans";
    }
    {
      assertion = (!gamesDiskEnabled) || (gamesDiskUuid != "");
      message = "settings.storage.gamesDisk.uuid must be set when gamesDisk.enable = true";
    }
    {
      assertion = (!gamesDiskEnabled) || lib.hasPrefix "/" gamesDiskMountPoint;
      message = "settings.storage.gamesDisk.mountPoint must be an absolute path";
    }
    {
      assertion = (!gamesDiskEnabled) || (!gamesDiskGvfsShow) || (gamesDiskGvfsName != "");
      message = "settings.storage.gamesDisk.gvfsName must not be empty when gvfsShow = true";
    }
    {
      assertion = (!gamesDiskForceDirtyNtfsMount) || builtins.elem gamesDiskFsType [ "ntfs3" "ntfs" ];
      message = "settings.storage.gamesDisk.forceDirtyNtfsMount is only valid for NTFS filesystems";
    }
  ];

  system.stateVersion = "25.11";
}
