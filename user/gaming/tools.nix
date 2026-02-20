{ lib, pkgs, settings, ... }:
let
  gaming = settings.gaming or { };
  enabled = gaming.enable or true;
  perf = gaming.performance or { };
  controllers = gaming.controllers or { };
in
lib.mkIf enabled {
  home.packages =
    lib.optionals (perf.mangohud or true) [
      (pkgs.writeShellScriptBin "game-session" ''
        exec "$@"
      '')
      (pkgs.writeShellScriptBin "game-session-mangohud" ''
        exec mangohud "$@"
      '')
      pkgs.goverlay
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
