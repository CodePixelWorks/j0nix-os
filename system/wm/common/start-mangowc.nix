{ lib, pkgs, ... }:
pkgs.writeShellScriptBin "start-mangowc" ''
  export XDG_SESSION_TYPE=wayland
  export XDG_CURRENT_DESKTOP=MangoWC
  export XDG_SESSION_DESKTOP=mangowc
  export DESKTOP_SESSION=mangowc

  if command -v systemctl >/dev/null 2>&1; then
    systemctl --user start graphical-session.target >/dev/null 2>&1 || true
  fi

  exec ${lib.getExe pkgs.mangowc}
''
