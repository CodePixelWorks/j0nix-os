{
  lib,
}:
let
  # ---------------------------------------------------------------------------
  # Keybind Data Model
  # ---------------------------------------------------------------------------
  # A bind is an attrset:
  #   { mods = "SUPER"; key = "q"; dispatcher = "killactive"; arg = null; }
  #   { mods = "SUPER SHIFT"; key = "f"; dispatcher = "fullscreen"; arg = "1"; }
  #   { mods = ""; key = "XF86AudioMute"; dispatcher = "exec"; arg = "wpctl set-mute @DEFAULT_AUDIO_SINK@ toggle"; }
  #
  # Rendering follows Hyprland bind syntax:
  #   <mods>, <key>, <dispatcher>, <argument>
  #
  # Special bind types add prefixes to <mods> for rendering, e.g.  
  #   binde → <mods>_<key>, <dispatcher>, <argument>  (repeating)
  #   bindm → <mods>_<key>, <dispatcher>               (mouse)
  #   bindl → <mods>_<key>, <dispatcher>, <argument>  (locked)

  hasValue = value: value != null && value != "";
  trim = lib.strings.trim;

  # ---------------------------------------------------------------------------
  # Directional Keys (h/j/k/l)
  # ---------------------------------------------------------------------------
  directionalKeys = [
    { key = "h"; direction = "l"; label = "left";  resizeDelta = "-60 0"; resizeLabel = "shrink width"; }
    { key = "j"; direction = "d"; label = "down";  resizeDelta = "0 60";  resizeLabel = "grow height"; }
    { key = "k"; direction = "u"; label = "up";    resizeDelta = "0 -60"; resizeLabel = "shrink height"; }
    { key = "l"; direction = "r"; label = "right"; resizeDelta = "60 0";  resizeLabel = "grow width"; }
  ];

  # ---------------------------------------------------------------------------
  # Render: attrset → Hyprland bind string
  # ---------------------------------------------------------------------------
  mkBindString =
    { mods ? ""
    , key
    , dispatcher
    , arg ? null
    }:
    let
      modsPart = if mods != "" then mods else "";
      argPart = if arg != null && arg != "" then ", ${arg}" else "";
    in
    if modsPart != "" then
      "${modsPart}, ${key}, ${dispatcher}${argPart}"
    else
      "${key}, ${dispatcher}${argPart}";

  # Convenience wrapper for $mainMod binds
  mkMain =
    { extraMods ? ""
    , key
    , dispatcher
    , arg ? null
    , description ? null  # for documentation, ignored in rendering
    }:
    let
      mods = if extraMods != "" then "$mainMod ${extraMods}" else "$mainMod";
    in
    { inherit mods key dispatcher arg description; };

  # Convenience wrapper for binds without mods
  mkSimple =
    { key
    , dispatcher
    , arg ? null
    , description ? null
    }:
    { mods = ""; inherit key dispatcher arg description; };

  # ---------------------------------------------------------------------------
  # Batch render helpers
  # ---------------------------------------------------------------------------
  renderBindList = binds: map (b: mkBindString b) binds;

  # ---------------------------------------------------------------------------
  # Parsing: string bind → attrset (inverse of mkBindString)
  # ---------------------------------------------------------------------------
  # ---------------------------------------------------------------------------
  # Parsing: string bind → attrset
  # ---------------------------------------------------------------------------
  # Hyprland bind syntax: [mods], key, dispatcher, arg1, arg2, ...
  # If no mods: key, dispatcher, arg1, arg2, ...
  parseBindString = s:
    let
      parts = map trim (lib.splitString "," s);
      n = builtins.length parts;
      # Parts 0..(n-4) are mods (when there are enough parts for key+dispatcher)
      # Simple rule: first part = mods, second = key, third = dispatcher, rest = args
      mods_ = if n > 0 then builtins.elemAt parts 0 else "";
      key_ = if n > 1 then builtins.elemAt parts 1 else "";
      dispatcher_ = if n > 2 then builtins.elemAt parts 2 else "";
      argument_ =
        if n > 3 then
          lib.concatStringsSep ", " (lib.drop 3 parts)
        else
          null;
    in
    {
      mods = mods_;
      key = key_;
      dispatcher = dispatcher_;
      arg = if argument_ != "" then argument_ else null;
    };

  # ---------------------------------------------------------------------------
  # Bind type flags (for documentation / analysis, not rendering)
  # ---------------------------------------------------------------------------
  bindTypeFlags = {
    bind  = { };
    bindi = { ignore_mods = true; };
    bindin = { ignore_mods = true; non_consuming = true; };
    binde = { repeating = true; };
    bindl = { locked = true; };
    bindle = { locked = true; repeating = true; };
    bindr = { release = true; };
    bindm = { mouse = true; };
  };

  # Add type metadata to bind attrsets
  tagBindType = type: binds: map (b: b // { _type = type; _flags = bindTypeFlags.${type} or { }; }) binds;

  # ---------------------------------------------------------------------------
  # Group binds by category for documentation
  # ---------------------------------------------------------------------------
  categorizeBinds = binds:
    let
      # Heuristic categorization based on dispatcher and keywords
      catOf = b:
        let
          d = b.dispatcher or "";
          arg = b.arg or "";
          mods = b.mods or "";
          key = b.key or "";
          full = "${mods} ${key} ${d} ${arg}";
        in
        if lib.hasPrefix "workspace" d then "Navigation"
        else if lib.hasPrefix "movefocus" d || lib.hasPrefix "movewindow" d then "Window Management"
        else if lib.hasPrefix "resizeactive" d || lib.hasPrefix "splitratio" d then "Resizing"
        else if lib.hasPrefix "layoutmsg" d then "Layout"
        else if lib.hasPrefix "fullscreen" d || lib.hasPrefix "togglefloating" d then "Window State"
        else if d == "killactive" then "Window State"
        else if d == "exit" then "Session"
        else if d == "exec" && (lib.hasInfix "screenshot" arg || key == "Print") then "Screenshot"
        else if d == "exec" && (lib.hasInfix "volume" arg || lib.hasInfix "mute" arg || lib.hasPrefix "XF86Audio" key) then "Media"
        else if d == "exec" && (lib.hasInfix "brightness" arg || lib.hasPrefix "XF86MonBrightness" key) then "Media"
        else if d == "exec" && (lib.hasInfix "clipboard" arg || lib.hasInfix "emoji" arg) then "Launcher"
        else if d == "exec" && (lib.hasInfix "lock" arg || lib.hasInfix "caelestia:session" arg) then "Session"
        else if d == "global" then "Shell"
        else if d == "exec" then "App Launch"
        else "Other";

      allCats = lib.unique (map catOf binds);
    in
    lib.listToAttrs (map (cat: {
      name = cat;
      value = lib.filter (b: catOf b == cat) binds;
    }) allCats);

in
{
  inherit
    directionalKeys
    mkBindString
    mkMain
    mkSimple
    renderBindList
    parseBindString
    bindTypeFlags
    tagBindType
    categorizeBinds
    hasValue
    trim
    ;
}
