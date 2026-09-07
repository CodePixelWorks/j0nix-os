{
  fetchurl,
  lib,
  p7zip,
  wineWow64Packages,
  writeShellApplication,
}:
let
  version = "5.6.2.0W";
  archiveVersion = lib.removeSuffix "W" version;
  archive = fetchurl {
    url = "https://github.com/HolterPhylo/AMUMSS/releases/download/v${version}/UPDATE.-.${archiveVersion}.FULL.7z";
    hash = "sha256-SiiH9znpwaUy5zt/x8+Gtt6HqrahUsto1wDy0c/SXBg=";
  };
in
writeShellApplication {
  name = "nms-amumss";
  runtimeInputs = [
    p7zip
    wineWow64Packages.waylandFull
  ];
  text = ''
    set -eu

    runtime_base="''${XDG_DATA_HOME:-$HOME/.local/share}/nms-patcher"
    runtime_dir="$runtime_base/amumss-${version}"
    game_dir=""
    scripts_dir=""

    usage() {
      cat <<'EOF'
    Usage: nms-amumss --game-dir <No-Man's-Sky-dir> [--scripts-dir <directory>]

    Extracts the pinned AMUMSS release into the user data directory, configures it
    for the supplied game directory, optionally imports Lua scripts, then starts
    AMUMSS through Wine. AMUMSS downloads the matching MBINCompiler at runtime.
    EOF
    }

    while [ "$#" -gt 0 ]; do
      case "$1" in
        --game-dir)
          [ "$#" -ge 2 ] || { usage >&2; exit 2; }
          game_dir="$2"
          shift 2
          ;;
        --scripts-dir)
          [ "$#" -ge 2 ] || { usage >&2; exit 2; }
          scripts_dir="$2"
          shift 2
          ;;
        --help|-h)
          usage
          exit 0
          ;;
        *)
          usage >&2
          exit 2
          ;;
      esac
    done

    [ -n "$game_dir" ] || { usage >&2; exit 2; }
    [ -d "$game_dir/GAMEDATA" ] || { echo "Error: not a No Man's Sky game directory: $game_dir" >&2; exit 1; }
    [ -z "$scripts_dir" ] || [ -d "$scripts_dir" ] || { echo "Error: scripts directory does not exist: $scripts_dir" >&2; exit 1; }

    if [ ! -f "$runtime_dir/BUILDMOD_AUTO.bat" ]; then
      mkdir -p "$runtime_base"
      temporary="$(mktemp -d "$runtime_base/.amumss-extract.XXXXXX")"
      trap 'rm -rf "$temporary"' EXIT
      7z x -y -o"$temporary" ${archive} >/dev/null
      mv "$temporary" "$runtime_dir"
      trap - EXIT
    fi

    wine_game_dir="$(winepath -w "$game_dir")"
    printf '%s\n' "$wine_game_dir" > "$runtime_dir/NMS_FOLDER.txt"

    if [ -n "$scripts_dir" ]; then
      mkdir -p "$runtime_dir/ModScript"
      find "$scripts_dir" -maxdepth 1 -type f -name '*.lua' -exec cp -- '{}' "$runtime_dir/ModScript/" \;
    fi

    cd "$runtime_dir"
    exec wine cmd /c BUILDMOD_AUTO.bat
  '';

  meta = {
    description = "Pinned AMUMSS Lua mod builder runner for No Man's Sky";
    homepage = "https://github.com/HolterPhylo/AMUMSS";
    license = lib.licenses.mit;
    platforms = lib.platforms.linux;
  };
}
