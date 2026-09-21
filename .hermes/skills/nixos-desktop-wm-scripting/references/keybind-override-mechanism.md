# Keybind Override Mechanism — Architecture Detail

Session 2026-07-07: Implemented shell-override filtering to eliminate
duplicate/colliding binds between Core and Caelestia shell.

## File Layout

```
nix/user/wm/hyprland/config/
  keybinds.nix          Orchestrator: merges Core + Shell, parses for Lua
  keybinds/
    core.nix            Core binds (navigation, window, media, layout)
    shells.nix          Shell-specific binds + overrides declarations
    lib.nix             Pure helpers (parse, render, categorize)
  keybind-diagnostics.nix  Probe/dump scripts for debugging
```

## $mainMod

Defined in `fragments.nix` → `00-vars.conf`:
```
$mainMod = SUPER
```
Lua counterpart in `lua-fragments.nix` → `vars.lua`:
```lua
mainMod = "SUPER"
```
No override path. All shells depend on this being SUPER.

## Bind Types

| Type    | Flags                    | Meaning                        |
|---------|--------------------------|--------------------------------|
| bind    | (none)                   | Standard                       |
| bindi   | ignore_mods              | Ignores mod-grab               |
| bindin  | ignore_mods, non_consuming | Non-consuming + ignore       |
| binde   | repeating                | Repeats while held             |
| bindl   | locked                   | Active in lockscreen           |
| bindle  | locked, repeating        | Locked + repeat                |
| bindr   | release                  | Fires on key release           |
| bindm   | mouse                    | Mouse bind                     |

## Merge Flow

1. `core.nix` exports: `coreBinds`, `baseBind`, `baseBinde`, `baseBindm`,
   `baseBindl`, `baseBindle`.
2. `shells.nix` exports per-shell attrsets with optional `overrides` list.
3. `keybinds.nix`:
   - `shellOverrides = shellHyprKeybinds.overrides or []`
   - `isOverridden type entry` — checks if (type, mods, key) matches any override
   - `mergedBindList key` = filter Core (remove overridden) ++ Shell binds
4. `effectiveBindLists`:
   - `bind` = coreBinds ++ workspaceSwitchBinds ++ workspaceMoveBinds ++ mergedBindList "bind"
   - Other types = mergedBindList for that type

## Dual Render Paths

### Hyprlang (fragments.nix → 80-keybinds.conf)
- Only active for non-Caelestia shells.
- For Caelestia: bindLines empty, all binds go into `caelestiaSubmapConfig` in 95-shell.conf.
- Caelestia wraps everything in a `submap = global` block with launcher-interrupt binds.

### Lua (lua-fragments.nix → j0nix/keybinds.lua + j0nix/shell.lua)
- `structuredBinds` = all binds parsed into `{mods, key, dispatcher, argument, flags, raw}`.
- `structuredLuaGlobalBinds` = empty for Caelestia, all binds for other shells.
- `structuredLuaShellBinds` = all binds for Caelestia, empty for others.
- Caelestia shell.lua:
  - `hl.bind("SUPER + SUPER_L", ...)` with release flag opens launcher.
  - `hl.define_submap("global", ...)` wraps all shell binds.
  - Every mainMod bind gets a parallel `caelestia:launcherInterrupt` bind.

## Override Entries (Caelestia)

```
bindl  ""  XF86AudioPlay
bindl  ""  XF86AudioPause
bindl  ""  XF86AudioNext
bindl  ""  XF86AudioPrev
bindl  ""  XF86AudioStop
bindl  ""  XF86MonBrightnessUp
bindl  ""  XF86MonBrightnessDown
bindl  ""  Print
bindl  ""  XF86AudioMicMute
bindl  ""  XF86AudioMute
bindle ""  XF86AudioRaiseVolume
bindle ""  XF86AudioLowerVolume
```

## Remaining Known Issues (not yet fixed)

1. **Exact duplicates in shell binde**: Page_Up/Down, minus/equal/plus, changegroupactive — all duplicated between Core `baseBinde` and Shell `binde`.
2. **Type conflict**: `changegroupactive` exists as both `bind` (Core coreBinds) and `binde` (Shell binde). Both fire.
3. **Shell bindm duplicates**: mouse:272/273 in both Core `baseBindm` and Shell `bindm` (Shell writes "Super" instead of "$mainMod" but they're identical).

These could be resolved by extending the overrides mechanism to cover `binde` and `bindm` types, or by removing the redundant shell entries.

## Configurable Bind Variables

| Setting | Default | Purpose |
|---------|---------|---------|
| `hyprland.layoutToggleBind` | `$mainMod SHIFT, SPACE` | Keyboard layout toggle |
| `hyprland.overviewToggleBind` | `$mainMod, TAB` | DMS overview toggle |
| `programs.keepassxc.workspace.toggleBind` | `$mainMod SHIFT, P` | KeePassXC workspace toggle |
| `hyprland.minimizer.*` | (from minimizer.nix) | Minimizer toggle/restore/menu |
| `dms.workspaces.count` | 10 | Workspace count (1-10) |
| `hyprland.toggleableOutputs.*` | per-output `bindKey` | Monitor toggle binds |
| `hyprland.outputBindings.*` | per-output `bindIndex` | Workspace-to-monitor binds |
