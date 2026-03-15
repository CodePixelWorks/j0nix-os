{ stdenvNoCC }:

stdenvNoCC.mkDerivation {
  pname = "j0nix-wallpapers";
  version = "1.0.0";
  src = ../../../../wallpapers;
  dontBuild = true;

  installPhase = ''
    mkdir -p "$out/share/j0nix/wallpapers"
    cp -r "$src"/. "$out/share/j0nix/wallpapers/"
  '';
}
