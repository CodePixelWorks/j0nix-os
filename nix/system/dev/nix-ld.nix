{ lib, pkgs, settings, ... }:
let
  dev = settings.dev or { };
  nixLd = dev.nixLd or { };
  enabled = nixLd.enable or true;
in
lib.mkIf enabled {
  programs.nix-ld = {
    enable = true;
    libraries = with pkgs; [
      # Core runtime/toolchain
      stdenv.cc.cc
      zlib
      fuse3
      icu
      nss
      nspr
      openssl
      curl
      expat
      libffi
      xz
      bzip2
      libxml2

      # Audio / IPC
      dbus
      libpulseaudio

      # Wayland/X11 windowing stack
      wayland
      libxkbcommon
      libx11
      libxcursor
      libxi
      libxrandr
      libxrender
      libxext
      libxfixes
      libxinerama

      # Rendering/font stack
      glib
      gtk3
      fontconfig
      freetype
      libGL
      libdrm
      vulkan-loader
    ];
  };

  # CachyOS WineWayland Proton contains 32-bit Wine components with the
  # conventional interpreter path /lib/ld-linux.so.2. NixOS supplies the
  # 64-bit nix-ld path, but not this i686 compatibility path. Keep the target
  # in the store and let tmpfiles replace it on upgrades; do not create a
  # mutable, hand-maintained loader link.
  systemd.tmpfiles.rules = [
    "d /lib 0755 root root -"
    "L+ /lib/ld-linux.so.2 - - - - ${pkgs.pkgsi686Linux.glibc}/lib/ld-linux.so.2"
  ];
}
