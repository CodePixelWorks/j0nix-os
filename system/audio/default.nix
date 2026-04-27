{
  config,
  lib,
  pkgs,
  ...
}:
let
  cfg = config.j0nix.desktop.audio;
  audioBackend = cfg.backend;
  usePipeWire = audioBackend == "pipewire";
  usePulseAudio = audioBackend == "pulseaudio";
  preventInterfaceSuspend = cfg.preventInterfaceSuspend;
  enableHiFiCodecs = cfg.bluetooth.enableHiFiCodecs;
  enableBluezExperimental = cfg.bluetooth.enableBluezExperimental;
  enableMsbc = cfg.bluetooth.enableMsbc;
  bluetoothCodecs = cfg.bluetooth.codecs;
  hasPulseAudioBtModules = builtins.hasAttr "pulseaudio-modules-bt" pkgs;
in
{
  options.j0nix.desktop.audio = {
    backend = lib.mkOption {
      type = lib.types.enum [
        "pipewire"
        "pulseaudio"
      ];
      default = "pipewire";
    };

    preventInterfaceSuspend = lib.mkOption {
      type = lib.types.bool;
      default = true;
      description = "Disable PipeWire/WirePlumber idle suspend for ALSA devices to avoid interface flapping.";
    };

    bluetooth = {
      enableHiFiCodecs = lib.mkOption {
        type = lib.types.bool;
        default = true;
      };
      enableBluezExperimental = lib.mkOption {
        type = lib.types.bool;
        default = false;
        description = "Enable BlueZ experimental features such as LE Audio/BAP. Keep disabled unless a device requires it.";
      };
      enableMsbc = lib.mkOption {
        type = lib.types.bool;
        default = true;
      };
      codecs = lib.mkOption {
        type = lib.types.listOf lib.types.str;
        default = [
          "sbc"
          "sbc_xq"
          "aac"
          "aptx"
          "aptx_hd"
          "ldac"
        ];
      };
    };
  };

  config = {
    services.pipewire = {
      enable = usePipeWire;
      pulse.enable = usePipeWire;
      alsa.enable = usePipeWire;
      alsa.support32Bit = usePipeWire;
      wireplumber.enable = usePipeWire;
    };

    security.rtkit.enable = true;

    services.pipewire.wireplumber.extraConfig = lib.mkMerge [
      (lib.mkIf (usePipeWire && preventInterfaceSuspend) {
        "50-alsa-no-suspend" = {
          "monitor.alsa.rules" = [
            {
              matches = [
                {
                  "node.name" = "~alsa_(input|output).*";
                }
              ];
              actions = {
                update-props = {
                  "session.suspend-timeout-seconds" = 0;
                  "node.pause-on-idle" = false;
                };
              };
            }
          ];
        };
      })
      (lib.mkIf (usePipeWire && enableHiFiCodecs) {
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
      })
      (lib.mkIf usePipeWire {
        "52-bt-buffer-tuning" = {
          "monitor.bluez.properties" = {
            "bluez5.a2dp.ldac-quality" = "hq";
          };
          "alsa.properties" = {
            "api.alsa.period-size" = 1024;
            "api.alsa.headroom" = 8192;
          };
        };
      })
      (lib.mkIf usePipeWire {
        "53-bt-sbc-bitpool" = {
          "monitor.bluez.rules" = [
            {
              matches = [
                {
                  "node.name" = "~bluez_output.*";
                }
              ];
              actions = {
                update-props = {
                  "api.alsa.period-size" = 1024;
                  "api.alsa.headroom" = 8192;
                  "resample.quality" = 10;
                };
              };
            }
          ];
        };
      })
    ];

    services.pulseaudio = {
      enable = usePulseAudio;
      support32Bit = true;
      package = lib.mkIf usePulseAudio pkgs.pulseaudioFull;
    };

    hardware.bluetooth.enable = true;
    hardware.bluetooth.powerOnBoot = true;
    hardware.bluetooth.settings = lib.mkMerge [
      {
        Policy.AutoEnable = true;
      }
      (lib.mkIf enableBluezExperimental {
        General.Experimental = true;
      })
    ];

    services.blueman.enable = true;

    j0nix.software.systemPackages =
      lib.optionals (usePulseAudio && hasPulseAudioBtModules && enableHiFiCodecs)
        [
          pkgs."pulseaudio-modules-bt"
        ];

    assertions = [
      {
        assertion = (!enableHiFiCodecs) || ((builtins.length bluetoothCodecs) > 0);
        message = "j0nix.desktop.audio.bluetooth.codecs must not be empty when enableHiFiCodecs = true";
      }
    ];
  };
}
