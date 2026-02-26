{ ... }:
{
  j0nix.desktop.sysctl.extraFragments = [
    {
      # Raise common dev limits; collector resolves conflicts by taking higher numeric values.
      "fs.inotify.max_user_watches" = 2097152;
      "fs.inotify.max_user_instances" = 16384;
      "fs.file-max" = 4194304;
      "net.core.somaxconn" = 8192;
    }
  ];
}
