{ config, lib, pkgs, ... }:
let
  cfg = config.j0nix.desktop.network;
in
{
  options.j0nix.desktop.network = {
    hostName = lib.mkOption {
      type = lib.types.str;
      default = "nixos";
    };

    networkmanager.enable = lib.mkOption {
      type = lib.types.bool;
      default = true;
    };

    wifiManagerGui.enable = lib.mkOption {
      type = lib.types.bool;
      default = true;
      description = "Install NetworkManager GUI tools (nm-applet / nm-connection-editor).";
    };

    tailscale = {
      enable = lib.mkOption {
        type = lib.types.bool;
        default = false;
      };
      installCli = lib.mkOption {
        type = lib.types.bool;
        default = true;
      };
    };
  };

  config = {
    networking.hostName = cfg.hostName;
    networking.networkmanager.enable = cfg.networkmanager.enable;
    services.tailscale.enable = cfg.tailscale.enable;

    j0nix.software.systemPackages =
      lib.optionals (cfg.networkmanager.enable && cfg.wifiManagerGui.enable) [
        pkgs.networkmanagerapplet
      ];

    environment.systemPackages = lib.optionals (cfg.tailscale.enable && cfg.tailscale.installCli) [
      pkgs.tailscale
    ];
  };
}
