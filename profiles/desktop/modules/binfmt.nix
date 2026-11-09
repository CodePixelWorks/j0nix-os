{ ... }:
{
  j0nix.desktop.binfmt.appimage.enable = true;
  # Build + deploy the aarch64 edge host (app-srv-02) from this
  # workstation: binfmt registration for the qemu-user interpreter and
  # the nix extra-platforms entry so aarch64 derivations get scheduled
  # here. See nix/system/binfmt/default.nix.
  j0nix.desktop.binfmt.aarch64.enable = true;
}
