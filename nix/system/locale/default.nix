{ config, lib, ... }:
let
  cfg = config.j0nix.desktop.locale;
in
{
  options.j0nix.desktop.locale = {
    timeZone = lib.mkOption {
      type = lib.types.str;
      default = "UTC";
    };

    defaultLocale = lib.mkOption {
      type = lib.types.str;
      default = "en_US.UTF-8";
    };

    extraLocaleSettings = lib.mkOption {
      type = lib.types.attrsOf lib.types.str;
      default = { };
    };

    console.useXkbConfig = lib.mkOption {
      type = lib.types.bool;
      default = true;
    };
  };

  config = {
    time.timeZone = cfg.timeZone;
    i18n.defaultLocale = cfg.defaultLocale;
    i18n.extraLocaleSettings = cfg.extraLocaleSettings;
    console.useXkbConfig = cfg.console.useXkbConfig;
  };
}
