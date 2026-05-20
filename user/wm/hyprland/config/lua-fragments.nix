{
  lib,
  settings,
  profileDetails,
  hyprlandKeybinds,
  hyprlandWindowRules,
  sessionEnv,
  startupCommands,
  managedMonitorLines,
  hyprctlExec,
  useUWSM,
}:
let
  trim = lib.strings.trim;
  selectedShell = settings.wmShell or (settings.hyprlandShell or "caelestia-shell");

  luaValue =
    value:
    if builtins.isBool value then
      if value then "true" else "false"
    else if builtins.isInt value || builtins.isFloat value then
      toString value
    else if builtins.isString value then
      builtins.toJSON value
    else if builtins.isList value then
      "{ " + lib.concatStringsSep ", " (map luaValue value) + " }"
    else if builtins.isAttrs value then
      "{ " + lib.concatStringsSep ", " (lib.mapAttrsToList (name: child: "${name} = ${luaValue child}") value) + " }"
    else if value == null then
      "nil"
    else
      throw "Unsupported Lua value type";

  renderLuaConfig = attrs: "hl.config(${luaValue attrs})";
  renderLuaEnv = name: value: "hl.env(${builtins.toJSON name}, ${builtins.toJSON (toString value)})";
  renderExec = command: "  hl.exec_cmd(${builtins.toJSON command})";
  renderWindowRule = rule:
    let
      body = {
        match = rule.match or { };
      } // builtins.removeAttrs rule [ "match" "name" ];
    in
    "hl.window_rule(${luaValue body})";
  renderBindFlags = flags:
    if flags == { } then
      null
    else
      "{ "
      + lib.concatStringsSep ", " (
        lib.mapAttrsToList (
          name: value:
          if builtins.isBool value then
            "${name} = ${if value then "true" else "false"}"
          else
            "${name} = ${builtins.toJSON value}"
        ) flags
      )
      + " }";
  renderBindKeys =
    bind:
    let
      isCatchall = (bind.flags or { }).catchall or false;
      mods = builtins.filter (part: part != "") (lib.splitString " " (bind.mods or ""));
      normalizeMod =
        part:
        let
          upper = lib.toUpper part;
        in
        if part == "$mainMod" then
          "SUPER"
        else if builtins.elem upper [
          "SUPER"
          "SHIFT"
          "CTRL"
          "ALT"
        ] then
          upper
        else
          part;
      normalizedMods = map normalizeMod mods;
      usesMainMod = builtins.elem "SUPER" normalizedMods;
      suffixSegments = (lib.filter (part: part != "SUPER") normalizedMods) ++ [ bind.key ];
      suffix = lib.concatStringsSep " + " suffixSegments;
      nonSuperMods = lib.filter (part: part != "SUPER") normalizedMods;
      modPrefix = lib.concatStringsSep " + " normalizedMods;
    in
    if isCatchall && bind.key == "" then
      if usesMainMod then
        if nonSuperMods == [ ] then
          "mainMod .. \" + \""
        else
          "mainMod .. \" + " + (lib.concatStringsSep " + " nonSuperMods) + " + \""
      else
        builtins.toJSON (modPrefix + lib.optionalString (modPrefix != "") " + ")
    else if usesMainMod then
      if suffix == "" then
        "mainMod"
      else
        "mainMod .. \" + " + suffix + "\""
    else
      builtins.toJSON suffix;
  renderRawDispatchCommand =
    bind:
    let
      dispatcher = bind.dispatcher or "";
      argument = if bind.argument == null || bind.argument == "" then "_" else bind.argument;
    in
    "hyprctl dispatch -- ${dispatcher} ${lib.escapeShellArg argument}";
  renderBindDispatcher =
    bind:
    let
      dispatcher = bind.dispatcher or "";
      argument = bind.argument;
      argumentString = if argument == null then "" else argument;
    in
    if dispatcher == "exec" then
      "hl.dsp.exec_cmd(${builtins.toJSON argumentString})"
    else if dispatcher == "global" then
      "hl.dsp.global(${builtins.toJSON argumentString})"
    else if dispatcher == "movefocus" then
      "hl.dsp.focus({ direction = ${builtins.toJSON argumentString} })"
    else if dispatcher == "workspace" then
      "hl.dsp.focus({ workspace = ${builtins.toJSON argumentString} })"
    else if dispatcher == "movewindow" && (bind.flags.mouse or false) then
      "hl.dsp.window.drag()"
    else if dispatcher == "resizewindow" && (bind.flags.mouse or false) then
      "hl.dsp.window.resize()"
    else if dispatcher == "killactive" then
      "hl.dsp.window.close()"
    else if dispatcher == "togglefloating" then
      "hl.dsp.window.float({ action = \"toggle\" })"
    else if dispatcher == "fullscreen" && argument == "0" then
      "hl.dsp.window.fullscreen({ mode = \"fullscreen\", action = \"toggle\" })"
    else if dispatcher == "fullscreen" && argument == "1" then
      "hl.dsp.window.fullscreen({ mode = \"maximized\", action = \"toggle\" })"
    else if dispatcher == "layoutmsg" then
      "hl.dsp.layout(${builtins.toJSON argumentString})"
    else if dispatcher == "exit" then
      "hl.dsp.exit()"
    else
      "hl.dsp.exec_cmd(${builtins.toJSON (renderRawDispatchCommand bind)})";
  renderBind = bind:
    let
      keysExpr = renderBindKeys bind;
      dispatcherExpr = renderBindDispatcher bind;
      flagsExpr = renderBindFlags (bind.flags or { });
      args =
        [
          keysExpr
          dispatcherExpr
        ]
        ++ lib.optionals (flagsExpr != null) [ flagsExpr ];
    in
    "hl.bind(" + lib.concatStringsSep ", " args + ")";
  renderIndentedBind = bind: "  " + renderBind bind;
  parseMonitorLine =
    line:
    let
      parts = map trim (lib.splitString "," line);
      len = builtins.length parts;
    in
    if len == 0 then
      null
    else
      let
        output = builtins.elemAt parts 0;
      in
      if output == "" then
        {
          output = "";
          mode = "preferred";
          position = "auto";
          scale = "1";
        }
      else if len >= 2 && builtins.elemAt parts 1 == "disable" then
        {
          inherit output;
          disabled = true;
        }
      else if len >= 4 then
        {
          inherit output;
          mode = builtins.elemAt parts 1;
          position = builtins.elemAt parts 2;
          scale = builtins.elemAt parts 3;
        }
      else
        null;

  staticMonitorLines = profileDetails.hyprlandMonitors or [ ];
  allMonitorLines = staticMonitorLines ++ managedMonitorLines;
  monitorEntries = builtins.filter (entry: entry != null) (map parseMonitorLine allMonitorLines);

  inputConfig = {
    input = {
      kb_layout = settings.keyboardLayout or "de";
      kb_options = settings.keyboardOptions or "caps:escape";
      follow_mouse = 1;
      touchpad = {
        natural_scroll = true;
      };
    };
  };

  generalConfig = {
    general = {
      gaps_in = 6;
      gaps_out = 10;
      border_size = 2;
      col = {
        active_border = "rgba(89b4faff)";
        inactive_border = "rgba(313244ff)";
      };
      resize_on_border = true;
      extend_border_grab_area = 15;
      hover_icon_on_border = true;
    };
    dwindle = {
      preserve_split = true;
    };
    binds = {
      disable_keybind_grabbing = true;
    };
  };

  decorationConfig = {
    decoration = {
      rounding = 8;
      active_opacity = 1.0;
      inactive_opacity = 0.94;
      fullscreen_opacity = 1.0;
      blur = {
        enabled = true;
        size = 8;
        passes = 2;
      };
    };
  };

  miscConfig = {
    misc = {
      vrr = 0;
      animate_manual_resizes = false;
      animate_mouse_windowdragging = false;
      force_default_wallpaper = 0;
      on_focus_under_fullscreen = 2;
      allow_session_lock_restore = true;
      middle_click_paste = false;
      focus_on_activate = true;
      session_lock_xray = true;
      mouse_move_enables_dpms = true;
      key_press_enables_dpms = true;
      disable_hyprland_logo = true;
      disable_splash_rendering = true;
    };
    debug = {
      error_position = 1;
    };
  };

  startupLua =
    if startupCommands == [ ] then
      "-- No startup commands generated yet."
    else
      ''
        hl.on("hyprland.start", function()
        ${lib.concatStringsSep "\n" (map renderExec startupCommands)}
        end)
      '';

  monitorLua = lib.concatStringsSep "\n\n" (
    map (
      monitor:
      if monitor ? disabled then
        "hl.monitor(${luaValue { output = monitor.output; disabled = true; }})"
      else
        "hl.monitor(${luaValue { output = monitor.output; mode = monitor.mode; position = monitor.position; scale = monitor.scale; }})"
    ) monitorEntries
  );
  windowRuleLua = lib.concatStringsSep "\n" (map renderWindowRule hyprlandWindowRules.structured);
  keybindLua = lib.concatStringsSep "\n" (map renderBind hyprlandKeybinds.structuredLuaGlobalBinds);
  caelestiaShellLua =
    if selectedShell == "caelestia-shell" then
      ''
        hl.define_submap("global", function()
        ${lib.concatStringsSep "\n" (map renderIndentedBind hyprlandKeybinds.structuredLuaShellBinds)}
        end)

        -- Mirror the pre-Lua setup: keep "global" as the active submap via an
        -- external hyprctl dispatch instead of the crashing in-process Lua call.
        hl.on("hyprland.start", function()
          hl.exec_cmd(${builtins.toJSON "${hyprctlExec} dispatch submap global"})
        end)
      ''
    else
      "";
  shellLua =
    if selectedShell == "dank-material-shell" then
      ''
        error("dank-material-shell is temporarily marked broken during the Hyprland Lua migration. Use caelestia-shell.")
      ''
    else
      caelestiaShellLua;
in
{
  files = {
    "hypr/hyprland.lua" = ''
      -- j0nix Hyprland Lua config.
      local j0nixDir = os.getenv("HOME") .. "/.config/hypr/j0nix"

      dofile(j0nixDir .. "/vars.lua")
      dofile(j0nixDir .. "/env.lua")
      dofile(j0nixDir .. "/monitors.lua")
      dofile(j0nixDir .. "/startup.lua")
      dofile(j0nixDir .. "/input.lua")
      dofile(j0nixDir .. "/general.lua")
      dofile(j0nixDir .. "/decoration.lua")
      dofile(j0nixDir .. "/misc.lua")
      dofile(j0nixDir .. "/window-rules.lua")
      dofile(j0nixDir .. "/keybinds.lua")
      dofile(j0nixDir .. "/shell.lua")
      dofile(j0nixDir .. "/user-overrides.lua")
    '';

    "hypr/j0nix-scaffold.lua" = ''
      -- Compatibility alias for the staged migration path.
      dofile(os.getenv("HOME") .. "/.config/hypr/hyprland.lua")
    '';

    "hypr/j0nix/vars.lua" = ''
      -- Shared constants for the staged Lua config.
      mainMod = "SUPER"
      useUWSM = ${if useUWSM then "true" else "false"}
      return {
        mainMod = mainMod,
        useUWSM = useUWSM,
      }
    '';

    "hypr/j0nix/env.lua" = ''
      -- Session environment scaffold.
      -- Note: production UWSM sessions should keep HYPR* variables in uwsm env files.
      ${lib.concatStringsSep "\n" (lib.mapAttrsToList renderLuaEnv sessionEnv)}
    '';

    "hypr/j0nix/monitors.lua" = ''
      -- Static monitor scaffold generated from the current declarative topology.
      ${if monitorLua == "" then "-- No monitor entries generated." else monitorLua}
    '';

    "hypr/j0nix/startup.lua" = ''
      -- Startup scaffold generated from the current Hyprland startup commands.
      ${startupLua}
    '';

    "hypr/j0nix/input.lua" = ''
      -- Input scaffold.
      ${renderLuaConfig inputConfig}
    '';

    "hypr/j0nix/general.lua" = ''
      -- General compositor/layout scaffold.
      ${renderLuaConfig generalConfig}
    '';

    "hypr/j0nix/decoration.lua" = ''
      -- Decoration scaffold.
      ${renderLuaConfig decorationConfig}
    '';

    "hypr/j0nix/misc.lua" = ''
      -- Misc runtime scaffold.
      ${renderLuaConfig miscConfig}
    '';

    "hypr/j0nix/window-rules.lua" = ''
      -- Window rules scaffold generated from the shared rule model.
      ${windowRuleLua}
    '';

    "hypr/j0nix/keybinds.lua" = ''
      -- Keybind scaffold generated from the shared bind model.
      ${keybindLua}
    '';

    "hypr/j0nix/shell.lua" = ''
      -- Shell-specific staged Lua integration.
      ${if shellLua == "" then "-- No shell-specific Lua overlay for the selected shell." else shellLua}
    '';

    "hypr/j0nix/user-overrides.lua" = ''
      local selectedShell = ${builtins.toJSON selectedShell}
      local overridePath = os.getenv("HOME") .. "/.config/hypr/shell-overrides/" .. selectedShell .. "/user-overrides.lua"
      local ok, err = pcall(dofile, overridePath)
      if not ok then
        local file = io.open(overridePath, "r")
        if file ~= nil then
          file:close()
          error(err)
        end
      end
    '';
  };
}
