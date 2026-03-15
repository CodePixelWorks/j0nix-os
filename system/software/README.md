# System Software

This layer aggregates system-wide package requirements via `j0nix.software.systemPackages`.

## Shared Files Under `/run/current-system/sw`

Installing a package through `environment.systemPackages` is not always enough to make custom
data paths appear under `/run/current-system/sw`.

If a package exports files under a custom subtree such as:
- `/share/j0nix/...`

then that subtree must also be added to:
- `environment.pathsToLink`

Example:

```nix
environment.systemPackages = [ pkgs.j0nix-wallpapers ];

environment.pathsToLink = [
  "/share/j0nix"
];
```

Without `environment.pathsToLink`, the package can be present in the system profile while the
expected path under `/run/current-system/sw/...` is still missing.
