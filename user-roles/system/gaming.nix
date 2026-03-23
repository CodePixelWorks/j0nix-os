{ ... }:
{
  boot.kernelParams = [
    # Avoid severe stutter penalty from split-lock detection in games
    # using older anti-cheat or certain middleware (especially Unreal Engine).
    "split_lock_mitigate=0"
  ];

  j0nix.desktop.sysctl.extraFragments = [
    {
      # Favor low-latency buffering for game workloads (collector keeps higher numeric values on conflicts).
      "vm.swappiness" = 10;
      "vm.vfs_cache_pressure" = 50;
      "net.core.netdev_max_backlog" = 32768;
      # Required by Star Citizen, Jedi: Survivor, and many Unreal Engine titles.
      "vm.max_map_count" = 2147483642;
    }
  ];
}
