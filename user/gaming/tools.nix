{ lib, pkgs, settings, ... }:
let
  gaming = settings.gaming or { };
  enabled = gaming.enable or true;
  perf = gaming.performance or { };
  launchers = gaming.launchers or { };
  controllers = gaming.controllers or { };
  rockstarEnabled = launchers.rockstar or false;
in
lib.mkIf enabled {
  home.packages =
    [
      # Steam launch options examples:
      #   game-session %command%
      #   game-session-gamemode %command%
      (pkgs.writeShellScriptBin "game-session" ''
        exec "$@"
      '')
      (pkgs.writeShellScriptBin "game-session-gamemode" ''
        exec gamemoderun "$@"
      '')
    ]
    ++ lib.optionals (perf.mangohud or true) [
      # Steam launch options example:
      #   game-session-mangohud %command%
      (pkgs.writeShellScriptBin "game-session-mangohud" ''
        exec mangohud gamemoderun "$@"
      '')
      pkgs.goverlay
    ]
    ++ lib.optionals rockstarEnabled [
      (pkgs.writeShellScriptBin "rockstar-steam-setup" ''
        set -eu

        base_dir="$HOME/Games/rockstar"
        download_dir="$base_dir/downloads"
        prefix_dir="$base_dir/prefix"
        installer="$download_dir/Rockstar-Games-Launcher.exe"
        installer_url="https://gamedownloads.rockstargames.com/public/installer/Rockstar-Games-Launcher.exe"

        mkdir -p "$download_dir" "$prefix_dir"

        if [ ! -f "$installer" ]; then
          echo "Downloading Rockstar Games Launcher installer..."
          ${pkgs.curl}/bin/curl -fL "$installer_url" -o "$installer"
        fi

        echo
        echo "Add installer as non-Steam game:"
        echo "  $installer"
        echo
        echo "Recommended Steam Launch Options for installer and launcher:"
        echo "  STEAM_COMPAT_DATA_PATH=$prefix_dir game-session-gamemode %command%"
        echo
        echo "Optional with MangoHud:"
        echo "  STEAM_COMPAT_DATA_PATH=$prefix_dir game-session-mangohud %command%"
      '')
    ]
    ++ lib.optionals (controllers.dualsense or true) [ pkgs.dualsensectl ];

  home.file.".config/MangoHud/MangoHud.conf" = lib.mkIf (perf.mangohud or true) {
    text = ''
      preset=1
      font_size=30
      background_alpha=0.0
    '';
  };
}
