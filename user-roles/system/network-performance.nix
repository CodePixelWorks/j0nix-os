{ ... }:
{
  j0nix.desktop.sysctl.extraFragments = [
    {
      # Throughput/latency baseline for desktop + gaming + remote workflows.
      "net.core.default_qdisc" = "fq";
      "net.ipv4.tcp_congestion_control" = "bbr";
      "net.ipv4.tcp_mtu_probing" = 1;
      "net.ipv4.tcp_fastopen" = 3;
      "net.core.rmem_max" = 67108864;
      "net.core.wmem_max" = 67108864;
      "net.ipv4.tcp_rmem" = "4096 131072 33554432";
      "net.ipv4.tcp_wmem" = "4096 131072 33554432";
      "net.core.netdev_max_backlog" = 16384;
    }
  ];
}
