{ settings, ... }:
let
  network = ((settings.sysctlProfiles or { }).network or { });
in {
  # Throughput/latency baseline for desktop + gaming workloads.
  "net.core.default_qdisc" = network.defaultQdisc or "fq";
  "net.ipv4.tcp_congestion_control" = network.tcpCongestionControl or "bbr";
  "net.ipv4.tcp_mtu_probing" = network.tcpMtuProbing or 1;
  "net.ipv4.tcp_fastopen" = network.tcpFastOpen or 3;
  "net.core.rmem_max" = network.rmemMax or 67108864;
  "net.core.wmem_max" = network.wmemMax or 67108864;
  "net.ipv4.tcp_rmem" = network.tcpRmem or "4096 131072 33554432";
  "net.ipv4.tcp_wmem" = network.tcpWmem or "4096 131072 33554432";
  "net.core.netdev_max_backlog" = network.netdevMaxBacklog or 16384;
}
