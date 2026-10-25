# PdfCraft (ArtCraft) — open-source PDF workbench (Rust, v0.9.0 alpha).
#
# Consumed from github:ipeglin/artcraft-nix (AppImage-packaged from the
# official releases, sha256-verified mirrors). Only the pdfcraft package
# — not the whole suite.
#
# The module form (inputs.artcraft.nixosModules.default) installs EVERY
# app + links /usr/share/fonts; we only want pdfcraft, so the package is
# installed directly and the font-dir requirement is handled here.
{ config, lib, pkgs, inputs, ... }:
let
  artcraftPkgs = inputs.artcraft.packages.${pkgs.system};
in
{
  environment.systemPackages = [ artcraftPkgs.pdfcraft ];

  # The ArtCraft apps' text tools look in /usr/share/fonts, not through
  # fontconfig (module README). fontconfig's fontDir already renders the
  # system fonts there on j0nix-os — asserted so a fontconfig change
  # never silently breaks PdfCraft text rendering.
  fonts.fontDir.enable = lib.mkForce true;
}
