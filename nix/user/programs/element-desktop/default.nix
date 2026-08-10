{
  lib,
  pkgs,
  settings,
  ...
}:
let
  cfg = (settings.programs or { }).elementDesktop or { };
  enabled = cfg.enable or false;

  hasValue = value: value != null && value != "";

  homeserverCfg = cfg.homeserver or { };
  identityServerCfg = cfg.identityServer or { };
  autoLoginCfg = cfg.autoLogin or { };

  homeserverBaseUrl = homeserverCfg.baseUrl or null;
  homeserverName = homeserverCfg.serverName or null;
  identityServerBaseUrl = identityServerCfg.baseUrl or null;
  ssoRedirect = autoLoginCfg.ssoRedirect or false;
  selectorCfg = cfg.selector or { };

  baseConfig = {
    brand = cfg.brand or "Element";
    disable_custom_urls = cfg.disableCustomUrls or false;
  }
  // lib.optionalAttrs (hasValue homeserverName) {
    default_server_name = homeserverName;
  }
  //
    lib.optionalAttrs
      (hasValue homeserverBaseUrl || hasValue homeserverName || hasValue identityServerBaseUrl)
      {
        default_server_config =
          lib.optionalAttrs (hasValue homeserverBaseUrl || hasValue homeserverName) {
            "m.homeserver" =
              (lib.optionalAttrs (hasValue homeserverBaseUrl) {
                base_url = homeserverBaseUrl;
              })
              // (lib.optionalAttrs (hasValue homeserverName) {
                server_name = homeserverName;
              });
          }
          // lib.optionalAttrs (hasValue identityServerBaseUrl) {
            "m.identity_server" = {
              base_url = identityServerBaseUrl;
            };
          };
      }
  // lib.optionalAttrs ssoRedirect {
    sso_redirect_options = {
      immediate = true;
    };
  };

  configFile = (pkgs.formats.json { }).generate "element-config.json" (
    lib.recursiveUpdate baseConfig (cfg.extraConfig or { })
  );
  defaultProfiles = [
    {
      id = "default";
      name = "Default";
      profile = null;
      default = true;
    }
  ];
  profiles = lib.imap0 (
    index: profile:
    let
      id = toString (profile.id or profile.name or "profile-${toString index}");
    in
    {
      inherit id;
      name = toString (profile.name or id);
      profile = profile.profile or id;
      default = profile.default or (index == 0);
      config = profile.config or { };
    }
  ) (cfg.profiles or defaultProfiles);
  profileCount = builtins.length profiles;
  selectorEnable = selectorCfg.enable or (profileCount > 1);
  profileIds = map (profile: profile.id) profiles;
  profileNames = map (profile: profile.name) profiles;
  profileConfigPaths = map configPathForProfile profiles;
  defaultProfile =
    if profiles == [ ] then
      builtins.head defaultProfiles
    else
      let
        defaults = builtins.filter (profile: profile.default) profiles;
      in
      if defaults == [ ] then builtins.head profiles else builtins.head defaults;
  configForProfile =
    profile:
    if profile.config == { } then
      configFile
    else
      (pkgs.formats.json { }).generate "element-config-${profile.id}.json" (
        lib.recursiveUpdate baseConfig (lib.recursiveUpdate (cfg.extraConfig or { }) profile.config)
      );
  configPathForProfile =
    profile:
    if profile.profile == null then "Element/config.json" else "Element-${profile.profile}/config.json";
  profileConfigFiles = builtins.listToAttrs (
    map (profile: {
      name = configPathForProfile profile;
      value.source = configForProfile profile;
    }) profiles
  );
  profileMenuEntries = lib.concatMapStringsSep "\n" (profile: profile.name) profiles;
  profileLaunchCases = lib.concatMapStringsSep "\n" (
    profile:
    let
      profileFlag = lib.optionalString (
        profile.profile != null
      ) "--profile ${lib.escapeShellArg profile.profile} ";
      profileConfigFile = configForProfile profile;
    in
    ''
      ${lib.escapeShellArg profile.id})
        exec ${lib.getExe pkgs.element-desktop} \
          --password-store=gnome-libsecret \
          ${profileFlag}--config ${lib.escapeShellArg profileConfigFile} \
          "$@"
        ;;
    ''
  ) profiles;
  profileSelectionCases = lib.concatMapStringsSep "\n" (profile: ''
    ${lib.escapeShellArg profile.name})
      launch_profile ${lib.escapeShellArg profile.id} "$@"
      ;;
  '') profiles;
  launcherScript = pkgs.writeShellScriptBin "element-desktop" ''
    set -euo pipefail

    launch_profile() {
      local profile_id="''${1:-}"
      shift || true

      case "$profile_id" in
    ${profileLaunchCases}
        *)
          printf 'Unknown Element profile: %s\n' "$profile_id" >&2
          exit 64
          ;;
      esac
    }

    choose_profile() {
      local entries selected
      entries=${lib.escapeShellArg profileMenuEntries}

      if [ "${
        if selectorEnable then "1" else "0"
      }" != "1" ] || [ "${toString profileCount}" -le 1 ]; then
        launch_profile ${lib.escapeShellArg defaultProfile.id} "$@"
      fi

      if command -v fuzzel >/dev/null 2>&1; then
        selected="$(printf '%s\n' "$entries" | fuzzel --dmenu --prompt 'Element > ' --placeholder 'Choose instance' --lines ${toString profileCount})" || exit 0
      elif command -v wofi >/dev/null 2>&1; then
        selected="$(printf '%s\n' "$entries" | wofi --dmenu --prompt 'Element instance')" || exit 0
      elif command -v rofi >/dev/null 2>&1; then
        selected="$(printf '%s\n' "$entries" | rofi -dmenu -p 'Element')" || exit 0
      elif command -v bemenu >/dev/null 2>&1; then
        selected="$(printf '%s\n' "$entries" | bemenu -p 'Element')" || exit 0
      else
        PS3='Element instance: '
        select selected in ${
          lib.concatMapStringsSep " " (profile: lib.escapeShellArg profile.name) profiles
        }; do
          [ -n "''${selected:-}" ] && break
        done
      fi

      case "$selected" in
    ${profileSelectionCases}
        "")
          exit 0
          ;;
        *)
          printf 'Unknown Element selection: %s\n' "$selected" >&2
          exit 64
          ;;
      esac
    }

    case "''${1:-}" in
      --j0nix-profile)
        shift
        launch_profile "''${1:-}" "''${@:2}"
        ;;
      --j0nix-menu)
        shift
        choose_profile "$@"
        ;;
      "")
        choose_profile
        ;;
      *)
        exec ${lib.getExe pkgs.element-desktop} --password-store=gnome-libsecret "$@"
        ;;
    esac
  '';
  elementDesktopPkg = pkgs.symlinkJoin {
    name = "${pkgs.element-desktop.pname}-j0nix-${pkgs.element-desktop.version}";
    paths = [ pkgs.element-desktop ];
    postBuild = ''
      rm -f "$out/bin/element-desktop"
      ln -s ${lib.getExe launcherScript} "$out/bin/element-desktop"
    '';
  };
in
lib.mkIf enabled {
  j0nix.user.software.packages = [ elementDesktopPkg ];

  xdg.configFile = profileConfigFiles;

  assertions = [
    {
      assertion = !(hasValue homeserverBaseUrl) || hasValue homeserverName;
      message = "settings.userSettings.<name>.programs.elementDesktop.homeserver.baseUrl requires homeserver.serverName for Element Desktop.";
    }
    {
      assertion = !ssoRedirect || hasValue homeserverBaseUrl;
      message = "settings.userSettings.<name>.programs.elementDesktop.autoLogin.ssoRedirect requires homeserver.baseUrl for Element Desktop.";
    }
    {
      assertion = profiles != [ ];
      message = "settings.userSettings.<name>.programs.elementDesktop.profiles must contain at least one Element profile.";
    }
    {
      assertion = (lib.unique profileIds) == profileIds;
      message = "settings.userSettings.<name>.programs.elementDesktop.profiles ids must be unique.";
    }
    {
      assertion = (lib.unique profileNames) == profileNames;
      message = "settings.userSettings.<name>.programs.elementDesktop.profiles names must be unique.";
    }
    {
      assertion = (lib.unique profileConfigPaths) == profileConfigPaths;
      message = "settings.userSettings.<name>.programs.elementDesktop.profiles profile values must map to unique Element config directories.";
    }
  ];
}
