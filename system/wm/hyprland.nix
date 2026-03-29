{
  inputs,
  pkgs,
  lib,
  settings,
  ...
}:
let
  dm = import ./display-manager/contract.nix { inherit lib; };
  resolveEnabledWms = import ../lib/enabled-wms.nix { inherit lib; };
  greetdVariants = import ./display-manager/greetd/variants.nix { inherit lib pkgs; };
  users = builtins.attrNames (settings.userSettings or { });
  hasUsers = users != [ ];
  primaryUser = if hasUsers then builtins.head users else "root";
  enabledWms = resolveEnabledWms settings;
  userOverrides = settings.userSettings or { };
  useUWSM = (settings.hyprland or { }).useUWSM or true;
  hyprlandSessionName = if useUWSM then "hyprland-uwsm" else "hyprland";
  selectedDisplayManager = dm.resolveDisplayManager settings;
  useGreetd = selectedDisplayManager == "greetd";
  useSddm = selectedDisplayManager == "sddm";
  useGdm = selectedDisplayManager == "gdm";

  selectedGreetdGreeter = dm.resolveGreetdGreeter settings;
  regreetCompositor = dm.resolveRegreetCompositor settings;
  greetdUsesConfigurableCompositor = builtins.elem selectedGreetdGreeter [
    "regreet"
    "qmlgreet"
  ];

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
  qmlgreetHyprlandConfigPath = "/etc/qmlgreet/hyprland.conf";
  qmlgreetConfigPath = "/etc/qmlgreet/qmlgreet.conf";
  qmlgreetColorSchemePath = "/etc/qmlgreet/j0nix.colors";
  dmsGreeterHyprConfigPath = "/etc/greetd/hypr.conf";
  qmlgreetPackage = pkgs.qmlgreet;
  qmlgreetSettings = (settings.greetd or { }).qmlgreet or { };
  caelestiaThemeSettings = ((settings.programs or { }).caelestia or { }).theme or { };
  qmlgreetMode = settings.colorSchemePreference or (caelestiaThemeSettings.mode or "dark");
  useCatppuccinMochaForGreeter =
    (caelestiaThemeSettings.scheme or (settings.theme or "catppuccin")) == "catppuccin"
    && (caelestiaThemeSettings.flavour or "mocha") == "mocha"
    && qmlgreetMode != "light";
  qmlgreetPalette =
    if useCatppuccinMochaForGreeter then
      {
        buttonBg = "49,50,68";
        buttonAlt = "69,71,90";
        buttonFg = "205,214,244";
        viewBg = "30,30,46";
        viewAlt = "24,24,37";
        viewFg = "205,214,244";
        windowBg = "24,24,37";
        windowAlt = "17,17,27";
        windowFg = "205,214,244";
        headerBg = "17,17,27";
        selectionBg = "203,166,247";
        selectionAlt = "137,180,250";
        selectionFg = "17,17,27";
        tooltipBg = "49,50,68";
        tooltipAlt = "69,71,90";
        tooltipFg = "205,214,244";
        focus = "203,166,247";
        hover = "137,180,250";
        active = "137,180,250";
        inactive = "166,173,200";
        link = "137,180,250";
        visited = "180,190,254";
        negative = "243,139,168";
        neutral = "249,226,175";
        positive = "166,227,161";
        complementaryBg = "17,17,27";
        complementaryAlt = "24,24,37";
        complementaryFg = "205,214,244";
        wmActiveBg = "24,24,37";
        wmActiveBlend = "24,24,37";
        wmActiveFg = "205,214,244";
        wmInactiveBg = "30,30,46";
        wmInactiveBlend = "30,30,46";
        wmInactiveFg = "166,173,200";
      }
    else
      {
        buttonBg = "49,54,59";
        buttonAlt = "59,64,69";
        buttonFg = "239,240,241";
        viewBg = "30,32,36";
        viewAlt = "36,39,44";
        viewFg = "239,240,241";
        windowBg = "24,26,30";
        windowAlt = "30,32,36";
        windowFg = "239,240,241";
        headerBg = "24,26,30";
        selectionBg = "88,101,242";
        selectionAlt = "114,135,253";
        selectionFg = "239,240,241";
        tooltipBg = "49,54,59";
        tooltipAlt = "59,64,69";
        tooltipFg = "239,240,241";
        focus = "88,101,242";
        hover = "114,135,253";
        active = "114,135,253";
        inactive = "175,176,179";
        link = "137,180,250";
        visited = "180,190,254";
        negative = "243,139,168";
        neutral = "249,226,175";
        positive = "166,227,161";
        complementaryBg = "17,19,22";
        complementaryAlt = "24,26,30";
        complementaryFg = "239,240,241";
        wmActiveBg = "24,26,30";
        wmActiveBlend = "24,26,30";
        wmActiveFg = "239,240,241";
        wmInactiveBg = "30,32,36";
        wmInactiveBlend = "30,32,36";
        wmInactiveFg = "175,176,179";
      };
  qmlgreetDefaultSession = qmlgreetSettings.defaultSession or "";
  qmlgreetColorSchemeFile =
    if (qmlgreetSettings.colorSchemePath or null) != null then
      qmlgreetSettings.colorSchemePath
    else
      qmlgreetColorSchemePath;
  qmlgreetBackgroundImage = qmlgreetSettings.backgroundImage or null;
  qmlgreetWallpaperPath =
    if qmlgreetBackgroundImage != null then
      toString qmlgreetBackgroundImage
    else
      (((settings.dms or { }).wallpaper or { }).wallpaperPath or "");
  qmlgreetIconTheme =
    if (qmlgreetSettings.iconTheme or null) != null then
      qmlgreetSettings.iconTheme
    else
      ((settings.iconTheme or { }).name or "");
  qmlgreetFont = qmlgreetSettings.font or "";
  qmlgreetFontSize = toString (qmlgreetSettings.fontSize or 10);
  qmlgreetShowAvatars = if qmlgreetSettings ? showAvatars then qmlgreetSettings.showAvatars else true;
  dmsGreeterCommand = "${
    if hasDmsPackage then
      lib.getExe' dmsPackage "dms-greeter"
    else
      "/run/current-system/sw/bin/dms-greeter"
  } --command hyprland -C ${dmsGreeterHyprConfigPath}";
  hyprlandUwsmSessionPackage =
    (pkgs.writeTextDir "share/wayland-sessions/hyprland-uwsm.desktop" ''
      [Desktop Entry]
      Name=Hyprland (UWSM)
      Comment=Hyprland via UWSM
      TryExec=${lib.getExe pkgs.uwsm}
      Exec=${lib.getExe pkgs.uwsm} start hyprland.desktop
      Type=Application
      DesktopNames=Hyprland
    '').overrideAttrs
      (old: {
        passthru = (old.passthru or { }) // {
          providedSessions = [ "hyprland-uwsm" ];
        };
      });
  cursorTheme = "Bibata-Modern-Classic";
  cursorSize = 24;
  hyprlandPostResumeRecover = pkgs.writeShellScript "hyprland-post-resume-recover" ''
    set -eu

    sleep 2

    for username in ${lib.escapeShellArgs users}; do
      uid="$(${pkgs.coreutils}/bin/id -u "$username" 2>/dev/null || true)"
      [ -n "$uid" ] || continue

      runtime_dir="/run/user/$uid"
      profile_bin="/etc/profiles/per-user/$username/bin"

      [ -S "$runtime_dir/bus" ] || continue

      ${pkgs.util-linux}/bin/runuser -u "$username" -- \
        ${pkgs.coreutils}/bin/env \
        XDG_RUNTIME_DIR="$runtime_dir" \
        DBUS_SESSION_BUS_ADDRESS="unix:path=$runtime_dir/bus" \
        PATH="$profile_bin:/run/current-system/sw/bin:${pkgs.coreutils}/bin:${pkgs.procps}/bin" \
        ${pkgs.bash}/bin/bash -lc '
          if command -v hyprctl >/dev/null 2>&1; then
            hyprctl dispatch dpms on >/dev/null 2>&1 || true
            hyprctl reload >/dev/null 2>&1 || true
          fi

          if [ -x "'"$profile_bin"'/wm-shell-restart-detached" ]; then
            "'"$profile_bin"'/wm-shell-restart-detached" >/dev/null 2>&1 || true
          fi
        ' || true
    done
  '';

  greetdEnvironments = [
    "auto-wm-session.desktop"
    "${hyprlandSessionName}.desktop"
  ]
  ++ lib.optional useUWSM "hyprland.desktop"
  ++ lib.optional (!useUWSM) "hyprland-uwsm.desktop"
  ++ lib.optional (builtins.elem "mangowc" enabledWms) "mangowc.desktop"
  ++ lib.optional (builtins.elem "niri" enabledWms) "niri.desktop"
  ++ lib.optional (builtins.elem "gnome" enabledWms) "gnome.desktop";

  regreetCommand =
    if regreetCompositor == "hyprland" then
      "start-hyprland -- -c ${regreetHyprlandConfigPath}"
    else
      null;
  qmlgreetCommand =
    if regreetCompositor == "hyprland" then
      "start-hyprland -- -c ${qmlgreetHyprlandConfigPath}"
    else
      null;
  startHyprlandSessionScript = pkgs.writeShellScriptBin "start-hyprland-session" ''
    # Graphical-session user target is started by Hyprland exec-once after the compositor is ready.
    if [ "${if useUWSM then "1" else "0"}" = "1" ]; then
      exec ${lib.getExe pkgs.uwsm} start hyprland.desktop "$@"
    fi

    exec start-hyprland "$@"
  '';
  sessionCommandForWMS =
    wms:
    if wms == "hyprland" then
      lib.getExe startHyprlandSessionScript
    else if wms == "mangowc" then
      "start-mangowc"
    else if wms == "niri" then
      "start-niri"
    else if wms == "gnome" then
      "gnome-session"
    else
      lib.getExe startHyprlandSessionScript;
  userCaseBranches = lib.concatStringsSep "\n" (
    map (
      username:
      let
        userCfg = userOverrides.${username} or { };
        defaultWMS = userCfg.defaultWMS or "hyprland";
      in
      "  ${username}) exec ${sessionCommandForWMS defaultWMS} ;;"
    ) users
  );
  autoWmScript = pkgs.writeShellScriptBin "auto-wm-session" ''
        target_user="''${1:-''${USER:-${primaryUser}}}"

        case "$target_user" in
    ${userCaseBranches}
          *) exec ${sessionCommandForWMS "hyprland"} ;;
        esac
  '';
  autoWmSessionPackage =
    (pkgs.writeTextDir "share/wayland-sessions/auto-wm-session.desktop" ''
      [Desktop Entry]
      Name=Auto (User Default)
      Comment=Start the configured desktop for the authenticated user
      TryExec=${lib.getExe autoWmScript}
      Exec=${lib.getExe autoWmScript}
      Type=Application
      DesktopNames=auto-wm-session
    '').overrideAttrs
      (old: {
        passthru = (old.passthru or { }) // {
          providedSessions = [ "auto-wm-session" ];
        };
      });
in
{
  imports = [
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
  services.displayManager.sessionPackages =
    lib.optionals useGreetd [ autoWmSessionPackage ]
    ++ lib.optional (
      useGreetd && selectedGreetdGreeter == "dms-greeter" && useUWSM
    ) hyprlandUwsmSessionPackage;

  services.greetd = lib.mkIf useGreetd {
    enable = true;
    settings.default_session = lib.mkMerge [
      (lib.mkIf (selectedGreetdGreeter == "tuigreet") {
        inherit
          (greetdVariants.tuigreet {
            user = primaryUser;
            sessionCommand = lib.getExe autoWmScript;
          })
          user
          command
          ;
      })
      (lib.mkIf (selectedGreetdGreeter == "regreet") {
        inherit
          (greetdVariants.regreet {
            compositor = regreetCompositor;
            hyprlandCommand = regreetCommand;
          })
          user
          command
          ;
      })
      (lib.mkIf (selectedGreetdGreeter == "qmlgreet") {
        inherit
          (greetdVariants.qmlgreet {
            package = qmlgreetPackage;
            compositor = regreetCompositor;
            configPath = qmlgreetConfigPath;
            hyprlandCommand = qmlgreetCommand;
          })
          user
          command
          ;
      })
      (lib.mkIf (selectedGreetdGreeter == "dms-greeter") {
        inherit
          (greetdVariants.dmsGreeter {
            command = dmsGreeterCommand;
          })
          user
          command
          ;
      })
    ];
  };

  programs.regreet.enable = useGreetd && selectedGreetdGreeter == "regreet";

  assertions = [
    {
      assertion = hasUsers;
      message = "system/wm/hyprland.nix requires at least one entry in settings.userSettings.";
    }
    {
      assertion = builtins.elem selectedDisplayManager dm.validDisplayManagers;
      message = "settings.displayManager must be one of: greetd, sddm, gdm";
    }
    {
      assertion = (!useGreetd) || builtins.elem selectedGreetdGreeter dm.validGreetdGreeters;
      message = "settings.greetd.greeter must be one of: tuigreet, regreet, qmlgreet, dms-greeter (legacy alias: darkmaterialshell)";
    }
    {
      assertion =
        (!useGreetd)
        || (!greetdUsesConfigurableCompositor)
        || builtins.elem regreetCompositor dm.validRegreetCompositors;
      message = "settings.greetd.regreetCompositor must be one of: cage, hyprland";
    }
    {
      assertion =
        (!useGreetd) || (selectedGreetdGreeter != "qmlgreet") || ((qmlgreetSettings.fontSize or 10) > 0);
      message = "settings.greetd.qmlgreet.fontSize must be > 0.";
    }
    {
      assertion = (!useDankMaterialShell) || hasDmsPackage;
      message = "greetd.greeter=dms-greeter requires inputs.dank-material-shell.packages.<system>.default to be available";
    }
  ];

  j0nix.software.systemPackages =
    with pkgs;
    [
      (import ./common/start-mangowc.nix { inherit lib pkgs; })
      brightnessctl
      bibata-cursors
      btop
    ]
    ++ lib.optional (useDankMaterialShell && hasDmsPackage) dmsPackage;

  environment.sessionVariables = {
    XCURSOR_THEME = cursorTheme;
    XCURSOR_SIZE = toString cursorSize;
  }
  // lib.optionalAttrs useNvidia {
    NIXOS_OZONE_WL = "1";
    GBM_BACKEND = "nvidia-drm";
    __GLX_VENDOR_LIBRARY_NAME = "nvidia";
    LIBVA_DRIVER_NAME = "nvidia";
  };

  environment.etc."greetd/environments" = lib.mkIf useGreetd {
    text = (lib.concatStringsSep "\n" greetdEnvironments) + "\n";
    mode = "0444";
  };

  environment.etc."regreet/hyprland.conf" =
    lib.mkIf (useGreetd && selectedGreetdGreeter == "regreet" && regreetCompositor == "hyprland")
      {
        text = ''
          # Greeter sessions should light up every connected display instead of inheriting any user-session monitor policy.
          monitor = ,preferred,auto,1

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

  environment.etc."qmlgreet/j0nix.colors" =
    lib.mkIf (useGreetd && selectedGreetdGreeter == "qmlgreet")
      {
        text = ''
          [ColorEffects:Disabled]
          Color=56,56,56
          ColorAmount=0
          ColorEffect=0
          ContrastAmount=0.65
          ContrastEffect=0
          IntensityAmount=0.1
          IntensityEffect=0

          [ColorEffects:Inactive]
          ChangeSelectionColor=true
          Color=${qmlgreetPalette.inactive}
          ColorAmount=-0.95
          ColorEffect=1
          ContrastAmount=0.4
          ContrastEffect=2
          Enable=true
          IntensityAmount=0
          IntensityEffect=0

          [Colors:Button]
          BackgroundAlternate=${qmlgreetPalette.buttonAlt}
          BackgroundNormal=${qmlgreetPalette.buttonBg}
          DecorationFocus=${qmlgreetPalette.focus}
          DecorationHover=${qmlgreetPalette.hover}
          ForegroundActive=${qmlgreetPalette.active}
          ForegroundInactive=${qmlgreetPalette.inactive}
          ForegroundLink=${qmlgreetPalette.link}
          ForegroundNegative=${qmlgreetPalette.negative}
          ForegroundNeutral=${qmlgreetPalette.neutral}
          ForegroundNormal=${qmlgreetPalette.buttonFg}
          ForegroundPositive=${qmlgreetPalette.positive}
          ForegroundVisited=${qmlgreetPalette.visited}

          [Colors:Complementary]
          BackgroundAlternate=${qmlgreetPalette.complementaryAlt}
          BackgroundNormal=${qmlgreetPalette.complementaryBg}
          DecorationFocus=${qmlgreetPalette.focus}
          DecorationHover=${qmlgreetPalette.hover}
          ForegroundActive=${qmlgreetPalette.active}
          ForegroundInactive=${qmlgreetPalette.inactive}
          ForegroundLink=${qmlgreetPalette.link}
          ForegroundNegative=${qmlgreetPalette.negative}
          ForegroundNeutral=${qmlgreetPalette.neutral}
          ForegroundNormal=${qmlgreetPalette.complementaryFg}
          ForegroundPositive=${qmlgreetPalette.positive}
          ForegroundVisited=${qmlgreetPalette.visited}

          [Colors:Header]
          BackgroundNormal=${qmlgreetPalette.headerBg}

          [Colors:Selection]
          BackgroundAlternate=${qmlgreetPalette.selectionAlt}
          BackgroundNormal=${qmlgreetPalette.selectionBg}
          DecorationFocus=${qmlgreetPalette.focus}
          DecorationHover=${qmlgreetPalette.hover}
          ForegroundActive=${qmlgreetPalette.selectionFg}
          ForegroundInactive=${qmlgreetPalette.selectionFg}
          ForegroundLink=${qmlgreetPalette.selectionFg}
          ForegroundNegative=${qmlgreetPalette.selectionFg}
          ForegroundNeutral=${qmlgreetPalette.selectionFg}
          ForegroundNormal=${qmlgreetPalette.selectionFg}
          ForegroundPositive=${qmlgreetPalette.selectionFg}
          ForegroundVisited=${qmlgreetPalette.selectionFg}

          [Colors:Tooltip]
          BackgroundAlternate=${qmlgreetPalette.tooltipAlt}
          BackgroundNormal=${qmlgreetPalette.tooltipBg}
          DecorationFocus=${qmlgreetPalette.focus}
          DecorationHover=${qmlgreetPalette.hover}
          ForegroundActive=${qmlgreetPalette.active}
          ForegroundInactive=${qmlgreetPalette.inactive}
          ForegroundLink=${qmlgreetPalette.link}
          ForegroundNegative=${qmlgreetPalette.negative}
          ForegroundNeutral=${qmlgreetPalette.neutral}
          ForegroundNormal=${qmlgreetPalette.tooltipFg}
          ForegroundPositive=${qmlgreetPalette.positive}
          ForegroundVisited=${qmlgreetPalette.visited}

          [Colors:View]
          BackgroundAlternate=${qmlgreetPalette.viewAlt}
          BackgroundNormal=${qmlgreetPalette.viewBg}
          DecorationFocus=${qmlgreetPalette.focus}
          DecorationHover=${qmlgreetPalette.hover}
          ForegroundActive=${qmlgreetPalette.active}
          ForegroundInactive=${qmlgreetPalette.inactive}
          ForegroundLink=${qmlgreetPalette.link}
          ForegroundNegative=${qmlgreetPalette.negative}
          ForegroundNeutral=${qmlgreetPalette.neutral}
          ForegroundNormal=${qmlgreetPalette.viewFg}
          ForegroundPositive=${qmlgreetPalette.positive}
          ForegroundVisited=${qmlgreetPalette.visited}

          [Colors:Window]
          BackgroundAlternate=${qmlgreetPalette.windowAlt}
          BackgroundNormal=${qmlgreetPalette.windowBg}
          DecorationFocus=${qmlgreetPalette.focus}
          DecorationHover=${qmlgreetPalette.hover}
          ForegroundActive=${qmlgreetPalette.active}
          ForegroundInactive=${qmlgreetPalette.inactive}
          ForegroundLink=${qmlgreetPalette.link}
          ForegroundNegative=${qmlgreetPalette.negative}
          ForegroundNeutral=${qmlgreetPalette.neutral}
          ForegroundNormal=${qmlgreetPalette.windowFg}
          ForegroundPositive=${qmlgreetPalette.positive}
          ForegroundVisited=${qmlgreetPalette.visited}

          [General]
          ColorScheme=j0nix-greeter
          Name=j0nix Greeter
          shadeSortColumn=true

          [KDE]
          contrast=0

          [WM]
          activeBackground=${qmlgreetPalette.wmActiveBg}
          activeBlend=${qmlgreetPalette.wmActiveBlend}
          activeForeground=${qmlgreetPalette.wmActiveFg}
          inactiveBackground=${qmlgreetPalette.wmInactiveBg}
          inactiveBlend=${qmlgreetPalette.wmInactiveBlend}
          inactiveForeground=${qmlgreetPalette.wmInactiveFg}
        '';
        mode = "0444";
      };

  environment.etc."qmlgreet/qmlgreet.conf" =
    lib.mkIf (useGreetd && selectedGreetdGreeter == "qmlgreet")
      {
        text = ''
          # Default values for QMLGreet
          # qmlgreet.conf 2026 (c) Nitrux Latinoamericana S.C.

          [General]
          # Default session (leave empty to use first available)
          # Put the exact name of the session as it appears in the list (e.g., Hyprland, or Hyprland (uwsm-managed)).
          DefaultSession=${qmlgreetDefaultSession}

          [Appearance]
          # Path to KDE color scheme file (leave empty to use a default color scheme)
          ColorScheme=${qmlgreetColorSchemeFile}

          # Path to background image (leave empty for solid color)
          BackgroundImage=${qmlgreetWallpaperPath}

          # Icon theme to use (leave empty to use hicolor)
          IconTheme=${qmlgreetIconTheme}

          # Font to use (leave empty to use Noto Sans)
          Font=${qmlgreetFont}

          # Font size to use (leave empty to use a size of 10)
          FontSize=${qmlgreetFontSize}

          [Behavior]
          # Show user avatars (true/false)
          ShowAvatars=${if qmlgreetShowAvatars then "true" else "false"}
        '';
        mode = "0444";
      };

  environment.etc."qmlgreet/hyprland.conf" =
    lib.mkIf (useGreetd && selectedGreetdGreeter == "qmlgreet" && regreetCompositor == "hyprland")
      {
        text = ''
          # Greeter sessions should light up every connected display instead of inheriting any user-session monitor policy.
          monitor = ,preferred,auto,1

          general {
            gaps_in = 0
            gaps_out = 0
            border_size = 0
          }

          decoration {
            rounding = 0
            active_opacity = 0.97
            inactive_opacity = 0.97
            fullscreen_opacity = 0.97

            blur {
              enabled = true
              size = 2
              passes = 1
            }
          }

          misc {
            disable_hyprland_logo = true
            disable_splash_rendering = true
            disable_hyprland_guiutils_check = true
          }

          env = XCURSOR_THEME,${cursorTheme}
          env = XCURSOR_SIZE,${toString cursorSize}

          exec-once = ${lib.getExe qmlgreetPackage} -c ${qmlgreetConfigPath}
        '';
        mode = "0444";
      };

  environment.etc."greetd/hypr.conf" =
    lib.mkIf (useGreetd && selectedGreetdGreeter == "dms-greeter")
      {
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
    extraPortals = [
      pkgs.xdg-desktop-portal-gtk
      pkgs.kdePackages.xdg-desktop-portal-kde
    ];
    config = {
      common.default = [ "gtk" ];
      hyprland = {
        default = [
          "hyprland"
          "gtk"
          "kde"
        ];
        "org.freedesktop.impl.portal.ScreenCast" = [ "hyprland" ];
        "org.freedesktop.impl.portal.FileChooser" = [ "kde" ];
        "org.freedesktop.impl.portal.Settings" = [ "gtk" ];
        "org.freedesktop.impl.portal.Secret" = [ "gnome-keyring" ];
      };
    };
  };

  powerManagement.resumeCommands = ''
    ${hyprlandPostResumeRecover}
  '';
}
// lib.optionalAttrs useDankMaterialShell {
  programs.dank-material-shell.greeter = {
    enable = true;
    compositor.name = "hyprland";
  };
}
