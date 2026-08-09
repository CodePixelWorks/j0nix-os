{ ... }:
{
  config = {
    j0nix.desktop.sysctl.extraFragments = [
      {
        # Bambu/related wrappers require unprivileged user namespaces.
        "kernel.unprivileged_userns_clone" = 1;
        "user.max_user_namespaces" = 1048576;
      }
    ];
  };
}
