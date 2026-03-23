{ settings, ... }:
{
  j0nix.desktop.locale = {
    timeZone = settings.timezone;
    defaultLocale = settings.locale;
    extraLocaleSettings = {
      LANG = settings.locale;
      # LC_ALL intentionally omitted — it overrides ALL categories and breaks
      # tools like sort/awk that expect en_US formatting for numeric output.
      # LANGUAGE is a GNU gettext fallback list, not a locale category.
      LANGUAGE = "de:en";
    };
    console.useXkbConfig = true;
  };
}
