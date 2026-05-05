{
  lib,
  settings,
  profileDetails,
  isCaelestiaShell,
  isDmsShell,
  hyprDmsDir,
  hyprlandWindowRules,
  hyprlandKeybinds,
  shellStartupCommand,
  dmsOverviewEnabled,
  dmsOverviewAutostart,
  homeBinDir,
  sessionEnvLines,
  keybindDiagnosticsEnable,
  sessionEnvImportCommand,
  startGraphicalSessionTargetCommand,
  swwwDaemonCommand,
  startupAppsCommand,
  keybindDiagnosticsStartupCommand,
  runtimeMonitorResetCommand,
  managedMonitorLines,
  mainConfigDir,
  shellConfigDir,
}:
let
  renderLines = key: values: lib.concatStringsSep "\n" (map (value: "${key} = ${value}") values);
  staticMonitorLines = profileDetails.hyprlandMonitors or [ ];
  hyprlandCfg = settings.hyprland or { };
  unknownMonitorFallbackRule = hyprlandCfg.unknownMonitorFallbackRule or ",preferred,auto,1";
  hasUnknownMonitorFallbackRule =
    unknownMonitorFallbackRule != null && unknownMonitorFallbackRule != "";
  useNvidia = ((settings.drivers or { }).nvidia or { }).enable or false;

  includePaths = [
    "${mainConfigDir}/00-vars.conf"
    "${mainConfigDir}/05-env.conf"
    "${mainConfigDir}/10-monitors.conf"
    "${mainConfigDir}/11-runtime-monitors.conf"
    "${mainConfigDir}/20-startup.conf"
    "${mainConfigDir}/30-input.conf"
    "${mainConfigDir}/40-general.conf"
    "${mainConfigDir}/50-decoration.conf"
    "${mainConfigDir}/55-render-opengl.conf"
    "${mainConfigDir}/60-misc-debug.conf"
    "${mainConfigDir}/70-window-rules.conf"
    "${mainConfigDir}/80-keybinds.conf"
    "${shellConfigDir}/95-shell.conf"
  ];

  # Fallback rule must come BEFORE specific per-monitor rules.
  # Hyprland processes monitor rules top-to-bottom; later rules override earlier ones.
  # Putting the wildcard first means specific rules (disable, explicit mode/position) win.
  monitorLines =
    lib.optionals hasUnknownMonitorFallbackRule [ unknownMonitorFallbackRule ]
    ++ staticMonitorLines
    ++ managedMonitorLines;

  startupLines = [
    sessionEnvImportCommand
  ]
  ++ [
    startGraphicalSessionTargetCommand
    runtimeMonitorResetCommand
    swwwDaemonCommand
    startupAppsCommand
  ]
  ++ lib.optionals (shellStartupCommand != null) [ shellStartupCommand ]
  ++ lib.optionals (dmsOverviewEnabled && dmsOverviewAutostart) [ "${homeBinDir}/wm-overview-start" ]
  ++ lib.optionals keybindDiagnosticsEnable [ keybindDiagnosticsStartupCommand ];

  bindLines =
    if isCaelestiaShell then
      ''
        # Caelestia binds are declared in shell submap config (95-shell.conf).
      ''
    else
      lib.concatStringsSep "\n" (
        lib.filter (line: line != "") [
          (renderLines "bind" hyprlandKeybinds.effectiveBindLists.bind)
          (renderLines "bindi" hyprlandKeybinds.effectiveBindLists.bindi)
          (renderLines "bindin" hyprlandKeybinds.effectiveBindLists.bindin)
          (renderLines "binde" hyprlandKeybinds.effectiveBindLists.binde)
          (renderLines "bindl" hyprlandKeybinds.effectiveBindLists.bindl)
          (renderLines "bindle" hyprlandKeybinds.effectiveBindLists.bindle)
          (renderLines "bindr" hyprlandKeybinds.effectiveBindLists.bindr)
          (renderLines "bindm" hyprlandKeybinds.effectiveBindLists.bindm)
        ]
      );

  shellLines = lib.concatStringsSep "\n\n" (
    lib.filter (line: line != "") [
      (lib.optionalString isDmsShell ''
        # DMS runtime-generated Hyprland overlays.
        source = ${hyprDmsDir}/colors.conf
        source = ${hyprDmsDir}/cursor.conf
        source = ${hyprDmsDir}/outputs.conf
        source = ${hyprDmsDir}/windowrules.conf
        source = ${hyprDmsDir}/binds.conf
        source = ${hyprDmsDir}/layout.conf
      '')
      (hyprlandKeybinds.shellHyprKeybinds.extraConfig or "")
      hyprlandKeybinds.caelestiaSubmapConfig
    ]
  );
in
{
  inherit includePaths;

  files = {
    "hypr/conf.d/00-vars.conf" = ''
      # ------------------------------------------------------------------
      # j0nix Hyprland
      # Variables
      # ------------------------------------------------------------------
      $mainMod = SUPER
    '';

    "hypr/conf.d/05-env.conf" = ''
      # ------------------------------------------------------------------
      # Session Environment
      # ------------------------------------------------------------------
      ${lib.concatStringsSep "\n" sessionEnvLines}
    '';

    "hypr/conf.d/10-monitors.conf" = ''
      # ------------------------------------------------------------------
      # Startup Monitor Defaults
      # ------------------------------------------------------------------
      # Order: wildcard fallback first, specific per-monitor rules after.
      # Hyprland applies rules top-to-bottom; later rules override earlier ones.
      ${renderLines "monitor" monitorLines}
    '';

    "hypr/conf.d/11-runtime-monitors.conf" = ''
      # ------------------------------------------------------------------
      # Runtime Monitor Overrides
      # ------------------------------------------------------------------
      # This file is intentionally reserved for runtime monitor tooling. Keep
      # it empty in the declarative baseline so the startup monitor defaults
      # remain authoritative until an explicit runtime override is applied.
    '';

    "hypr/conf.d/20-startup.conf" = ''
      # ------------------------------------------------------------------
      # Startup
      # ------------------------------------------------------------------
      ${renderLines "exec-once" startupLines}
    '';

    "hypr/conf.d/30-input.conf" = ''
      # ------------------------------------------------------------------
      # Input
      # ------------------------------------------------------------------
      input {
        kb_layout = ${settings.keyboardLayout or "de"}
        kb_options = ${settings.keyboardOptions or "caps:escape"}
        follow_mouse = true

        touchpad {
          natural_scroll = true
        }
      }
    '';

    "hypr/conf.d/40-general.conf" = ''
      # ------------------------------------------------------------------
      # Tiling / Layout Core
      # ------------------------------------------------------------------
      general {
        gaps_in = 6
        gaps_out = 10
        border_size = 2
        col.active_border = rgba(89b4faff)
        col.inactive_border = rgba(313244ff)
        resize_on_border = true
        extend_border_grab_area = 15
        hover_icon_on_border = true
      }

      dwindle {
        pseudotile = true
        preserve_split = true
      }

      # Keep compositor shortcuts responsive even with client inhibitors.
      binds {
        disable_keybind_grabbing = true
      }
    '';

    "hypr/conf.d/50-decoration.conf" = ''
      # ------------------------------------------------------------------
      # Decoration / Blur / Opacity
      # ------------------------------------------------------------------
      decoration {
        rounding = 8
        active_opacity = 1.0
        inactive_opacity = 0.94
        fullscreen_opacity = 1.0

        blur {
          enabled = true
          size = 8
          passes = 2
        }
      }
    '';

    "hypr/conf.d/55-render-opengl.conf" = ''
      # ------------------------------------------------------------------
      # Render / OpenGL
      # ------------------------------------------------------------------
      ${lib.optionalString useNvidia ''
        # Conservative NVIDIA path to reduce flicker on some displays.
        opengl {
          nvidia_anti_flicker = true
        }

        render {
          direct_scanout = 0
        }

        xwayland {
          force_zero_scaling = true
        }
      ''}
    '';

    "hypr/conf.d/60-misc-debug.conf" = ''
      # ------------------------------------------------------------------
      # Misc Runtime Behavior
      # ------------------------------------------------------------------
      misc {
        vfr = true
        vrr = 0
        animate_manual_resizes = false
        animate_mouse_windowdragging = false
        force_default_wallpaper = 0
        on_focus_under_fullscreen = 2
        allow_session_lock_restore = true
        middle_click_paste = false
        focus_on_activate = true
        session_lock_xray = true
        mouse_move_enables_dpms = true
        key_press_enables_dpms = true
        disable_hyprland_logo = true
        disable_splash_rendering = true
      }

      debug {
        error_position = 1
      }
    '';

    "hypr/conf.d/70-window-rules.conf" = ''
      # ------------------------------------------------------------------
      # Window Rules
      # ------------------------------------------------------------------
      ${renderLines "windowrule" (hyprlandWindowRules.default ++ hyprlandWindowRules.extra)}
    '';

    "hypr/conf.d/80-keybinds.conf" = ''
      # ------------------------------------------------------------------
      # Keybinds
      # ------------------------------------------------------------------
      ${bindLines}
    '';

    "hypr/shells/${
      settings.wmShell or (settings.hyprlandShell or "dank-material-shell")
    }/generated/95-shell.conf" =
      ''
        # ------------------------------------------------------------------
        # Shell-Specific Hyprland Integration
        # ------------------------------------------------------------------
        # Generated per selected shell to avoid cross-shell config collisions.
        ${shellLines}
      '';
  };
}
