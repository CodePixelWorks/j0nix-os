{ pkgs, ... }:
{
  j0nix.software.systemPackages = with pkgs; [
    home-manager
    nix-index
    git
    wget
    curl
    vim
    pciutils
    usbutils
    ntfs3g
    xfsprogs
    inetutils
    lsof
    lm_sensors
    vulkan-tools
    j0nix-wallpapers
  ];
}
