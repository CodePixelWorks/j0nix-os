{ inputs, pkgs, lib, ... }:
let
  hasZenPackage =
    (inputs ? zen-browser)
    && (inputs.zen-browser ? packages)
    && (builtins.hasAttr pkgs.stdenv.hostPlatform.system inputs.zen-browser.packages)
    && (inputs.zen-browser.packages.${pkgs.stdenv.hostPlatform.system} ? default);
in {
  home.packages = lib.optional hasZenPackage inputs.zen-browser.packages.${pkgs.stdenv.hostPlatform.system}.default;

  assertions = [
    {
      assertion = hasZenPackage;
      message = "Zen browser package missing in flake input 'zen-browser'";
    }
  ];
}
