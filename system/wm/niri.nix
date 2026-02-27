{ lib, pkgs, settings, ... }:
let
  dm = import ../lib/display-manager.nix { inherit lib; };
  greetdVariants = import ./display-manager/greetd/variants.nix { inherit lib pkgs; };
  selectedDisplayManager = dm.resolveDisplayManager settings;
  useGreetd = selectedDisplayManager == "greetd";
  useSddm = selectedDisplayManager == "sddm";
  useHyprlandModule = builtins.elem "hyprland" (settings.wms or [ ]);

  niriStartScript = pkgs.writeShellScriptBin "start-niri" ''
    export XDG_SESSION_TYPE=wayland
    export XDG_CURRENT_DESKTOP=niri
    export XDG_SESSION_DESKTOP=niri
    export DESKTOP_SESSION=niri
    exec ${lib.getExe pkgs.niri}
  '';

  niriSessionPackage = (pkgs.writeTextDir "share/wayland-sessions/niri.desktop" ''
    [Desktop Entry]
    Name=Niri
    Comment=Scrollable-tiling Wayland compositor
    TryExec=${lib.getExe niriStartScript}
    Exec=${lib.getExe niriStartScript}
    Type=Application
    DesktopNames=niri
  '').overrideAttrs (old: {
    passthru = (old.passthru or { }) // {
      providedSessions = [ "niri" ];
    };
  });
in
{
  imports = [
    ./common/wayland.nix
  ];

  services.displayManager.sddm = lib.mkIf (!useHyprlandModule && useSddm) {
    enable = true;
    wayland.enable = true;
    theme = "sddm-astronaut-theme";
    extraPackages = [ pkgs.sddm-astronaut ];
  };

  services.displayManager.defaultSession = lib.mkIf (!useHyprlandModule && useSddm) "niri";
  services.displayManager.sessionPackages = [ niriSessionPackage ];

  services.greetd = lib.mkIf (!useHyprlandModule && useGreetd) {
    enable = true;
    settings.default_session = greetdVariants.tuigreet {
      user = settings.username;
      sessionCommand = lib.getExe niriStartScript;
    };
  };

  programs.niri.enable = true;

  environment.systemPackages = [
    niriStartScript
    pkgs.niri
    pkgs.xdg-desktop-portal-gtk
  ];

  xdg.portal = {
    enable = true;
    xdgOpenUsePortal = true;
    config.niri.default = lib.mkDefault [ "gtk" ];
  };
}
