{ config, lib, pkgs, ... }:
let
  cfg = config.j0nix.desktop.binfmt;
in
{
  options.j0nix.desktop.binfmt.appimage.enable = lib.mkOption {
    type = lib.types.bool;
    default = false;
    description = "Register an AppImage binfmt handler using appimage-run.";
  };

  config = {
    boot.binfmt.registrations.appimage = lib.mkIf cfg.appimage.enable {
      wrapInterpreterInShell = false;
      interpreter = "${pkgs.appimage-run}/bin/appimage-run";
      recognitionType = "magic";
      offset = 0;
      mask = ''\xff\xff\xff\xff\x00\x00\x00\x00\xff\xff\xff'';
      magicOrExtension = ''\x7fELF....AI\x02'';
    };
  };
}
