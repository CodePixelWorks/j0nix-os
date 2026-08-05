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
  chromiumPackage =
    if nvidiaEnabled then
      pkgs.symlinkJoin {
        name = "chromium-nvidia-vaapi";
        paths = [ pkgs.chromium ];
        nativeBuildInputs = [ pkgs.makeWrapper ];
        postBuild = ''
          wrapProgram "$out/bin/chromium" \
            --set LIBVA_DRIVER_NAME nvidia \
            --set NVD_BACKEND direct \
            --set GBM_BACKEND nvidia-drm \
            --set __GLX_VENDOR_LIBRARY_NAME nvidia
        '';
      }
    else
      pkgs.chromium;
in
{
  programs.chromium = {
    enable = true;
    package = chromiumPackage;
    commandLineArgs = chromiumBaseFlags;
  };

  j0nix.user.software.packages = lib.optionals nvidiaEnabled [
    pkgs.libva-utils
  ];
}
