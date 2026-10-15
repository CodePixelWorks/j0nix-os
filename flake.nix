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
      url = "git+https://github.com/nix-community/nix-vscode-extensions?rev=9cfe29321e0ba1d2b5d53a76332669ae72c421f6";
      inputs.nixpkgs.follows = "nixpkgs";
    };
    codex-cli-nix = {
      url = "git+https://github.com/sadjow/codex-cli-nix?rev=65edd6ed0a1ef40e384c27d6da661a999b098f45";
      inputs.nixpkgs.follows = "nixpkgs";
    };
    open-design = {
      # Pinned to the last rev with a flake.nix: upstream deleted the flake
      # from main, which breaks any `nix flake lock` of this repo (and with
      # it Renovate's lockFileMaintenance — the whole lock refresh dies on
      # this single input). rev-pin form is Renovate-addressable (git-refs
      # datasource) and keeps the lock stable. Un-pin once upstream restores
      # a flake.nix.
      url = "git+https://github.com/nexu-io/open-design?rev=99c13e083e070f44aaa0009b2fc96589118c2a9a";
      inputs.nixpkgs.follows = "nixpkgs";
      inputs.home-manager.follows = "home-manager";
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
      url = "git+https://github.com/AvengeMedia/DankMaterialShell?rev=0b9d931ea3db44866f4fd29394d140674ae474c6";
      inputs.nixpkgs.follows = "nixpkgs";
    };
    quickshell-overview = {
      url = "git+https://github.com/Shanu-Kumawat/quickshell-overview?rev=47f0d402822b26805ed0ecea4a770c38c537b728";
      flake = false;
    };
    noctalia = {
      url = "git+https://github.com/noctalia-dev/noctalia-shell?rev=30415127e6c864212c61804a531a018980718b1f";
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
      url = "git+https://github.com/caelestia-dots/shell?rev=454f46da16ae75cc57f34adf48dea74db0fa5175";
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
      url = "git+https://github.com/hyprwm/hyprland-plugins?rev=bca761c5363df8ff73e2040b527c75cb682e9120";
      inputs.hyprland.follows = "hyprland";
    };
    hypr-dynamic-cursors = {
      url = "git+https://github.com/VirtCode/hypr-dynamic-cursors?rev=b9739b1db4a48616d66af29239ab0fe2756d28f6";
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
