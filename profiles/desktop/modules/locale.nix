{ settings, ... }:
{
  j0nix.desktop.locale = {
    timeZone = settings.timezone;
    defaultLocale = settings.locale;
    extraLocaleSettings = {
      LANG = settings.locale;
      LC_ALL = settings.locale;
      LANGUAGE = settings.locale;
    };
    console.useXkbConfig = true;
  };
}
