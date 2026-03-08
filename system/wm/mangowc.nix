{ lib, pkgs, settings, ... }:
let
  resolveEnabledWms = import ../lib/enabled-wms.nix { inherit lib; };
  users = builtins.attrNames (settings.userSettings or { });
  hasUsers = users != [ ];
  primaryUser = if hasUsers then builtins.head users else "root";
  dm = import ./display-manager/contract.nix { inherit lib; };
  greetdVariants = import ./display-manager/greetd/variants.nix { inherit lib pkgs; };
  selectedDisplayManager = dm.resolveDisplayManager settings;
  useGreetd = selectedDisplayManager == "greetd";
  useSddm = selectedDisplayManager == "sddm";
  useHyprlandModule = builtins.elem "hyprland" (resolveEnabledWms settings);
  manageOwnDisplayManager = !useHyprlandModule;

  selectedGreetdGreeter = dm.resolveGreetdGreeter settings;

  mangoPkg = pkgs.mangowc;
  mangoExe = lib.getExe mangoPkg;
  mangoStart = lib.getExe (pkgs.writeShellScriptBin "start-mangowc" ''
    export XDG_SESSION_TYPE=wayland
    export XDG_CURRENT_DESKTOP=MangoWC
    export XDG_SESSION_DESKTOP=mangowc
    export DESKTOP_SESSION=mangowc

    if command -v systemctl >/dev/null 2>&1; then
      systemctl --user start graphical-session.target >/dev/null 2>&1 || true
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

  services.displayManager.sddm = lib.mkIf (manageOwnDisplayManager && useSddm) {
    enable = true;
    wayland.enable = true;
    theme = "sddm-astronaut-theme";
    extraPackages = [ pkgs.sddm-astronaut ];
  };

  services.displayManager.defaultSession = lib.mkIf (manageOwnDisplayManager && useSddm) "mangowc";
  services.displayManager.sessionPackages = [ mangowcSessionPackage ];

  services.greetd = lib.mkIf (manageOwnDisplayManager && useGreetd) {
    enable = true;
    settings.default_session = lib.mkMerge [
      (lib.mkIf (selectedGreetdGreeter == "tuigreet") {
        inherit (greetdVariants.tuigreet {
          user = primaryUser;
          sessionCommand = mangoStart;
        }) user command;
      })
      (lib.mkIf (selectedGreetdGreeter == "regreet") {
        inherit (greetdVariants.regreet {
          compositor = "cage";
        }) user command;
      })
      (lib.mkIf (selectedGreetdGreeter == "dms-greeter") {
        inherit (greetdVariants.dmsGreeter {
          command = dmsGreeterMangoCommand;
        }) user command;
      })
    ];
  };

  environment.etc."greetd/mango.conf" = lib.mkIf (manageOwnDisplayManager && useGreetd && selectedGreetdGreeter == "dms-greeter") {
    text = ''
      env = DMS_RUN_GREETER,1
    '';
    mode = "0444";
  };

  j0nix.software.systemPackages = [
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

  assertions = [
    {
      assertion = hasUsers;
      message = "system/wm/mangowc.nix requires at least one entry in settings.userSettings.";
    }
    {
      assertion = (!(manageOwnDisplayManager && useGreetd)) || builtins.elem selectedGreetdGreeter dm.validGreetdGreeters;
      message = "settings.greetd.greeter must be one of: tuigreet, regreet, qmlgreet, dms-greeter (legacy alias: darkmaterialshell)";
    }
  ];
}
