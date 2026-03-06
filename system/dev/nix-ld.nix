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
      stdenv.cc.cc
      zlib
      fuse3
      icu
      nss
      openssl
      curl
      expat
    ];
  };
}
