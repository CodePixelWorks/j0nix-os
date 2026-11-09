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

  options.j0nix.desktop.binfmt.aarch64.enable = lib.mkOption {
    type = lib.types.bool;
    default = false;
    description = ''
      Register the aarch64 binfmt handler (qemu-user) and enable the
      corresponding nix build platform, so aarch64 NixOS closures can be
      built and deployed from this workstation (e.g. the app-srv-02
      edge host on OCI Ampere).
    '';
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

    # aarch64 via qemu-user: the registration covers execution inside
    # nix build sandboxes (binfmt is mounted there), and the nix
    # extra-platforms entry makes the daemon schedule aarch64 builds
    # on this machine.
    boot.binfmt.emulatedSystems = lib.mkIf cfg.aarch64.enable [ "aarch64-linux" ];

    # The nix daemon and user-level nix need the extra platform so
    # aarch64 derivations get scheduled here instead of failing with
    # "platform mismatch". sandbox stays at the system default — the
    # binfmt interpreter is available inside sandboxes automatically
    # (boot.binfmt registers it system-wide).
    nix.settings.extra-platforms = lib.mkIf cfg.aarch64.enable
      (lib.mkAfter [ "aarch64-linux" ]);
  };
}
