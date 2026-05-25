{ lib, settings, ... }:
let
  cfg = (settings.programs or { }).fastfetch or { };
  enabled = cfg.enable or false;
in
lib.mkIf enabled {
  programs.fastfetch = {
    enable = true;
    settings = {
      display = {
        separator = " -> ";
        color = {
          keys = "35";
          output = "39";
        };
      };

      logo = {
        source = "nixos";
        type = "builtin";
        padding = {
          top = 1;
          left = 1;
        };
      };

      modules = [
        "break"
        {
          type = "os";
          key = "OS";
        }
        {
          type = "kernel";
          key = "Kernel";
        }
        {
          type = "packages";
          key = "Packages";
        }
        {
          type = "shell";
          key = "Shell";
        }
        {
          type = "wm";
          key = "WM";
        }
        "break"
        {
          type = "host";
          key = "Host";
        }
        {
          type = "cpu";
          key = "CPU";
        }
        {
          type = "gpu";
          key = "GPU";
        }
        {
          type = "memory";
          key = "Memory";
        }
        {
          type = "disk";
          key = "Disk";
        }
        {
          type = "uptime";
          key = "Uptime";
        }
      ];
    };
  };
}
