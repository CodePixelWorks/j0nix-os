{ stdenvNoCC }:

stdenvNoCC.mkDerivation {
  pname = "j0nix-wallpapers";
  version = "1.0.0";
  src = ../../../../wallpapers;
  dontBuild = true;

  installPhase = ''
    mkdir -p "$out/share/j0nix/wallpapers"
    find "$src" -type f | while IFS= read -r file; do
      install -Dm644 "$file" "$out/share/j0nix/wallpapers/$(basename "$file")"
    done
  '';
}
