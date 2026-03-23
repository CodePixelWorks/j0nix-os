{ settings, ... }:
let
  loggingCfg = settings.logging or { };
  journalCfg = loggingCfg.journal or { };
in
{
  j0nix.desktop.logging = {
    enable = loggingCfg.enable or true;
    journal = {
      persistent = journalCfg.persistent or true;
      maxRetention = journalCfg.maxRetention or "14day";
      systemMaxUse = journalCfg.systemMaxUse or "1G";
      runtimeMaxUse = journalCfg.runtimeMaxUse or "256M";
      compress = journalCfg.compress or true;
    };
  };
}
