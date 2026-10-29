{
  description = "j0nix-os (independent gaming/dev NixOS)";

  outputs = inputs:
    import ./nix/system/lib/flake/outputs.nix {
      baseDir = ./.;
      inherit inputs;
    };

  inputs = {
    nixpkgs.url = "github:nixos/nixpkgs/nixos-unstable";

    nix-cachyos-kernel = {
      # `release` branch = the Hydra-built kernels that are guaranteed
      # present in the upstream binary cache. Do NOT follow our
      # nixpkgs: the pinned overlay uses the flake's own nixpkgs
      # revision, and cache hits require exactly that revision.
      url = "github:xddxdd/nix-cachyos-kernel/release";
    };
    home-manager = {
      url = "github:nix-community/home-manager/master";
      inputs.nixpkgs.follows = "nixpkgs";
    };
    nix-vscode-extensions = {
      url = "git+https://github.com/nix-community/nix-vscode-extensions?rev=69a9ce1fa6fec39b405660df82fd25994e67730a";
      inputs.nixpkgs.follows = "nixpkgs";
    };
    # ArtCraft apps (pdfcraft etc. — AppImage-packaged, verified mirrors,
    # github:ipeglin/artcraft-nix). Only the pdfcraft package is consumed.
    artcraft = {
      url = "github:ipeglin/artcraft-nix";
      inputs.nixpkgs.follows = "nixpkgs";
    };
    codex-cli-nix = {
      url = "git+https://github.com/sadjow/codex-cli-nix?rev=0ba1b93ea032580f9cf19ab26fb8a1b5d0f97f99";
      inputs.nixpkgs.follows = "nixpkgs";
    };
    mcp-language-server-src = {
      url = "git+https://github.com/isaacphi/mcp-language-server?rev=e4395849a52e18555361abab60a060802c06bf50";
      flake = false;
    };
    sops-nix = {
      url = "git+https://github.com/Mic92/sops-nix?rev=44931708c62937c2b1bf7953902989fa5bb9ee1b";
      inputs.nixpkgs.follows = "nixpkgs";
    };
    stylix = {
      url = "git+https://github.com/danth/stylix?rev=fb28acd59e2ac1984ec84fa496599d6b4bf3e690";
      inputs.nixpkgs.follows = "nixpkgs";
    };
    ags = {
      url = "git+https://github.com/Aylur/ags?rev=bbee2f18939f1ec7ff720e717cf305e73635628f";
      inputs.nixpkgs.follows = "nixpkgs";
    };
    dank-material-shell = {
      url = "git+https://github.com/AvengeMedia/DankMaterialShell?rev=c4aea85296a3a20e34be7e467170265c0c29dc38";
      inputs.nixpkgs.follows = "nixpkgs";
    };
    quickshell-overview = {
      url = "git+https://github.com/Shanu-Kumawat/quickshell-overview?rev=47f0d402822b26805ed0ecea4a770c38c537b728";
      flake = false;
    };
    noctalia = {
      url = "git+https://github.com/noctalia-dev/noctalia-shell?rev=0d234d64e7e568ffdd9470292a68b8d0f40ea79a";
      inputs.nixpkgs.follows = "nixpkgs";
    };
    hyprmcp-src = {
      url = "git+https://github.com/stefanoamorelli/hyprmcp?rev=13d5195e6a474078183cb031771be7a71b330bb6";
      flake = false;
    };
    quickshell-stable = {
      url = "github:quickshell-mirror/quickshell?ref=v0.2.1";
      inputs.nixpkgs.follows = "nixpkgs";
    };
    quickshell-dev = {
      url = "github:quickshell-mirror/quickshell?ref=master";
      inputs.nixpkgs.follows = "nixpkgs";
    };
    caelestia-shell = {
      url = "git+https://github.com/caelestia-dots/shell?rev=a3a8fe59aba2c0048ab02dc817748678f96076ff";
      inputs.nixpkgs.follows = "nixpkgs";
      inputs.quickshell.follows = "quickshell-stable";
    };
    caelestia-shell-dev = {
      url = "github:caelestia-dots/shell?ref=main";
      inputs.nixpkgs.follows = "nixpkgs";
      inputs.quickshell.follows = "quickshell-dev";
    };
    hyprland = {
      url = "git+https://github.com/hyprwm/Hyprland?ref=refs/tags/v0.55.4&submodules=1";
      inputs.nixpkgs.follows = "nixpkgs";
    };
    nixvim = {
      url = "git+https://github.com/nix-community/nixvim?rev=5980a626794486abad69fca7667f9c11dfbc3bd7";
      inputs.nixpkgs.follows = "nixpkgs";
    };
    hyprland-plugins = {
      url = "git+https://github.com/hyprwm/hyprland-plugins?rev=428bfcd1c9ee34965400bb359349f518140c9920";
      inputs.hyprland.follows = "hyprland";
    };
    hypr-dynamic-cursors = {
      url = "git+https://github.com/VirtCode/hypr-dynamic-cursors?rev=2a8d0b735328d874a78ca93b2f201649f712a74a";
      inputs.hyprland.follows = "hyprland";
    };
    hyprkcs = {
      url = "git+https://github.com/kosa12/hyprKCS?rev=6319243ebf8da4b8456f49d36f07b5c24e032548";
      inputs.nixpkgs.follows = "nixpkgs";
    };
    hyprland-minimizer-orteip = {
      url = "git+https://github.com/0rteip/hyprland_minimizer?rev=3859257bab455e09742e7aec5bd5f70e8880ebf1";
      flake = false;
    };
    plasma-manager = {
      url = "git+https://github.com/nix-community/plasma-manager?rev=a19a2a029fa180911bd89c554dca1616e10f4c1d";
      inputs.nixpkgs.follows = "nixpkgs";
      inputs.home-manager.follows = "home-manager";
    };
    zen-browser = {
      url = "git+https://github.com/0xc000022070/zen-browser-flake?rev=9342d127aa8c585e82f3f57ddb25800fd546029f";
      inputs.nixpkgs.follows = "nixpkgs";
    };
    aagl = {
      url = "git+https://github.com/ezKEa/aagl-gtk-on-nix?rev=d82d6d6f66caf4b63fb154e62fad83c627874127";
      inputs.nixpkgs.follows = "nixpkgs";
    };
  };
}
