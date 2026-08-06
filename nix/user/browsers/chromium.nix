{ lib, pkgs, settings, ... }:
let
  nvidiaEnabled = ((settings.drivers or { }).nvidia or { }).enable or false;
  chromiumFeatures = [
    "VaapiVideoDecoder"
    "AcceleratedVideoDecodeLinuxGL"
  ]
  ++ lib.optionals nvidiaEnabled [
    "VaapiIgnoreDriverChecks"
  ];
  chromiumBaseFlags = [
    # Prefer native Wayland on Hyprland and keep the wrapper behavior deterministic.
    "--ozone-platform-hint=auto"
    # Enable Linux VA-API paths for hardware video decode.
    "--enable-features=${lib.concatStringsSep "," chromiumFeatures}"
    "--ignore-gpu-blocklist"
    "--enable-zero-copy"
  ];
in
{
  programs.chromium = {
    enable = true;
    package = pkgs.chromium;
    commandLineArgs = chromiumBaseFlags;
  };

  home.sessionVariables = lib.mkIf nvidiaEnabled {
    LIBVA_DRIVER_NAME = "nvidia";
    NVD_BACKEND = "direct";
    GBM_BACKEND = "nvidia-drm";
    __GLX_VENDOR_LIBRARY_NAME = "nvidia";
  };

  j0nix.user.software.packages = lib.optionals nvidiaEnabled [
    pkgs.libva-utils
  ];
}
