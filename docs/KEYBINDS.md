# Keybind Reference

Auto-generated from `user/wm/hyprland/config/keybinds/`.

> [!NOTE]
> `$mainMod` = `SUPER` (Windows key). Some binds may vary by selected shell.


## Navigation

| Mods | Key | Dispatcher | Argument | Type |
|------|-----|------------|----------|------|
| `SUPER` | 0 | workspace | 10 | bind |
| `SUPER` | 1 | workspace | 1 | bind |
| `SUPER` | 2 | workspace | 2 | bind |
| `SUPER` | 3 | workspace | 3 | bind |
| `SUPER` | 4 | workspace | 4 | bind |
| `SUPER` | 5 | workspace | 5 | bind |
| `SUPER` | 6 | workspace | 6 | bind |
| `SUPER` | 7 | workspace | 7 | bind |
| `SUPER` | 8 | workspace | 8 | bind |
| `SUPER` | 9 | workspace | 9 | bind |
| `SUPER` CTRL | G | workspace | previous_per_monitor | bind |
| `SUPER` | Page_Down | workspace | +1 | binde |
| `SUPER` | Page_Down | workspace | +1 | binde |
| `SUPER` | Page_Up | workspace | -1 | binde |
| `SUPER` | Page_Up | workspace | -1 | binde |
| `SUPER` CTRL | Tab | workspace | previous_per_monitor | bind |
| `SUPER` | left | workspace | -1 | bind |
| `SUPER` | mouse_down | workspace | -1 | bind |
| `SUPER` | mouse_up | workspace | +1 | bind |
| `SUPER` | right | workspace | +1 | bind |

## Resizing

| Mods | Key | Dispatcher | Argument | Type |
|------|-----|------------|----------|------|
| `SUPER` ALT | h | resizeactive | -60 0 | binde |
| `SUPER` ALT | j | resizeactive | 0 60 | binde |
| `SUPER` ALT | k | resizeactive | 0 -60 | binde |
| `SUPER` ALT | l | resizeactive | 60 0 | binde |
| `SUPER` | equal | splitratio | -0.1 | binde |
| `SUPER` | equal | splitratio | -0.1 | binde |
| `SUPER` | minus | splitratio | 0.1 | binde |
| `SUPER` | minus | splitratio | 0.1 | binde |
| `SUPER` | plus | splitratio | -0.1 | binde |
| `SUPER` | plus | splitratio | -0.1 | binde |

## Layout

| Mods | Key | Dispatcher | Argument | Type |
|------|-----|------------|----------|------|
| `SUPER` CTRL | h | layoutmsg | preselect l | bind |
| `SUPER` CTRL | j | layoutmsg | preselect d | bind |
| `SUPER` CTRL | k | layoutmsg | preselect u | bind |
| `SUPER` CTRL | l | layoutmsg | preselect r | bind |
| `SUPER` CTRL | v | layoutmsg | preselect r | bind |
| `SUPER` CTRL SHIFT | v | layoutmsg | preselect d | bind |

## Session

| Mods | Key | Dispatcher | Argument | Type |
|------|-----|------------|----------|------|
| `SUPER` SHIFT | l | exec | wm-lock-screen | bind |
| `SUPER` SHIFT | q | exit |  | bind |

## Screenshot

| Mods | Key | Dispatcher | Argument | Type |
|------|-----|------------|----------|------|
|  | Print | exec | wm-screenshot-area | bindl |
|  | Print | exec | caelestia screenshot | bindl |
| SHIFT | Print | exec | caelestia screenshot | bindl |
| CTRL | Print | exec | caelestia screenshot | bindl |
| `SUPER` | p | exec | caelestia screenshot | bind |

## Media

| Mods | Key | Dispatcher | Argument | Type |
|------|-----|------------|----------|------|
|  | AudioLowerVolume | exec | wpctl set-mute @DEFAULT_AUDIO_SINK@ 0; wpctl set-volume @DEFAULT_AUDIO_SINK@ 3%- | bindle |
|  | AudioLowerVolume | exec | wpctl set-mute @DEFAULT_AUDIO_SINK@ 0; wpctl set-volume @DEFAULT_AUDIO_SINK@ 3%- | bindle |
|  | AudioMicMute | exec | wpctl set-mute @DEFAULT_AUDIO_SOURCE@ toggle | bindl |
|  | AudioMicMute | exec | wpctl set-mute @DEFAULT_AUDIO_SOURCE@ toggle | bindl |
|  | AudioMute | exec | wpctl set-mute @DEFAULT_AUDIO_SINK@ toggle | bindl |
|  | AudioMute | exec | wpctl set-mute @DEFAULT_AUDIO_SINK@ toggle | bindl |
|  | AudioNext | exec | playerctl next | bindl |
|  | AudioPause | exec | playerctl play-pause | bindl |
|  | AudioPlay | exec | playerctl play-pause | bindl |
|  | AudioPrev | exec | playerctl previous | bindl |
|  | AudioRaiseVolume | exec | wpctl set-mute @DEFAULT_AUDIO_SINK@ 0; wpctl set-volume -l 1 @DEFAULT_AUDIO_SINK@ 3%+ | bindle |
|  | AudioRaiseVolume | exec | wpctl set-mute @DEFAULT_AUDIO_SINK@ 0; wpctl set-volume -l 1 @DEFAULT_AUDIO_SINK@ 3%+ | bindle |
|  | AudioStop | exec | playerctl stop | bindl |
|  | MonBrightnessDown | exec | brightnessctl set 10%- | bindl |
|  | MonBrightnessUp | exec | brightnessctl set +10% | bindl |
| `SUPER` SHIFT | m | exec | wpctl set-mute @DEFAULT_AUDIO_SINK@ toggle | bindl |

## Launcher

| Mods | Key | Dispatcher | Argument | Type |
|------|-----|------------|----------|------|
| `SUPER` | period | exec | pkill fuzzel || caelestia emoji -p | bind |
| `SUPER` SHIFT | v | exec | pkill fuzzel || caelestia clipboard | bind |
| `SUPER` ALT | v | exec | pkill fuzzel || caelestia clipboard -d | bind |

## Shell

| Mods | Key | Dispatcher | Argument | Type |
|------|-----|------------|----------|------|
| `SUPER` SHIFT | BackSpace | global | caelestia:lock | bindl |
| CTRL SUPER | Equal | global | caelestia:mediaNext | bindl |
| CTRL SUPER | Minus | global | caelestia:mediaPrev | bindl |
| CTRL SUPER | Space | global | caelestia:mediaToggle | bindl |
|  | AudioNext | global | caelestia:mediaNext | bindl |
|  | AudioPause | global | caelestia:mediaToggle | bindl |
|  | AudioPlay | global | caelestia:mediaToggle | bindl |
|  | AudioPrev | global | caelestia:mediaPrev | bindl |
|  | AudioStop | global | caelestia:mediaStop | bindl |
|  | MonBrightnessDown | global | caelestia:brightnessDown | bindl |
|  | MonBrightnessUp | global | caelestia:brightnessUp | bindl |
| `SUPER` | escape | global | caelestia:session | bind |
| `SUPER` | n | global | caelestia:clearNotifs | bind |
| `SUPER` SHIFT | n | global | caelestia:clearNotifs | bind |
| `SUPER` SHIFT | s | global | caelestia:screenshotFreeze | bind |
| `SUPER` SHIFT ALT | s | global | caelestia:screenshot | bind |
| `SUPER` | space | global | caelestia:showall | bind |

## Other

| Mods | Key | Dispatcher | Argument | Type |
|------|-----|------------|----------|------|
| `SUPER` CTRL | Backslash | centerwindow | 1 | bind |
| CTRL ALT | Tab | changegroupactive | f | bind |
| CTRL SHIFT ALT | Tab | changegroupactive | b | bind |
| CTRL ALT | Tab | changegroupactive | f | binde |
| CTRL SHIFT ALT | Tab | changegroupactive | b | binde |
| `SUPER` SHIFT | semicolon | moveoutofgroup |  | bind |
| `SUPER` ALT | 0 | movetoworkspace | 10 | bind |
| `SUPER` ALT | 1 | movetoworkspace | 1 | bind |
| `SUPER` ALT | 2 | movetoworkspace | 2 | bind |
| `SUPER` ALT | 3 | movetoworkspace | 3 | bind |
| `SUPER` ALT | 4 | movetoworkspace | 4 | bind |
| `SUPER` ALT | 5 | movetoworkspace | 5 | bind |
| `SUPER` ALT | 6 | movetoworkspace | 6 | bind |
| `SUPER` ALT | 7 | movetoworkspace | 7 | bind |
| `SUPER` ALT | 8 | movetoworkspace | 8 | bind |
| `SUPER` ALT | 9 | movetoworkspace | 9 | bind |
| `SUPER` ALT | Page_Down | movetoworkspace | +1 | binde |
| `SUPER` ALT | Page_Up | movetoworkspace | -1 | binde |
| `SUPER` CTRL SHIFT | down | movetoworkspace | e+0 | bind |
| `SUPER` ALT | h | movetoworkspace | l | bind |
| `SUPER` ALT | j | movetoworkspace | d | bind |
| `SUPER` ALT | k | movetoworkspace | u | bind |
| `SUPER` ALT | l | movetoworkspace | r | bind |
| `SUPER` ALT | left | movetoworkspace | -1 | bind |
| `SUPER` CTRL SHIFT | left | movetoworkspace | -1 | bind |
| `SUPER` ALT | mouse_down | movetoworkspace | -1 | bind |
| `SUPER` ALT | mouse_down | movetoworkspace | -1 | bind |
| `SUPER` ALT | mouse_up | movetoworkspace | +1 | bind |
| `SUPER` ALT | mouse_up | movetoworkspace | +1 | bind |
| `SUPER` ALT | right | movetoworkspace | +1 | bind |
| `SUPER` CTRL SHIFT | right | movetoworkspace | +1 | bind |
| `SUPER` ALT | s | movetoworkspace | special:special | bind |
| `SUPER` CTRL SHIFT | up | movetoworkspace | special:special | bind |
| `SUPER` SHIFT | p | pin |  | bind |
| `SUPER` | mouse:273 | resizewindow |  | bindm |
| Super | mouse:273 | resizewindow |  | bindm |
| `SUPER` | semicolon | togglegroup |  | bind |

---

Generated at 2026-05-22T11:07:28+02:00
