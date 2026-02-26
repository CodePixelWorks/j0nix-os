{ ... }:
{
  j0nix.desktop.sysctl.extraFragments = [
    {
      # Favor larger write buffering during exports/transcodes.
      "vm.dirty_background_ratio" = 10;
      "vm.dirty_ratio" = 30;
    }
  ];
}
