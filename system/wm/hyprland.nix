{ inputs, pkgs, lib, settings, ... }:
let
  dm = import ../lib/display-manager.nix { inherit lib; };
  greetdVariants = import ./display-manager/greetd/variants.nix { inherit lib pkgs; };
  users = settings.users or [ settings.username ];
  primaryUser = builtins.head users;
  userOverrides = settings.userSettings or { };
  useUWSM = (settings.hyprland or { }).useUWSM or true;
  hyprlandSessionName = if useUWSM then "hyprland-uwsm" else "hyprland";
  selectedDisplayManager = dm.resolveDisplayManager settings;
  useGreetd = selectedDisplayManager == "greetd";
  useSddm = selectedDisplayManager == "sddm";
  useGdm = selectedDisplayManager == "gdm";

  selectedGreetdGreeter = dm.resolveGreetdGreeter settings;
  regreetCompositor = dm.resolveRegreetCompositor settings;

  useDankMaterialShell = useGreetd && selectedGreetdGreeter == "dms-greeter";
  hasDmsPackage =
    (inputs.dank-material-shell ? packages)
    && (builtins.hasAttr pkgs.stdenv.hostPlatform.system inputs.dank-material-shell.packages)
    && (inputs.dank-material-shell.packages.${pkgs.stdenv.hostPlatform.system} ? default);
  dmsPackage =
    if hasDmsPackage then
      inputs.dank-material-shell.packages.${pkgs.stdenv.hostPlatform.system}.default
    else
      null;
  useNvidia = ((settings.drivers or { }).nvidia or { }).enable or false;
  regreetHyprlandConfigPath = "/etc/regreet/hyprland.conf";
  dmsGreeterHyprConfigPath = "/etc/greetd/hypr.conf";
  dmsGreeterCommand =
    "${if hasDmsPackage then lib.getExe' dmsPackage "dms-greeter" else "/run/current-system/sw/bin/dms-greeter"} --command hyprland -C ${dmsGreeterHyprConfigPath}";
  hyprlandUwsmSessionPackage = (pkgs.writeTextDir "share/wayland-sessions/hyprland-uwsm.desktop" ''
    [Desktop Entry]
    Name=Hyprland (UWSM)
    Comment=Hyprland via UWSM
    TryExec=${lib.getExe pkgs.uwsm}
    Exec=${lib.getExe pkgs.uwsm} start hyprland.desktop
    Type=Application
    DesktopNames=Hyprland
  '').overrideAttrs (old: {
    passthru = (old.passthru or { }) // {
      providedSessions = [ "hyprland-uwsm" ];
    };
  });
  blackDonWallpapers = pkgs.stdenvNoCC.mkDerivation {
    pname = "black-don-wallpapers";
    version = "1.0.0";
    src = ../../wallpapers/black-don;
    dontBuild = true;
    installPhase = ''
      mkdir -p "$out/share/wallpapers"
      cp -r "$src"/. "$out/share/wallpapers/"
    '';
  };

  cursorTheme = "Bibata-Modern-Classic";
  cursorSize = 24;

  greetdEnvironments =
    [ "${hyprlandSessionName}.desktop" ]
    ++ lib.optional useUWSM "hyprland.desktop"
    ++ lib.optional (!useUWSM) "hyprland-uwsm.desktop"
    ++ lib.optional (builtins.elem "mangowc" settings.wms) "mangowc.desktop"
    ++ lib.optional (builtins.elem "niri" settings.wms) "niri.desktop"
    ++ lib.optional (builtins.elem "gnome" settings.wms) "gnome.desktop";

  regreetCommand =
    if regreetCompositor == "hyprland"
    then "start-hyprland -- -c ${regreetHyprlandConfigPath}"
    else null;
  sessionCommandForWMS = wms:
    if wms == "hyprland" then
      if useUWSM then
        "${lib.getExe pkgs.uwsm} start hyprland.desktop"
      else
        "start-hyprland"
    else if wms == "mangowc" then
      "start-mangowc"
    else if wms == "niri" then
      "start-niri"
    else if wms == "gnome" then
      "gnome-session"
    else if useUWSM then
      "${lib.getExe pkgs.uwsm} start hyprland.desktop"
    else
      "start-hyprland";
  userCaseBranches = lib.concatStringsSep "\n" (map (username:
    let
      userCfg = userOverrides.${username} or { };
      defaultWMS = userCfg.defaultWMS or "hyprland";
    in
    "  ${username}) exec ${sessionCommandForWMS defaultWMS} ;;"
  ) users);
  autoWmScript = pkgs.writeShellScriptBin "auto-wm-session" ''
    target_user="''${1:-''${USER:-${primaryUser}}}"

    case "$target_user" in
${userCaseBranches}
      *) exec ${sessionCommandForWMS "hyprland"} ;;
    esac
  '';
in {
  imports =
    [
      ./common/wayland.nix
    ]
    ++ lib.optional useDankMaterialShell inputs.dank-material-shell.nixosModules.greeter;

  services.displayManager.sddm = lib.mkIf useSddm {
    enable = true;
    wayland.enable = true;
    theme = "sddm-astronaut-theme";
    extraPackages = [ pkgs.sddm-astronaut ];
  };

  services.xserver.displayManager.gdm.enable = lib.mkIf useGdm true;

  services.displayManager.defaultSession = lib.mkIf useSddm hyprlandSessionName;
  services.displayManager.sessionPackages = lib.optional (useGreetd && selectedGreetdGreeter == "dms-greeter" && useUWSM) hyprlandUwsmSessionPackage;

  services.greetd = lib.mkIf useGreetd {
    enable = true;
    settings.default_session = lib.mkMerge [
      (lib.mkIf (selectedGreetdGreeter == "tuigreet") {
        inherit (greetdVariants.tuigreet {
          user = primaryUser;
          sessionCommand = lib.getExe autoWmScript;
        }) user command;
      })
      (lib.mkIf (selectedGreetdGreeter == "regreet") {
        inherit (greetdVariants.regreet {
          compositor = regreetCompositor;
          hyprlandCommand = regreetCommand;
        }) user command;
      })
      (lib.mkIf (selectedGreetdGreeter == "dms-greeter") {
        inherit (greetdVariants.dmsGreeter {
          command = dmsGreeterCommand;
        }) user command;
      })
    ];
  };

  programs.regreet.enable = useGreetd && selectedGreetdGreeter == "regreet";

  assertions = [
    {
      assertion = builtins.elem selectedDisplayManager dm.validDisplayManagers;
      message = "settings.displayManager must be one of: greetd, sddm, gdm";
    }
    {
      assertion = (!useGreetd) || builtins.elem selectedGreetdGreeter dm.validGreetdGreeters;
      message = "settings.greetd.greeter must be one of: tuigreet, regreet, dms-greeter (legacy alias: darkmaterialshell)";
    }
    {
      assertion = (!useGreetd) || builtins.elem regreetCompositor dm.validRegreetCompositors;
      message = "settings.greetd.regreetCompositor must be one of: cage, hyprland";
    }
    {
      assertion = (!useDankMaterialShell) || hasDmsPackage;
      message = "greetd.greeter=dms-greeter requires inputs.dank-material-shell.packages.<system>.default to be available";
    }
  ];

  environment.systemPackages = with pkgs; [
    (writeShellScriptBin "start-mangowc" ''
      export XDG_SESSION_TYPE=wayland
      export XDG_CURRENT_DESKTOP=MangoWC
      export XDG_SESSION_DESKTOP=mangowc
      export DESKTOP_SESSION=mangowc

      if command -v systemctl >/dev/null 2>&1; then
        systemctl --user start graphical-session.target >/dev/null 2>&1 || true
      fi

      exec ${lib.getExe pkgs.mangowc}
    '')
    brightnessctl
    bibata-cursors
    btop
    blackDonWallpapers
  ] ++ lib.optional (useDankMaterialShell && hasDmsPackage) dmsPackage;

  environment.sessionVariables = {
    XCURSOR_THEME = cursorTheme;
    XCURSOR_SIZE = toString cursorSize;
  } // lib.optionalAttrs useNvidia {
    NIXOS_OZONE_WL = "1";
    GBM_BACKEND = "nvidia-drm";
    __GLX_VENDOR_LIBRARY_NAME = "nvidia";
    LIBVA_DRIVER_NAME = "nvidia";
  };

  environment.etc."greetd/environments" = lib.mkIf useGreetd {
    text = (lib.concatStringsSep "\n" greetdEnvironments) + "\n";
    mode = "0444";
  };

  environment.etc."regreet/hyprland.conf" = lib.mkIf (useGreetd && selectedGreetdGreeter == "regreet" && regreetCompositor == "hyprland") {
    text = ''
      misc {
        disable_hyprland_logo = true
        disable_splash_rendering = true
        disable_hyprland_guiutils_check = true
      }

      env = XCURSOR_THEME,${cursorTheme}
      env = XCURSOR_SIZE,${toString cursorSize}
    '';
    mode = "0444";
  };

  environment.etc."greetd/hypr.conf" = lib.mkIf (useGreetd && selectedGreetdGreeter == "dms-greeter") {
    text = ''
      env = DMS_RUN_GREETER,1

      misc {
          disable_hyprland_logo = true
      }
    '';
    mode = "0444";
  };

  programs.hyprland = {
    enable = true;
    withUWSM = useUWSM;
    xwayland.enable = true;
    package = pkgs.hyprland;
    portalPackage = pkgs.xdg-desktop-portal-hyprland;
  };

  nix.settings = {
    substituters = [ "https://hyprland.cachix.org" ];
    trusted-public-keys = [ "hyprland.cachix.org-1:a7pgxzMz7+chwVL3/pzj6jIBMioiJM7ypFP8PwtkuGc=" ];
  };

  xdg.portal = {
    enable = true;
    xdgOpenUsePortal = true;
    config = {
      hyprland.default = [ "hyprland" ];
    };
  };
} // lib.optionalAttrs useDankMaterialShell {
  programs.dank-material-shell.greeter = {
    enable = true;
    compositor.name = "hyprland";
  };
}
