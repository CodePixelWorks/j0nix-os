{
  baseDir,
  inputs,
}:
let
  nixpkgs = inputs.nixpkgs;
  home-manager = inputs.home-manager;
  lib = nixpkgs.lib;
  overlays = import ./overlays.nix {
    inherit baseDir inputs nixpkgs;
  };

  settingsFile =
    if builtins.pathExists (baseDir + "/settings.nix") then
      baseDir + "/settings.nix"
    else
      throw ''
        settings.nix is required but was not found in the evaluated flake source.

        This usually means the flake was evaluated from a git snapshot that does not
        include your local ignored settings.nix file.

        Use:
          nixos-rebuild switch --flake path:${toString baseDir}#<hostname>
      '';

  mkHostAttrs = profileName:
    let
      profileDir = baseDir + "/profiles/${profileName}";
      profileDetailsFile =
        if builtins.pathExists (profileDir + "/details.nix") then
          profileDir + "/details.nix"
        else
          throw ''
            ${profileName}: profiles/${profileName}/details.nix is required for flake evaluation.

            The matching .example file is only a template and is never imported automatically.

            Create it from:
              cp profiles/${profileName}/details.nix.example profiles/${profileName}/details.nix
          '';
      profileDetails = import profileDetailsFile { };
      pkgs = import nixpkgs {
        system = profileDetails.system;
        overlays = overlays.default;
        config.allowUnfree = true;
      };
      rawSettings = import settingsFile { inherit inputs; };
      settings = rawSettings // {
        secrets = (rawSettings.secrets or { }) // (import (profileDir + "/secrets.nix"));
        profileDetails = profileDetails;
        themeDetails = import (baseDir + "/themes/${rawSettings.theme}.nix") { inherit pkgs; };
      };
      baseSettings = builtins.removeAttrs settings [
        "profileDetails"
        "themeDetails"
        "username"
        "dotfilesDir"
      ];
      userOverrides = settings.userSettings or { };
      mkUserSettings = import (baseDir + "/nix/system/lib/settings/mk-user-settings.nix") {
        inherit baseDir baseSettings lib pkgs profileDetails userOverrides;
      };
      mkHomeModules = import (baseDir + "/nix/system/lib/home/mk-home-modules.nix") {
        inherit baseDir lib profileDir;
      };
    in
    {
      inherit
        profileDir
        profileDetails
        pkgs
        settings
        baseSettings
        userOverrides
        mkUserSettings
        mkHomeModules
        ;
    };

  mkNixosSystem = { profileName }:
    let
      host = mkHostAttrs profileName;
      hmUsers = builtins.attrNames (host.settings.userSettings or { });
    in
    nixpkgs.lib.nixosSystem {
      modules = [
        inputs.stylix.nixosModules.stylix
        home-manager.nixosModules.home-manager
        ({ ... }: {
          nixpkgs.overlays = [
            overlays.vscodeOverlay
            overlays.localFixesOverlay
            overlays.resolveOverlay
          ];
        })
        ({ pkgs, ... }: {
          home-manager = {
            useGlobalPkgs = true;
            useUserPackages = true;
            backupFileExtension = "backup";
            backupCommand = "${pkgs.writeShellScript "home-manager-backup-unique" ''
              set -eu

              target="''${1:?missing target path}"
              if [ ! -e "$target" ] && [ ! -L "$target" ]; then
                exit 0
              fi

              ext="''${HOME_MANAGER_BACKUP_EXT:-backup}"
              timestamp="$(${pkgs.coreutils}/bin/date +%Y%m%d-%H%M%S)"
              backup="$target.$ext-$timestamp"
              index=0

              while [ -e "$backup" ] || [ -L "$backup" ]; do
                index=$((index + 1))
                backup="$target.$ext-$timestamp-$index"
              done

              ${pkgs.coreutils}/bin/mv -- "$target" "$backup"
            ''}";
            extraSpecialArgs = {
              inherit inputs;
              profileMeta = host.profileDetails;
            };
            sharedModules = hmSharedModules host.settings;
            users = builtins.listToAttrs (
              map (username: {
                name = username;
                value = { ... }:
                  let
                    userSettings = host.mkUserSettings username;
                  in
                  {
                    _module.args = {
                      inherit inputs;
                      profileMeta = host.profileDetails;
                      settings = userSettings;
                    };
                    imports = host.mkHomeModules userSettings;
                  };
              }) hmUsers
            );
          };
        })
        (host.profileDir + "/configuration.nix")
      ]
      ++ lib.optional host.settings.enableSops inputs.sops-nix.nixosModules.sops;
      specialArgs = {
        inherit inputs;
        profileMeta = host.profileDetails;
        settings = host.settings;
      };
    };

  mkHomeManagerConfiguration = { username, profileName }:
    let
      host = mkHostAttrs profileName;
      userSettings = host.mkUserSettings username;
    in
    home-manager.lib.homeManagerConfiguration {
      pkgs = host.pkgs;
      modules = (host.mkHomeModules userSettings) ++ hmSharedModulesStandalone host.settings;
      extraSpecialArgs = {
        inherit inputs;
        profileMeta = host.profileDetails;
        settings = userSettings;
      };
    };

  hmSharedModules = settings: [
    inputs.plasma-manager.homeModules.plasma-manager
    inputs.nixvim.homeModules.nixvim
  ]
  ++ lib.optional (settings.enableSops or false) inputs.sops-nix.homeManagerModules.sops;

  hmSharedModulesStandalone = settings: (hmSharedModules settings) ++ [ inputs.stylix.homeModules.stylix ];

  profileRoot = baseDir + "/profiles";
  profileDirs = builtins.readDir profileRoot;
  profileNames = lib.sort lib.lessThan (
    lib.filter (
      name:
      let
        profileDir = profileRoot + "/${name}";
      in
      profileDirs.${name} == "directory"
      && builtins.pathExists (profileDir + "/details.nix")
    ) (builtins.attrNames (builtins.readDir profileRoot))
  );
  profileEntries = map (profileName: {
    name = (mkHostAttrs profileName).profileDetails.hostname;
    inherit profileName;
  }) profileNames;
  profileHostNames = map (entry: entry.name) profileEntries;
  duplicateProfileHostNames = lib.filter (
    name: lib.count (entry: entry.name == name) profileEntries > 1
  ) (lib.unique profileHostNames);
  checkedProfileEntries =
    if duplicateProfileHostNames != [ ] then
      throw "Profile hostnames must be unique; duplicate hostname(s): ${lib.concatStringsSep ", " duplicateProfileHostNames}"
    else if profileEntries == [ ] then
      throw "No profile with profiles/<name>/details.nix was found. Create a profile before evaluating this flake."
    else
      profileEntries;

  nixosConfigurations = builtins.listToAttrs (map (entry: {
    name = entry.name;
    value = mkNixosSystem { profileName = entry.profileName; };
  }) checkedProfileEntries);

  homeConfigurations = builtins.listToAttrs (
    lib.concatMap (
      entry:
      let
        host = mkHostAttrs entry.profileName;
        users = builtins.attrNames (host.settings.userSettings or { });
      in
      map (username: {
        name = "${username}@${entry.name}";
        value = mkHomeManagerConfiguration {
          inherit username;
          profileName = entry.profileName;
        };
      }) users
    ) checkedProfileEntries
  );
in
{
  inherit nixosConfigurations homeConfigurations;
}
