{ lib, settings, ... }:
let
  network = ((settings.sysctlProfiles or { }).network or { });
in
lib.optionalAttrs (network ? defaultQdisc) {
  "net.core.default_qdisc" = network.defaultQdisc;
}
// lib.optionalAttrs (network ? tcpCongestionControl) {
  "net.ipv4.tcp_congestion_control" = network.tcpCongestionControl;
}
// lib.optionalAttrs (network ? tcpMtuProbing) {
  "net.ipv4.tcp_mtu_probing" = network.tcpMtuProbing;
}
// lib.optionalAttrs (network ? tcpFastOpen) {
  "net.ipv4.tcp_fastopen" = network.tcpFastOpen;
}
// lib.optionalAttrs (network ? rmemMax) {
  "net.core.rmem_max" = network.rmemMax;
}
// lib.optionalAttrs (network ? wmemMax) {
  "net.core.wmem_max" = network.wmemMax;
}
// lib.optionalAttrs (network ? tcpRmem) {
  "net.ipv4.tcp_rmem" = network.tcpRmem;
}
// lib.optionalAttrs (network ? tcpWmem) {
  "net.ipv4.tcp_wmem" = network.tcpWmem;
}
// lib.optionalAttrs (network ? netdevMaxBacklog) {
  "net.core.netdev_max_backlog" = network.netdevMaxBacklog;
}
