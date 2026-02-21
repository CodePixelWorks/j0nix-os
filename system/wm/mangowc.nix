{ lib, pkgs, settings, ... }:
let
  selectedDisplayManager = settings.displayManager or "sddm";
  useGreetd = selectedDisplayManager == "greetd";
  useSddm = selectedDisplayManager == "sddm";
  useHyprlandModule = builtins.elem "hyprland" (settings.wms or [ ]);

  selectedGreetdGreeterRaw = (settings.greetd or { }).greeter or "tuigreet";
  selectedGreetdGreeter =
    if selectedGreetdGreeterRaw == "darkmaterialshell" then
      "dms-greeter"
    else
      selectedGreetdGreeterRaw;
  regreetPackage = if pkgs ? regreet then pkgs.regreet else pkgs.greetd.regreet;

  mangoPkg = pkgs.mangowc;
  mangoExe = lib.getExe mangoPkg;
  mangoStart = lib.getExe (pkgs.writeShellScriptBin "start-mangowc" ''
    export XDG_SESSION_TYPE=wayland
    export XDG_CURRENT_DESKTOP=MangoWC
    export XDG_SESSION_DESKTOP=mangowc
    export DESKTOP_SESSION=mangowc

    if command -v systemctl >/dev/null 2>&1; then
      systemctl --user start graphical-session.target >/dev/null 2>&1 || true
      systemctl --user start mangowc-shell.service >/dev/null 2>&1 || true
    fi

    exec ${mangoExe}
  '');

  mangowcSessionPackage = (pkgs.writeTextDir "share/wayland-sessions/mangowc.desktop" ''
    [Desktop Entry]
    Name=MangoWC
    Comment=Minimal wlroots compositor
    TryExec=${mangoStart}
    Exec=${mangoStart}
    Type=Application
    DesktopNames=MangoWC
  '').overrideAttrs (old: {
    passthru = (old.passthru or { }) // {
      providedSessions = [ "mangowc" ];
    };
  });

  mangoGreeterConfigPath = "/etc/greetd/mango.conf";
  dmsGreeterMangoCommand = "/run/current-system/sw/bin/dms-greeter --command mango -C ${mangoGreeterConfigPath}";
in {
  imports = [
    ./common/wayland.nix
  ];

  services.displayManager.sddm = lib.mkIf (!useHyprlandModule && useSddm) {
    enable = true;
    wayland.enable = true;
    theme = "sddm-astronaut-theme";
    extraPackages = [ pkgs.sddm-astronaut ];
  };

  services.displayManager.defaultSession = lib.mkIf (!useHyprlandModule && useSddm) "mangowc";
  services.displayManager.sessionPackages = [ mangowcSessionPackage ];

  services.greetd = lib.mkIf (!useHyprlandModule && useGreetd) {
    enable = true;
    settings.default_session = lib.mkMerge [
      (lib.mkIf (selectedGreetdGreeter == "tuigreet") {
        user = settings.username;
        command = "${lib.getExe pkgs.tuigreet} --time --cmd ${mangoStart}";
      })
      (lib.mkIf (selectedGreetdGreeter == "regreet") {
        user = "greeter";
        command = "${lib.getExe pkgs.cage} -s -mlast -- ${lib.getExe regreetPackage}";
      })
      (lib.mkIf (selectedGreetdGreeter == "dms-greeter") {
        user = "greeter";
        command = dmsGreeterMangoCommand;
      })
    ];
  };

  environment.etc."greetd/mango.conf" = lib.mkIf (!useHyprlandModule && useGreetd && selectedGreetdGreeter == "dms-greeter") {
    text = ''
      env = DMS_RUN_GREETER,1
    '';
    mode = "0444";
  };

  environment.systemPackages = [
    mangoPkg
    pkgs.xdg-desktop-portal-wlr
  ];

  xdg.portal = {
    enable = true;
    xdgOpenUsePortal = true;
    extraPortals = [ pkgs.xdg-desktop-portal-wlr ];
    config = {
      common.default = [ "wlr" "gtk" ];
      mangowc.default = [ "wlr" "gtk" ];
    };
  };
}
