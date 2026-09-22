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
      url = "github:xddxdd/nix-cachyos-kernel";
      inputs.nixpkgs.follows = "nixpkgs";
    };
    home-manager = {
      url = "github:nix-community/home-manager/master";
      inputs.nixpkgs.follows = "nixpkgs";
    };
    nix-vscode-extensions = {
      url = "github:nix-community/nix-vscode-extensions";
      inputs.nixpkgs.follows = "nixpkgs";
    };
    codex-cli-nix = {
      url = "github:sadjow/codex-cli-nix";
      inputs.nixpkgs.follows = "nixpkgs";
    };
    # Hermes Agent — NOT the public NousResearch repo (public stays
    # vanilla upstream, zweigleisig). This workstation consumes the
    # curated package repo (NixOS/hermes on Gitea): upstream binary +
    # souls/presets/mcp-catalog/skills + the donsetch web plugin.
    hermes = {
      url = "git+ssh://git@git.j0lab.xyz/NixOS/hermes.git";
      inputs.nixpkgs.follows = "nixpkgs";
    };
    open-design = {
      url = "github:nexu-io/open-design/main";
      inputs.nixpkgs.follows = "nixpkgs";
      inputs.home-manager.follows = "home-manager";
    };
    mcp-language-server-src = {
      url = "github:isaacphi/mcp-language-server";
      flake = false;
    };
    sops-nix = {
      url = "github:Mic92/sops-nix";
      inputs.nixpkgs.follows = "nixpkgs";
    };
    j0nix-identity-secrets = {
      url = "git+ssh://git@git.j0lab.xyz/NixOS/j0nix-identity-secrets.git";
      inputs.nixpkgs.follows = "nixpkgs";
    };
    # drone-ci-mcp — Rust MCP server exposing Drone CI (ci.j0lab.xyz) as
    # tools. Consumes the release tarballs from the Rust/drone-ci-mcp
    # pipeline, same pattern as nixos-server-base. The Hermes wrapper
    # (hermes-drone-ci-mcp, built in ai-cli.nix) defaults to the full
    # tool surface — set hermesMcp.droneCi.enableWrites = false to
    # opt back into the readonly 6-tool profile.
    drone-ci-mcp = {
      url = "git+ssh://git@git.j0lab.xyz/Rust/drone-ci-mcp.git";
      inputs.nixpkgs.follows = "nixpkgs";
    };
    stylix = {
      url = "github:danth/stylix";
      inputs.nixpkgs.follows = "nixpkgs";
    };
    ags = {
      url = "git+https://github.com/Aylur/ags?rev=bbee2f18939f1ec7ff720e717cf305e73635628f";
      inputs.nixpkgs.follows = "nixpkgs";
    };
    dank-material-shell = {
      url = "github:AvengeMedia/DankMaterialShell";
      inputs.nixpkgs.follows = "nixpkgs";
    };
    quickshell-overview = {
      url = "github:Shanu-Kumawat/quickshell-overview";
      flake = false;
    };
    noctalia = {
      url = "github:noctalia-dev/noctalia-shell";
      inputs.nixpkgs.follows = "nixpkgs";
    };
    hyprmcp-src = {
      url = "github:stefanoamorelli/hyprmcp";
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
      url = "github:caelestia-dots/shell";
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
      url = "github:nix-community/nixvim";
      inputs.nixpkgs.follows = "nixpkgs";
    };
    hyprland-plugins = {
      url = "github:hyprwm/hyprland-plugins";
      inputs.hyprland.follows = "hyprland";
    };
    hypr-dynamic-cursors = {
      url = "github:VirtCode/hypr-dynamic-cursors";
      inputs.hyprland.follows = "hyprland";
    };
    hyprkcs = {
      url = "github:kosa12/hyprKCS";
      inputs.nixpkgs.follows = "nixpkgs";
    };
    hyprland-minimizer-orteip = {
      url = "github:0rteip/hyprland_minimizer";
      flake = false;
    };
    plasma-manager = {
      url = "github:nix-community/plasma-manager";
      inputs.nixpkgs.follows = "nixpkgs";
      inputs.home-manager.follows = "home-manager";
    };
    zen-browser = {
      url = "github:0xc000022070/zen-browser-flake";
      inputs.nixpkgs.follows = "nixpkgs";
    };
    aagl = {
      url = "github:ezKEa/aagl-gtk-on-nix";
      inputs.nixpkgs.follows = "nixpkgs";
    };
    resolve-patch = {
      url = "git+ssh://git@git.j0lab.xyz/NixOS/davinci-resolve-studio-patch.git";
      inputs.nixpkgs.follows = "nixpkgs";
    };
  };
}
