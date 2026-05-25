{ pkgs, ... }:
{
  j0nix.software.systemPackages = with pkgs; [
    hunspell
    hunspellDicts.en_US
    hunspellDicts.de_DE
  ];
}
