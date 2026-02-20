{ settings, ... }:
let
  gaming = (settings.sysctlProfiles or { }).gaming or { };
in {
  # High map_count avoids crashes in some Proton/Wine-heavy titles.
  "vm.max_map_count" = gaming.vmMaxMapCount or 2147483642;

  # Keep more memory for active game processes; tune for desktop responsiveness.
  "vm.swappiness" = gaming.swappiness or 10;
  "vm.vfs_cache_pressure" = gaming.vfsCachePressure or 50;
  "vm.dirty_background_ratio" = gaming.dirtyBackgroundRatio or 5;
  "vm.dirty_ratio" = gaming.dirtyRatio or 15;
  "vm.dirty_writeback_centisecs" = gaming.dirtyWritebackCentisecs or 1500;

  # Let scheduler keep interactive workloads snappy.
  "kernel.sched_autogroup_enabled" = gaming.schedAutogroup or 1;
}
