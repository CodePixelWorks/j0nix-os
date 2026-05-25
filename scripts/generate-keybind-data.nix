# Generates structured keybind data as JSON for documentation.
# Usage: nix eval --impure --file scripts/generate-keybind-data.nix
# Must be run from the repository root.
let
  # Determine repo root from the script directory (this file lives in scripts/)
  repoRoot = builtins.dirOf (builtins.toPath ./.);

  # Import the repo flake to get lib, settings, etc.
  flake = builtins.getFlake (toString repoRoot);
  system = builtins.currentSystem;
  pkgs = flake.inputs.nixpkgs.legacyPackages.${system};
  lib = pkgs.lib;

  # ---------------------------------------------------------------------------
  # Load keybind lib helpers
  # ---------------------------------------------------------------------------
  keybindLib = import (repoRoot + "/nix/user/wm/hyprland/config/keybinds/lib.nix") { inherit lib; };

  # ---------------------------------------------------------------------------
  # Mock dependencies for core.nix evaluation
  # ---------------------------------------------------------------------------
  homeBinDir = "$HOME/.local/bin";
  appExec = x: x;
  preferredTerminalCmd = "foot";
  keybindHelpCommand = "wm-keybind-help";
  layoutToggleBind = null;
  overviewToggleBind = null;
  dmsOverviewEnabled = false;
  keepassEnabled = false;
  keepassWorkspaceEnable = false;
  keepassToggleBind = null;
  minimizerEnabled = false;
  minimizerToggleBind = null;
  minimizerRestoreBind = null;
  minimizerMenuBind = null;
  minimizerToggleCommand = null;
  minimizerRestoreCommand = null;
  minimizerMenuCommand = null;
  keybindDiagnosticsEnable = false;
  toggleableOutputBindLines = [ ];

  # Minimal workspace binds for mock
  wsRange = lib.range 1 10;
  workspaceSwitchBinds = lib.concatMap (i:
    let key = if i == 10 then "0" else toString i;
    in [ "\$mainMod, ${key}, workspace, ${toString i}" ]
  ) wsRange;
  workspaceMoveBinds = lib.concatMap (i:
    let key = if i == 10 then "0" else toString i;
    in [ "\$mainMod ALT, ${key}, movetoworkspace, ${toString i}" ]
  ) wsRange;

  # ---------------------------------------------------------------------------
  # Evaluate core binds
  # ---------------------------------------------------------------------------
  coreModule = import (repoRoot + "/nix/user/wm/hyprland/config/keybinds/core.nix") {
    inherit lib homeBinDir appExec preferredTerminalCmd keybindHelpCommand;
    inherit layoutToggleBind overviewToggleBind dmsOverviewEnabled;
    inherit keepassEnabled keepassWorkspaceEnable keepassToggleBind;
    inherit minimizerEnabled minimizerToggleBind minimizerRestoreBind minimizerMenuBind;
    inherit minimizerToggleCommand minimizerRestoreCommand minimizerMenuCommand;
    inherit keybindDiagnosticsEnable toggleableOutputBindLines;
    inherit workspaceSwitchBinds workspaceMoveBinds;
  };

  parseBindList = type: lines:
    map (line: (keybindLib.parseBindString line) // { _type = type; })
      lines;

  allCore =
    parseBindList "bind" coreModule.coreBinds ++
    parseBindList "bind" coreModule.baseBind ++
    parseBindList "binde" coreModule.baseBinde ++
    parseBindList "bindm" coreModule.baseBindm ++
    parseBindList "bindl" coreModule.baseBindl ++
    parseBindList "bindle" coreModule.baseBindle;

  # ---------------------------------------------------------------------------
  # Evaluate shell binds
  # ---------------------------------------------------------------------------
  shellModule = import (repoRoot + "/nix/user/wm/hyprland/config/keybinds/shells.nix") {
    launcherAppExec = x: x;
    settings = { preferredBrowser = "chromium"; preferredEditor = "nvim"; };
    preferredFileManager = "nautilus";
  };

  caelestiaData = shellModule.caelestia or { };

  parseShellBinds = type: lines:
    map (line: (keybindLib.parseBindString line) // { _type = type; _shell = "caelestia"; })
      lines;

  allShell =
    parseShellBinds "bind"   (caelestiaData.bind   or [ ]) ++
    parseShellBinds "bindi"  (caelestiaData.bindi  or [ ]) ++
    parseShellBinds "bindl"  (caelestiaData.bindl  or [ ]) ++
    parseShellBinds "bindle" (caelestiaData.bindle or [ ]) ++
    parseShellBinds "binde"  (caelestiaData.binde or [ ]) ++
    parseShellBinds "bindr"  (caelestiaData.bindr  or [ ]) ++
    parseShellBinds "bindm"  (caelestiaData.bindm  or [ ]);

  # ---------------------------------------------------------------------------
  # Categorize and return
  # ---------------------------------------------------------------------------
  allParsed = allCore ++ allShell;
in
keybindLib.categorizeBinds allParsed
