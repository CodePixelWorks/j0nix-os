{ ... }:
{
  j0nix.desktop.sysctl.extraFragments = [
    {
      # Favor low-latency buffering for game workloads (collector keeps higher numeric values on conflicts).
      "vm.swappiness" = 10;
      "vm.vfs_cache_pressure" = 50;
      "net.core.netdev_max_backlog" = 32768;
    }
  ];
}
