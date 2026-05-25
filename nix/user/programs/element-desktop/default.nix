{ lib, pkgs, settings, ... }:
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

  baseConfig =
    {
      brand = cfg.brand or "Element";
      disable_custom_urls = cfg.disableCustomUrls or false;
    }
    // lib.optionalAttrs (hasValue homeserverName) {
      default_server_name = homeserverName;
    }
    // lib.optionalAttrs (hasValue homeserverBaseUrl || hasValue homeserverName || hasValue identityServerBaseUrl) {
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

  configFile = (pkgs.formats.json { }).generate "element-config.json" (lib.recursiveUpdate baseConfig (cfg.extraConfig or { }));
  elementDesktopPkg = pkgs.symlinkJoin {
    name = "${pkgs.element-desktop.pname}-j0nix-${pkgs.element-desktop.version}";
    paths = [ pkgs.element-desktop ];
    nativeBuildInputs = [ pkgs.makeWrapper ];
    postBuild = ''
      wrapProgram "$out/bin/element-desktop" \
        --add-flags "--password-store=gnome-libsecret"
    '';
  };
in
lib.mkIf enabled {
  j0nix.user.software.packages = [ elementDesktopPkg ];

  xdg.configFile."Element/config.json".source = configFile;

  assertions = [
    {
      assertion = !(hasValue homeserverBaseUrl) || hasValue homeserverName;
      message = "settings.userSettings.<name>.programs.elementDesktop.homeserver.baseUrl requires homeserver.serverName for Element Desktop.";
    }
    {
      assertion = !ssoRedirect || hasValue homeserverBaseUrl;
      message = "settings.userSettings.<name>.programs.elementDesktop.autoLogin.ssoRedirect requires homeserver.baseUrl for Element Desktop.";
    }
  ];
}
