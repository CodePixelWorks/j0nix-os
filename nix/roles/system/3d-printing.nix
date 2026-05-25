{ ... }:
{
  j0nix.desktop.sysctl.extraFragments = [
    {
      # AppImage/bwrap based 3D-print tooling may require unprivileged user namespaces.
      "kernel.unprivileged_userns_clone" = 1;
      "user.max_user_namespaces" = 1048576;
    }
  ];
}
