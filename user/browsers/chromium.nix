{ lib, pkgs, settings, ... }:
let
  nvidiaEnabled = ((settings.drivers or { }).nvidia or { }).enable or false;
  chromiumBaseFlags = [
    # Prefer native Wayland on Hyprland and keep the wrapper behavior deterministic.
    "--ozone-platform-hint=auto"
    # Enable Linux VA-API paths for hardware video decode.
    "--enable-features=VaapiVideoDecoder,AcceleratedVideoDecodeLinuxGL"
    "--ignore-gpu-blocklist"
    "--enable-zero-copy"
  ];
  chromiumNvidiaFlags = [
    # NVIDIA setups often need the driver checks relaxed for VA-API decode.
    "--enable-features=VaapiIgnoreDriverChecks"
  ];
in
{
  programs.chromium = {
    enable = true;
    commandLineArgs = chromiumBaseFlags ++ lib.optionals nvidiaEnabled chromiumNvidiaFlags;
  };
}
