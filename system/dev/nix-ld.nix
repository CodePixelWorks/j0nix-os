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
}
