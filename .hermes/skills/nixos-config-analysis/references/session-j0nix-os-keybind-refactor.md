# Session: Keybind Module Hierarchy (j0nix-os, May 22 2026)

Refactoring a monolithic `user/wm/hyprland/config/keybinds.nix` (354 lines, all binds in one file) into a clean module hierarchy.

---

## Before / After

| File | Before | After |
|------|--------|-------|
| `user/wm/hyprland/config/keybinds.nix` | 354 lines monolithic: core binds + shell binds + helper functions | ~192 lines orchestrator: imports submodules, merges per bind-type, renders to Hyprland syntax |
| `config/keybinds/lib.nix` | did not exist | Full data model: `parseBindString`, `mkMain`, `mkSimple`, `renderBindList`, `tagBindType`, `categorizeBinds`, `directionalKeys` |
| `config/keybinds/core.nix` | did not exist | Common binds: window mgmt, focus, workspaces, session, diagnostics; returns `coreBinds`, `baseBind`, `baseBinde`, `baseBindm`, `baseBindl`, `baseBindle` |
| `config/keybinds/shells.nix` | did not exist | Per-shell bind attrsets by type: `caelestia = { bind = [...]; binde = [...]; bindl = [...]; bindle = [...]; binde = [...]; bindr = [...]; bindm = [...] }` |
| `config/keybind-diagnostics.nix` | 0 lines | Standalone: `wm-hypr-keybind-probe` + `wm-hypr-keybind-dump` scripts via `pkgs.writeShellScriptBin` |

---

## Actual Architecture (as built)

### 1. Orchestrator (`keybinds.nix`)

Imports `core.nix` and `shells.nix`, merges per bind-type, produces structured + rendered outputs.

```nix
let
  coreBindsModule = import ./keybinds/core.nix { inherit lib homeBinDir appExec ...; };
  shellBindsModule = import ./keybinds/shells.nix { inherit launcherAppExec settings preferredFileManager; };

  baseHyprKeybinds = {
    bind  = coreBindsModule.baseBind;
    binde = coreBindsModule.baseBinde;
    bindm = coreBindsModule.baseBindm;
    bindl = coreBindsModule.baseBindl;
    bindle = coreBindsModule.baseBindle;
  };

  shellHyprKeybinds = if isCaelestiaShell then shellBindsModule.caelestia else { extraConfig = ""; };

  mergedBindList = key: (baseHyprKeybinds.${key} or [ ]) ++ (shellHyprKeybinds.${key} or [ ]);
in
{
  inherit effectiveBindLists structuredBindLists structuredBinds caelestiaSubmapConfig;
}
```

**Design**: `effectiveBindLists` is a flat `bind → [string]` map used for rendering. `structuredBindLists` is `bind → [attrset]` used for introspection/documentation.

### 2. Core Submodule (`keybinds/core.nix`)

Returns **raw Hyprland strings**, not attrsets. The orchestrator parses them later via `lib.parseBindString`.

```nix
{
  coreBinds = [
    "$mainMod, q, killactive,"
    "$mainMod, t, togglefloating,"
    "$mainMod, return, exec, ${appExec preferredTerminalCmd}"
    # ... conditional binds (keepass, minimizer, diagnostics)
  ];

  baseBind = mainFocusBinds ++ mainMoveBinds ++ workspaceSwitchBinds ++ [
    "$mainMod CTRL, Tab, workspace, previous_per_monitor"
  ];

  baseBinde = mainResizeBinds ++ [
    "$mainMod, minus, splitratio, 0.1"
  ];

  baseBindm = [
    "$mainMod, mouse:272, movewindow"
    "$mainMod, mouse:273, resizewindow"
  ];

  baseBindl = [
    ", XF86AudioMute, exec, wpctl set-mute @DEFAULT_AUDIO_SINK@ toggle"
  ];

  baseBindle = [
    ", XF86AudioRaiseVolume, exec, wpctl set-mute @DEFAULT_AUDIO_SINK@ 0; ..."
  ];
}
```

### 3. Shell Submodule (`keybinds/shells.nix`)

Returns per-type bind lists for each shell variant. Only Caelestia is currently populated.

```nix
{ launcherAppExec, settings, preferredFileManager }:
{
  caelestia = {
    extraConfig = "";
    bindi = [ ];
    bind = [
      "$mainMod, escape, global, caelestia:session"
      "$mainMod, space, global, caelestia:showall"
      # ...
    ];
    bindl = [ ", Print, exec, caelestia screenshot" ];
    bindle = [ "$mainMod, Page_Up, workspace, -1" ];
    bindr = [ "CTRL SUPER SHIFT, R, exec, qs -c caelestia kill" ];
    bindm = [ "Super, mouse:272, movewindow" ];
  };
}
```

### 4. Data Model Library (`keybinds/lib.nix`)

Full two-way transforming library:

```nix
{
  # Rendering: attrset → Hyprland bind string
  mkBindString = { mods ? "", key, dispatcher, arg ? null }:
    if mods != "" then "${mods}, ${key}, ${dispatcher}${if arg != null then ", ${arg}" else ""}"
    else "${key}, ${dispatcher}${if arg != null then ", ${arg}" else ""}";

  # Convenience: auto-prefixes "$mainMod"
  mkMain = { extraMods ? "", key, dispatcher, arg ? null, description ? null }:
    { mods = if extraMods != "" then "$mainMod ${extraMods}" else "$mainMod"; inherit key dispatcher arg description; };

  # Parsing: string → attrset (inverse of rendering)
  parseBindString = s:
    let parts = map trim (lib.splitString "," s); ...
    in { mods = ...; key = ...; dispatcher = ...; arg = ...; };

  # Documentation helpers
  tagBindType = type: binds: map (b: b // { _type = type; _flags = ... }) binds;
  categorizeBinds = binds:
    let catOf = b: ... # heuristic by dispatcher + arg + key ...
    in listToAttrs (map (cat: { name = cat; value = filter ...; }) allCats);
}
```

**Key exports**: `directionalKeys` (h/j/k/l with resize deltas), `renderBindList`, `bindTypeFlags`.

---

## Documentation Generation

Post-refactor, `scripts/generate-keybind-docs.sh` produces `docs/KEYBINDS.md` from the Nix data.

**Critical implementation note**: A separate `.nix` file for the eval avoids fragile bash escaping:

```bash
# scripts/generate-keybind-docs.sh
nix eval --json --impure --expr 'import ./scripts/generate-keybind-data.nix' > /tmp/keybinds.json
```

Note: `--file` does NOT work for this use case because `builtins.dirOf (builtins.toPath ./.)` inside a `--file` invocation resolves to the `scripts/` directory, not the repo root. This breaks all relative imports of `user/wm/hyprland/...`. Use `--expr 'import ./scripts/...'` instead, which preserves the CWD as the repo root.

**Pitfall**: Inline `--expr` with multiline Nix strings inside bash double-quotes breaks on `$` and `"` escaping. The separate `.nix` approach also enables `builtins.currentSystem` instead of hardcoded `x86_64-linux`.

**generate-keybind-data.nix mock dependencies**:
The eval runs without the full flake context, so all function arguments (e.g. `appExec`, `homeBinDir`, `workspaceSwitchBinds`) must be mocked to values that satisfy the module's type requirements. Workspace binds in particular need a minimal `lib.range` generator to avoid `null` in the bind strings:

```nix
wsRange = lib.range 1 10;
workspaceSwitchBinds = lib.concatMap (i:
  let key = if i == 10 then "0" else toString i;
  in [ "\$mainMod, ${key}, workspace, ${toString i}" ]
) wsRange;
```

## Post-Refactor Fixes (evolutionary fixes after the initial refactor)

1. **Parser simplification (Aug 2026)**: `parseBindString` originally used space-heuristics to guess which comma-delimited field contained "mods key" vs just "key". This broke uniformly because Hyprland syntax is strictly `mods, key, dispatcher, args...` with mods as its own field. The fix: simple positional split (field 0 = mods, 1 = key, 2 = dispatcher, 3+ = args). Heuristics are seductive but wrong when the schema is deterministic.

2. **Bash stdout trapping (Aug 2026)**: The doc generation script used `cat > file <<'HEADER'` for the header but the `for` loop and `jq` output went to unredirected stdout. This produced an empty file (just the header) while dumping tables to the terminal. The fix: wrap the entire generation in a subshell block `{ ... } > "$OUTFILE"`.

## When to Apply This Pattern

- Monolithic Nix file > 300 lines with clearly distinct concerns
- Consumer (e.g. Hyprland) expects flat lists, but human maintainers need named, categorized binds
- Multiple "modes" or "flavors" (shell layers, profile variants) that each need their own bind overrides
- Need to generate documentation from the bind set (see `scripts/generate-keybind-docs.sh`)
- Data model and rendering are mixed inline (split `lib.nix` for testability + doc generation)
