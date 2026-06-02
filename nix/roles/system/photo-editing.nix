{ ... }:
{
  j0nix.desktop.sysctl.extraFragments = [
    {
      # Larger buffers for high-resolution image exports and batch operations.
      "vm.dirty_background_ratio" = 10;
      "vm.dirty_ratio" = 30;
    }
  ];
}
