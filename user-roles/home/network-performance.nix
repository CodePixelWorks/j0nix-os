{ pkgs, ... }:
{
  # Network performance tools for user space
  j0nix.user.software.packages = with pkgs; [
    ethtool
    iperf3
    netcat-openbsd
    tcpdump
    nmap
    mtr
    htop
  ];
}
