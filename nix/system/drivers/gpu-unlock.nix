# gpu-unlock kernel module (Zagitta/gpu-unlock)
#
# Builds the gpu_unlock out-of-tree kernel module against the running
# kernel, installs the 16 firmware .bin files from assets/, and wires
# boot.kernelParams + boot.initrd.kernelModules so the module loads
# before the nvidia driver.
#
# Enable via: j0nix.desktop.drivers.gpuUnlock.enable = true;
{ config, lib, pkgs, ... }:
let
  cfg = config.j0nix.desktop.drivers.gpuUnlock;
  kernelPackages = config.boot.kernelPackages;

  gpuUnlockModule = pkgs.stdenv.mkDerivation rec {
    name = "gpu-unlock-2.0.0-${kernelPackages.kernel.version}";
    src = pkgs.fetchFromGitHub {
      owner = "Zagitta";
      repo = "gpu-unlock";
      rev = "1fc6d628c49c7fba34ef3a2e7f758700d35ce890";
      sha256 = "sha256-08xsnv39mwgig51lvjqs5yh805la91c0azp2hc4sv7irqz2fcrqk";
    };
    nativeBuildInputs = [ kernelPackages.kernel.dev ];
    buildPhase = ''
      make -C kernel/gpu_unlock \
        KDIR=${kernelPackages.kernel.dev}/lib/modules/${kernelPackages.kernel.version}/build
    '';
    installPhase = ''
      mkdir -p $out/lib/modules/${kernelPackages.kernel.version}/updates
      cp kernel/gpu_unlock/*.ko $out/lib/modules/${kernelPackages.kernel.version}/updates/
    '';
  };

  gpuUnlockFirmware = pkgs.stdenv.mkDerivation {
    name = "gpu-unlock-firmware-610.43.03";
    src = pkgs.fetchFromGitHub {
      owner = "Zagitta";
      repo = "gpu-unlock";
      rev = "1fc6d628c49c7fba34ef3a2e7f758700d35ce890";
      sha256 = "sha256-08xsnv39mwgig51lvjqs5yh805la91c0azp2hc4sv7irqz2fcrqk";
    };
    buildPhase = ":";
    installPhase = ''
      mkdir -p $out/lib/firmware/gpu-unlock/610.43.03
      cp assets/*.bin $out/lib/firmware/gpu-unlock/610.43.03/
      cp assets/NVIDIA-LICENSE $out/lib/firmware/gpu-unlock/610.43.03/
    '';
  };
in
{
  config = lib.mkIf cfg.enable {
    boot.extraModulePackages = [ gpuUnlockModule ];
    hardware.firmware = [ gpuUnlockFirmware ];
    boot.kernelParams = [ "gpu_unlock.targets=all" ];
    boot.initrd.kernelModules = [ "gpu_unlock" ];
  };
}
