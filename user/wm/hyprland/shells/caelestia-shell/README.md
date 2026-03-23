# Caelestia Shell

This module enables the `caelestia-shell` flake input and seeds `~/.config/caelestia/shell.json`.
It also patches the bundled `caelestia` CLI package to install the full upstream `schemes/*` data set, because the current upstream Nix package ships templates but omits the actual colour scheme files.

Repo-managed seeding currently only ensures these keys exist (without overwriting user values):
- `general.apps.terminal`
- `services.smartScheme`
- `paths.wallpaperDir` (when a wallpaper path is configured)

## Theme Ownership

Caelestia can manage more than its own shell colours. The upstream CLI also has theme writers for GTK and Qt.
That matters for this repo because desktop theming is already managed separately in:

- `user/desktop/theme.nix` for GTK
- `user/desktop/qt-theme.nix` for Qt/KDE

Operational rule:
- Caelestia should own shell theming.
- j0nix should own desktop toolkit theming.

If both layers write GTK/Qt state, the last writer wins and the session becomes nondeterministic.

## GTK Conflict Findings

Root cause of the recent GTK regressions:

- `settings.ini`, `gsettings`, and `GTK_THEME` were correct.
- The breakage came from `~/.config/gtk-3.0/gtk.css` and `~/.config/gtk-4.0/gtk.css` being rewritten after login.
- Those rewrites were not coming from Home Manager. They were coming from the upstream `caelestia` CLI theme application path.

Observed behavior:

- GTK3/GTK4 session settings still pointed at the intended Catppuccin theme.
- After login, `gtk.css` became a regular file again instead of staying repo-managed.
- The rewritten CSS pulled in old local overrides such as `thunar.css`, which changed spacing and colours.

Practical implication:

- `GTK_THEME` is not sufficient to explain or fix the issue on its own.
- The real ownership bug is a second writer touching GTK user config after login.
- Any "restore after login" workaround is a defensive patch, not the clean architectural fix.

## Upstream CLI Behavior

The upstream `caelestia` CLI theme code currently writes:

- `~/.config/gtk-3.0/gtk.css`
- `~/.config/gtk-3.0/thunar.css`
- `~/.config/gtk-4.0/gtk.css`
- `~/.config/gtk-4.0/thunar.css`

This is controlled by the shell config's theme block. Upstream defaults effectively treat GTK theming as enabled unless explicitly disabled.

Repo guidance:

- when j0nix manages GTK/Qt, Caelestia's GTK/Qt theme writers should be disabled explicitly in `shell.json`
- otherwise Caelestia will keep competing with repo-managed desktop theming

## j0nix Theme Wiring

Use `settings.programs.caelestia.theme` to pin a default CLI-managed scheme:

```nix
programs.caelestia.theme = {
  scheme = "catppuccin";
  flavour = "mocha";
  mode = "dark";
  variant = "tonalspot";
  smartScheme = false;
};
```

Notes:
- `scheme` falls back to the global `settings.theme` when unset.
- `flavour` is the scheme flavour (`mocha`, `latte`, `moon`, `main`, ...), not the Material variant.
- `variant` is the Material variant (`tonalspot`, `vibrant`, `expressive`, ...).
- The module applies these defaults through `caelestia scheme set` on shell startup, so `~/.local/state/caelestia/scheme.json` stays valid.
- Set `smartScheme = true;` to re-enable automatic wallpaper-driven theming. In that mode startup switches the active scheme back to `dynamic`.
- The launcher also gets `Auto Theme` and `Manual Theme` actions, backed by `caelestia-smart-theme enable|disable`.

## Quickshell Runtime

Use `settings.programs.caelestia.quickshellRuntime` to choose how `caelestia-shell` is launched:

```nix
programs.caelestia = {
  channel = "dev";
  quickshellRuntime = "upstream"; # "wrapped" | "upstream"
};
```

- `wrapped` (default): use the shell package's bundled quickshell wrapper.
- `upstream`: run Caelestia with the upstream quickshell input package (`qs`) from the selected Caelestia channel input.
- Channel wiring:
  - `stable` -> `quickshell-stable` (release input)
  - `dev` -> `quickshell-dev` (latest master)

## Referenz: `shell.json` Optionen

User-provided reference config (documented here as a source-of-truth example for supported/used Caelestia shell options):

```json
{
  "appearance": {
    "mediaGifSpeedAdjustment": 300,
    "sessionGifSpeed": 0.7,
    "anim": {
      "durations": {
        "scale": 1
      }
    },
    "font": {
      "family": {
        "clock": "Rubik",
        "material": "Material Symbols Rounded",
        "mono": "CaskaydiaCove NF",
        "sans": "Rubik"
      },
      "size": {
        "scale": 1
      }
    },
    "padding": {
      "scale": 1
    },
    "rounding": {
      "scale": 1
    },
    "spacing": {
      "scale": 1
    },
    "transparency": {
      "enabled": false,
      "base": 0.85,
      "layers": 0.4
    }
  },
  "general": {
    "logo": "caelestia",
    "apps": {
      "terminal": ["foot"],
      "audio": ["pavucontrol"],
      "playback": ["mpv"],
      "explorer": ["thunar"]
    },
    "battery": {
      "warnLevels": [
        {
          "level": 20,
          "title": "Low battery",
          "message": "You might want to plug in a charger",
          "icon": "battery_android_frame_2"
        },
        {
          "level": 10,
          "title": "Did you see the previous message?",
          "message": "You should probably plug in a charger <b>now</b>",
          "icon": "battery_android_frame_1"
        },
        {
          "level": 5,
          "title": "Critical battery level",
          "message": "PLUG THE CHARGER RIGHT NOW!!",
          "icon": "battery_android_alert",
          "critical": true
        }
      ],
      "criticalLevel": 3
    },
    "idle": {
      "lockBeforeSleep": true,
      "inhibitWhenAudio": true,
      "timeouts": [
        {
          "timeout": 180,
          "idleAction": "lock"
        },
        {
          "timeout": 300,
          "idleAction": "dpms off",
          "returnAction": "dpms on"
        },
        {
          "timeout": 600,
          "idleAction": ["system-power-action", "suspend-then-hibernate"]
        }
      ]
    }
  },
  "background": {
    "desktopClock": {
      "enabled": false,
      "scale": 1.0,
      "position": "bottom-right",
      "shadow": {
        "enabled": true,
        "opacity": 0.7,
        "blur": 0.4
      },
      "background": {
        "enabled": false,
        "opacity": 0.7,
        "blur": true
      },
      "invertColors": false
    },
    "enabled": true,
    "visualiser": {
      "blur": false,
      "enabled": false,
      "autoHide": true,
      "rounding": 1,
      "spacing": 1
    }
  },
  "bar": {
    "clock": {
      "showIcon": true
    },
    "dragThreshold": 20,
    "entries": [
      {
        "id": "logo",
        "enabled": true
      },
      {
        "id": "workspaces",
        "enabled": true
      },
      {
        "id": "spacer",
        "enabled": true
      },
      {
        "id": "activeWindow",
        "enabled": true
      },
      {
        "id": "spacer",
        "enabled": true
      },
      {
        "id": "tray",
        "enabled": true
      },
      {
        "id": "clock",
        "enabled": true
      },
      {
        "id": "statusIcons",
        "enabled": true
      },
      {
        "id": "power",
        "enabled": true
      }
    ],
    "persistent": true,
    "popouts": {
      "activeWindow": true,
      "statusIcons": true,
      "tray": true
    },
    "scrollActions": {
      "brightness": true,
      "workspaces": true,
      "volume": true
    },
    "showOnHover": true,
    "status": {
      "showAudio": false,
      "showBattery": true,
      "showBluetooth": true,
      "showKbLayout": false,
      "showMicrophone": false,
      "showNetwork": true,
      "showWifi": true,
      "showLockStatus": true
    },
    "tray": {
      "background": false,
      "compact": false,
      "iconSubs": [],
      "recolour": false
    },
    "workspaces": {
      "activeIndicator": true,
      "activeLabel": "󰮯",
      "activeTrail": false,
      "label": "  ",
      "occupiedBg": false,
      "occupiedLabel": "󰮯",
      "perMonitorWorkspaces": true,
      "showWindows": true,
      "shown": 5,
      "specialWorkspaceIcons": [
        {
          "name": "steam",
          "icon": "sports_esports"
        }
      ]
    },
    "excludedScreens": [""],
    "activeWindow": {
      "inverted": false
    }
  },
  "border": {
    "rounding": 25,
    "thickness": 10
  },
  "dashboard": {
    "enabled": true,
    "dragThreshold": 50,
    "mediaUpdateInterval": 500,
    "showOnHover": true
  },
  "launcher": {
    "actionPrefix": ">",
    "actions": [
      {
        "name": "Calculator",
        "icon": "calculate",
        "description": "Do simple math equations (powered by Qalc)",
        "command": ["autocomplete", "calc"],
        "enabled": true,
        "dangerous": false
      },
      {
        "name": "Scheme",
        "icon": "palette",
        "description": "Change the current colour scheme",
        "command": ["autocomplete", "scheme"],
        "enabled": true,
        "dangerous": false
      },
      {
        "name": "Wallpaper",
        "icon": "image",
        "description": "Change the current wallpaper",
        "command": ["autocomplete", "wallpaper"],
        "enabled": true,
        "dangerous": false
      },
      {
        "name": "Variant",
        "icon": "colors",
        "description": "Change the current scheme variant",
        "command": ["autocomplete", "variant"],
        "enabled": true,
        "dangerous": false
      },
      {
        "name": "Transparency",
        "icon": "opacity",
        "description": "Change shell transparency",
        "command": ["autocomplete", "transparency"],
        "enabled": false,
        "dangerous": false
      },
      {
        "name": "Random",
        "icon": "casino",
        "description": "Switch to a random wallpaper",
        "command": ["caelestia", "wallpaper", "-r"],
        "enabled": true,
        "dangerous": false
      },
      {
        "name": "Light",
        "icon": "light_mode",
        "description": "Change the scheme to light mode",
        "command": ["setMode", "light"],
        "enabled": true,
        "dangerous": false
      },
      {
        "name": "Dark",
        "icon": "dark_mode",
        "description": "Change the scheme to dark mode",
        "command": ["setMode", "dark"],
        "enabled": true,
        "dangerous": false
      },
      {
        "name": "Shutdown",
        "icon": "power_settings_new",
        "description": "Shutdown the system",
        "command": ["system-power-action", "poweroff"],
        "enabled": true,
        "dangerous": true
      },
      {
        "name": "Reboot",
        "icon": "cached",
        "description": "Reboot the system",
        "command": ["system-power-action", "reboot"],
        "enabled": true,
        "dangerous": true
      },
      {
        "name": "Logout",
        "icon": "exit_to_app",
        "description": "Log out of the current session",
        "command": ["loginctl", "terminate-user", ""],
        "enabled": true,
        "dangerous": true
      },
      {
        "name": "Lock",
        "icon": "lock",
        "description": "Lock the current session",
        "command": ["loginctl", "lock-session"],
        "enabled": true,
        "dangerous": false
      },
      {
        "name": "Sleep",
        "icon": "bedtime",
        "description": "Suspend the system",
        "command": ["system-power-action", "suspend"],
        "enabled": true,
        "dangerous": false
      },
      {
        "name": "Hibernate",
        "icon": "downloading",
        "description": "Hibernate the system",
        "command": ["system-power-action", "hibernate"],
        "enabled": true,
        "dangerous": false
      },
      {
        "name": "Settings",
        "icon": "settings",
        "description": "Configure the shell",
        "command": ["caelestia", "shell", "controlCenter", "open"],
        "enabled": true,
        "dangerous": false
      }
    ],
    "dragThreshold": 50,
    "vimKeybinds": false,
    "enableDangerousActions": false,
    "maxShown": 7,
    "maxWallpapers": 9,
    "specialPrefix": "@",
    "useFuzzy": {
      "apps": false,
      "actions": false,
      "schemes": false,
      "variants": false,
      "wallpapers": false
    },
    "showOnHover": false,
    "favouriteApps": [],
    "hiddenApps": []
  },
  "lock": {
    "recolourLogo": false
  },
  "notifs": {
    "actionOnClick": false,
    "clearThreshold": 0.3,
    "defaultExpireTimeout": 5000,
    "expandThreshold": 20,
    "openExpanded": false,
    "expire": false
  },
  "osd": {
    "enabled": true,
    "enableBrightness": true,
    "enableMicrophone": false,
    "hideDelay": 2000
  },
  "paths": {
    "mediaGif": "root:/assets/bongocat.gif",
    "sessionGif": "root:/assets/kurukuru.gif",
    "wallpaperDir": "~/Pictures/Wallpapers"
  },
  "services": {
    "audioIncrement": 0.1,
    "brightnessIncrement": 0.1,
    "maxVolume": 1.0,
    "defaultPlayer": "Spotify",
    "gpuType": "",
    "playerAliases": [
      {
        "from": "com.github.th_ch.youtube_music",
        "to": "YT Music"
      }
    ],
    "weatherLocation": "",
    "useFahrenheit": false,
    "useFahrenheitPerformance": false,
    "useTwelveHourClock": false,
    "smartScheme": true,
    "visualiserBars": 45
  },
  "session": {
    "dragThreshold": 30,
    "enabled": true,
    "vimKeybinds": false,
    "icons": {
      "logout": "logout",
      "shutdown": "power_settings_new",
      "hibernate": "downloading",
      "reboot": "cached"
    },
    "commands": {
      "logout": ["loginctl", "terminate-user", ""],
      "shutdown": ["system-power-action", "poweroff"],
      "hibernate": ["system-power-action", "hibernate"],
      "reboot": ["system-power-action", "reboot"]
    }
  },
  "sidebar": {
    "dragThreshold": 80,
    "enabled": true
  },
  "utilities": {
    "enabled": true,
    "maxToasts": 4,
    "toasts": {
      "audioInputChanged": true,
      "audioOutputChanged": true,
      "capsLockChanged": true,
      "chargingChanged": true,
      "configLoaded": true,
      "dndChanged": true,
      "gameModeChanged": true,
      "kbLayoutChanged": true,
      "kbLimit": true,
      "numLockChanged": true,
      "vpnChanged": true,
      "nowPlaying": false
    },
    "vpn": {
      "enabled": true,
      "provider": [
        {
          "name": "wireguard",
          "interface": "your-connection-name",
          "displayName": "Wireguard (Your VPN)",
          "enabled": false
        }
      ]
    }
  }
}
```
