{ config, lib, ... }:
let
  cfg = config.j0nix.desktop.logging;
  journalCfg = cfg.journal;
  boolToYesNo = value: if value then "yes" else "no";
in
{
  options.j0nix.desktop.logging = {
    enable = lib.mkOption {
      type = lib.types.bool;
      default = true;
    };

    journal = {
      persistent = lib.mkOption {
        type = lib.types.bool;
        default = true;
      };

      maxRetention = lib.mkOption {
        type = lib.types.str;
        default = "14day";
      };

      systemMaxUse = lib.mkOption {
        type = lib.types.str;
        default = "1G";
      };

      runtimeMaxUse = lib.mkOption {
        type = lib.types.str;
        default = "256M";
      };

      compress = lib.mkOption {
        type = lib.types.bool;
        default = true;
      };
    };
  };

  config = lib.mkIf cfg.enable {
    services.journald = {
      storage = if journalCfg.persistent then "persistent" else "auto";
      extraConfig = lib.concatStringsSep "\n" [
        "Compress=${boolToYesNo journalCfg.compress}"
        "SystemMaxUse=${journalCfg.systemMaxUse}"
        "RuntimeMaxUse=${journalCfg.runtimeMaxUse}"
        "MaxRetentionSec=${journalCfg.maxRetention}"
        "SplitMode=uid"
        "SyncIntervalSec=5m"
      ];
    };

    systemd.tmpfiles.rules = lib.optional journalCfg.persistent
      "d /var/log/journal 2755 root systemd-journal - -";

    assertions = [
      {
        assertion = journalCfg.maxRetention != "";
        message = "j0nix.desktop.logging.journal.maxRetention must not be empty";
      }
      {
        assertion = journalCfg.systemMaxUse != "";
        message = "j0nix.desktop.logging.journal.systemMaxUse must not be empty";
      }
      {
        assertion = journalCfg.runtimeMaxUse != "";
        message = "j0nix.desktop.logging.journal.runtimeMaxUse must not be empty";
      }
    ];
  };
}
