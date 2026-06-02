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
  system = pkgs.stdenv.hostPlatform.system;
  upstreamPackages = inputs.open-design.packages.${system} or { };
  pnpm_10 = pkgs.pnpm_10.overrideAttrs (_old: rec {
    version = "10.33.2";
    src = pkgs.fetchurl {
      url = "https://registry.npmjs.org/pnpm/-/pnpm-${version}.tgz";
      hash = "sha256-envPE9f2zrOUbAOXg3PZm+n94cr8MAC9/tTE95EWdhA=";
    };
  });
  openDesignDaemonPackage = upstreamPackages.default or null;
  openDesignWebPackage =
    if upstreamPackages ? web then
      upstreamPackages.web.overrideAttrs (old: {
        pnpmDeps = pkgs.fetchPnpmDeps {
          inherit (old) pname version src pnpmWorkspaces;
          hash = (import "${inputs.open-design}/nix/pnpm-deps.nix").webHash;
          fetcherVersion = 3;
          pnpm = pnpm_10;
        };
      })
    else
      null;
  openDesignPackage =
    if openDesignDaemonPackage == null || openDesignWebPackage == null then
      null
    else
      pkgs.symlinkJoin {
        name = "open-design-with-web";
        paths = [ openDesignDaemonPackage ];
        postBuild = ''
          mkdir -p "$out/lib/open-design/apps/web"
          ln -s ${openDesignWebPackage} "$out/lib/open-design/apps/web/out"
        '';
      };
  openDesignCli =
    if openDesignPackage == null then
      null
    else
      pkgs.writeShellScriptBin "od" ''
        export OD_DATA_DIR="''${OD_DATA_DIR:-$HOME/.od}"
        exec ${lib.getExe' openDesignPackage "od"} "$@"
      '';
in
lib.mkIf enabled {
  assertions = [
    {
      assertion = openDesignDaemonPackage != null;
      message = "inputs.open-design does not provide a default package for ${system}.";
    }
    {
      assertion = openDesignWebPackage != null;
      message = "inputs.open-design does not provide a web package for ${system}.";
    }
  ];

  j0nix.user.software.packages = [ openDesignCli ];
}
