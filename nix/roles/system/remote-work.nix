{ pkgs, ... }:
{
  j0nix.software.systemPackages = with pkgs; [
    wireguard-tools
    openvpn
  ];
}
