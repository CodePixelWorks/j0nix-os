{ ... }:
{
  j0nix.desktop.sysctl.extraFragments = [
    {
      # Keep higher FD limits available for heavy DCC workflows and render helpers.
      "fs.file-max" = 4194304;
    }
  ];
}
