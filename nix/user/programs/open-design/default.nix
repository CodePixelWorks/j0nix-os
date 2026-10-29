{
  inputs,
  lib,
  pkgs,
  settings,
  ...
}:
let
  cfg = (settings.programs or { }).openDesign or { };
  enabled = cfg.enable or false;
  autoStart = cfg.autoStart or true;
  host = cfg.host or "127.0.0.1";
  port = cfg.port or 7456;
  daemonUrl = "http://${host}:${toString port}/";
  system = pkgs.stdenv.hostPlatform.system;
  # The lasse-herzog packaging flake ships the FULL 0.26.1 build in
  # one package (daemon + web UI + desktop shell) — upstream retired
  # their own Nix distribution 2026-08-31 (#7644), so this community
  # flake is the maintained source (GH-Actions polls releases every
  # 6h, regenerates hashes, smoke-tests before committing).
  # It pins its own nixpkgs (pnpm fetcher + electron_44) — do NOT
  # make this input follow our nixpkgs.
  openDesignPackage = inputs.open-design.packages.${system}.default or null;
  openDesignWrappedBin =
    if openDesignPackage == null then
      null
    else
      pkgs.writeShellScriptBin "open-design" ''
        export OD_DATA_DIR="''${OD_DATA_DIR:-$HOME/.od}"
        export NODE_ENV=production
        exec ${lib.getExe pkgs.nodejs} \
          ${openDesignPackage}/lib/open-design/apps/daemon/dist/cli.js \
          "$@"
      '';
  openDesignCli =
    if openDesignWrappedBin == null then
      null
    else
      pkgs.writeShellScriptBin "od" ''
        exec ${lib.getExe' openDesignWrappedBin "open-design"} "$@"
      '';
  openDesignBrowserLauncher =
    if openDesignWrappedBin == null then
      null
    else
      pkgs.writeShellScriptBin "open-design-launch" ''
        set -eu

        ${pkgs.systemd}/bin/systemctl --user start open-design.service

        for _ in $(seq 1 45); do
          if ${pkgs.curl}/bin/curl -fsS ${lib.escapeShellArg daemonUrl} >/dev/null 2>&1; then
            exec ${pkgs.xdg-utils}/bin/xdg-open ${lib.escapeShellArg daemonUrl}
          fi
          sleep 1
        done

        echo "error: Open Design did not become ready at ${daemonUrl}" >&2
        exit 1
      '';
  openDesignDesktopItem =
    if openDesignBrowserLauncher == null || openDesignPackage == null then
      null
    else
      pkgs.makeDesktopItem {
        name = "open-design";
        desktopName = "Open Design";
        comment = "Open the local Open Design web UI";
        exec = "open-design-launch";
        icon = "${openDesignPackage}/lib/open-design/apps/web/out/logo.svg";
        terminal = false;
        categories = [
          "Graphics"
          "Development"
        ];
      };
in
lib.mkIf enabled {
  systemd.user.services.open-design = {
    Unit = {
      Description = "Open Design local daemon";
      PartOf = [ "graphical-session.target" ];
      After = [ "graphical-session.target" ];
    };
    Service = {
      ExecStart = "${lib.getExe' openDesignWrappedBin "open-design"} --no-open --host ${lib.escapeShellArg host} --port ${toString port}";
      Restart = "on-failure";
      RestartSec = 2;
    };
    Install.WantedBy = lib.optionals autoStart [ "graphical-session.target" ];
  };

  assertions = [
    {
      assertion = openDesignPackage != null;
      message = "inputs.open-design does not provide a default package for ${system}.";
    }
  ];

  j0nix.user.software.packages = lib.filter (pkg: pkg != null) [
    openDesignWrappedBin
    openDesignCli
    openDesignBrowserLauncher
    openDesignDesktopItem
  ];
}
