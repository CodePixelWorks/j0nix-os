# gpu-unlock kernel module (Zagitta/gpu-unlock)
#
# Builds the gpu_unlock out-of-tree kernel module against the running
# kernel, extracts the 16 firmware .bin files from the pinned NVIDIA
# 610.43.03 inputs, and wires boot.kernelParams + boot.initrd.kernelModules
# so the module loads before the nvidia driver.
#
# Enable via: j0nix.desktop.drivers.gpuUnlock.enable = true;
{ config, lib, pkgs, ... }:
let
  cfg = config.j0nix.desktop.drivers.gpuUnlock;
  kernelPackages = config.boot.kernelPackages;

  nvVersion = "610.43.03";

  gpuUnlockSrc = pkgs.fetchFromGitHub {
    owner = "Zagitta";
    repo = "gpu-unlock";
    rev = "1fc6d628c49c7fba34ef3a2e7f758700d35ce890";
    sha256 = "08xsnv39mwgig51lvjqs5yh805la91c0azp2hc4sv7irqz2fcrqk";
  };

  # NVIDIA inputs the upstream extractors read. The repository does not
  # ship the firmware blobs itself; assets/ only carries banner.svg.
  nvInstaller = pkgs.fetchurl {
    url = "https://download.nvidia.com/XFree86/Linux-x86_64/${nvVersion}/NVIDIA-Linux-x86_64-${nvVersion}-no-compat32.run";
    sha256 = "141gzqc47s05a95xkxs5r7ikdln495bnakypsclxz9ihnwflb170";
  };
  nvKernelSource = pkgs.fetchurl {
    url = "https://download.nvidia.com/XFree86/NVIDIA-kernel-module-source/NVIDIA-kernel-module-source-${nvVersion}.tar.xz";
    sha256 = "1p61kzz2vb770cia95c6z6d4xq738qx2fqsd24vdqgm2qwiqj4by";
  };

  gpuUnlockModule = pkgs.stdenv.mkDerivation {
    name = "gpu-unlock-2.0.0-${kernelPackages.kernel.version}";
    src = gpuUnlockSrc;
    nativeBuildInputs = [ kernelPackages.kernel.dev ];
    buildPhase = ''
      make -C kernel/gpu_unlock \
        KDIR=${kernelPackages.kernel.dev}/lib/modules/${kernelPackages.kernel.modDirVersion}/build
    '';
    installPhase = ''
      mkdir -p $out/lib/modules/${kernelPackages.kernel.modDirVersion}/updates
      cp kernel/gpu_unlock/*.ko $out/lib/modules/${kernelPackages.kernel.modDirVersion}/updates/
    '';
  };

  # The NVIDIA artifacts must not be buildInputs: stdenv sources every
  # buildInput as a setup hook, and the .run installer is a makeself
  # binary archive ("cannot execute binary file"). They are interpolated
  # into the build script instead.
  gpuUnlockFirmware = pkgs.stdenv.mkDerivation {
    name = "gpu-unlock-firmware-${nvVersion}";
    src = gpuUnlockSrc;
    nativeBuildInputs = [ pkgs.python3 pkgs.zstd ];
    buildPhase = ''
      runHook preBuild
      export HOME=$TMPDIR
      # extract_boot_assets.py reads the extracted kernel source tree.
      mkdir -p assets.src
      tar -xf ${nvKernelSource} -C assets.src
      python3 ${gpuUnlockSrc}/firmware/extract_gsp.py ${nvInstaller} ./assets
      python3 ${gpuUnlockSrc}/firmware/extract_boot_assets.py \
        ./assets.src/NVIDIA-kernel-module-source-${nvVersion} ./assets
      runHook postBuild
    '';
    installPhase = ''
      runHook preInstall
      mkdir -p $out/lib/firmware/gpu-unlock/${nvVersion}
      cp assets/*.bin $out/lib/firmware/gpu-unlock/${nvVersion}/
      cp assets/NVIDIA-LICENSE $out/lib/firmware/gpu-unlock/${nvVersion}/NVIDIA-LICENSE
      runHook postInstall
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
