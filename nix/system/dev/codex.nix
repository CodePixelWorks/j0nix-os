{
  inputs,
  lib,
  pkgs,
  settings,
}:
let
  dev = settings.dev or { };
  ai = dev.ai or { };
  rawCodex = ai.codex or true;
  codexCfg = if builtins.isAttrs rawCodex then rawCodex else { enable = rawCodex; };
  enabled = (ai.enable or true) && (codexCfg.enable or true);
  provider = codexCfg.provider or "upstream";
  vscodeEnable = codexCfg.vscode or true;
  mcp = codexCfg.mcp or { };
  rawLsp = mcp.lsp or false;
  lspCfg = if builtins.isAttrs rawLsp then rawLsp else { enable = rawLsp; };
  mcpNixosEnable = enabled && (mcp.nixos or false);
  mcpGithubEnable = enabled && (mcp.github or false);
  mcpHyprlandEnable = enabled && (mcp.hyprland or false);
  mcpLspEnable = enabled && (lspCfg.enable or false);
  mcpLspLanguages =
    if mcpLspEnable then
      (lspCfg.languages or [
        "nix"
        "rust"
        "python"
        "typescript"
        "go"
      ]
      )
    else
      [ ];
  mcpRemotes = ai.mcpRemotes or { };
  mcpNixosPackage =
    if pkgs ? mcp-nixos then
      pkgs.mcp-nixos.overridePythonAttrs (_: {
        # nixpkgs 26.05 currently evaluates the package with a broken pytest
        # TOML shape on Python 3.13. The runtime package is fine; only the
        # check phase fails.
        doCheck = false;
      })
    else
      null;
  mcpGithubPackage = if pkgs ? github-mcp-server then pkgs.github-mcp-server else null;
  mcpHyprlandPackage =
    if inputs ? hyprmcp-src then
      let
        pythonWithMcp = pkgs.python3.withPackages (ps: [ ps.mcp ]);
      in
      pkgs.writeShellApplication {
        name = "j0nix-mcp-hyprland";
        runtimeInputs = [
          pkgs.hyprland
          pythonWithMcp
        ];
        text = ''
          exec ${pythonWithMcp}/bin/python ${inputs.hyprmcp-src}/hyprmcp/server.py
        '';
      }
    else
      null;
  mcpLspPackage = if pkgs ? mcp-language-server-j0nix then pkgs.mcp-language-server-j0nix else null;

  lspLanguageSpecs = {
    nix = {
      serverName = "lsp-nix";
      wrapperName = "j0nix-mcp-lsp-nix";
      runtimeInputs = [
        mcpLspPackage
        pkgs.nixd
      ];
      lspCommand = "${pkgs.nixd}/bin/nixd";
      lspArgs = [ ];
    };
    rust = {
      serverName = "lsp-rust";
      wrapperName = "j0nix-mcp-lsp-rust";
      runtimeInputs = [
        mcpLspPackage
        pkgs.rust-analyzer
      ];
      lspCommand = "${pkgs.rust-analyzer}/bin/rust-analyzer";
      lspArgs = [ ];
    };
    python = {
      serverName = "lsp-python";
      wrapperName = "j0nix-mcp-lsp-python";
      runtimeInputs = [
        mcpLspPackage
        pkgs.pyright
      ];
      lspCommand = "${pkgs.pyright}/bin/pyright-langserver";
      lspArgs = [ "--stdio" ];
    };
    typescript = {
      serverName = "lsp-typescript";
      wrapperName = "j0nix-mcp-lsp-typescript";
      runtimeInputs = [
        mcpLspPackage
        pkgs.typescript-language-server
        pkgs.nodejs
      ];
      lspCommand = "${pkgs.typescript-language-server}/bin/typescript-language-server";
      lspArgs = [ "--stdio" ];
    };
    go = {
      serverName = "lsp-go";
      wrapperName = "j0nix-mcp-lsp-go";
      runtimeInputs = [
        mcpLspPackage
        pkgs.gopls
      ];
      lspCommand = "${pkgs.gopls}/bin/gopls";
      lspArgs = [ ];
    };
  };
  supportedMcpLspLanguages = builtins.attrNames lspLanguageSpecs;
  validMcpLspLanguages = lib.all (lang: builtins.elem lang supportedMcpLspLanguages) mcpLspLanguages;

  mkLspWrapper =
    language: spec:
    pkgs.writeShellApplication {
      name = spec.wrapperName;
      runtimeInputs = spec.runtimeInputs;
      text =
        let
          lspArgsFragment =
            if spec.lspArgs == [ ] then
              ""
            else
              " -- ${lib.concatMapStringsSep " " lib.escapeShellArg spec.lspArgs}";
        in
        ''
          set -eu
          workspace="$(${pkgs.git}/bin/git rev-parse --show-toplevel 2>/dev/null || pwd)"
          exec ${lib.getExe mcpLspPackage} --workspace "$workspace" --lsp ${lib.escapeShellArg spec.lspCommand}${lspArgsFragment}
        '';
    };

  mcpLspServers =
    if !mcpLspEnable || mcpLspPackage == null || !validMcpLspLanguages then
      { }
    else
      builtins.listToAttrs (
        map (
          language:
          let
            spec = lspLanguageSpecs.${language};
            wrapper = mkLspWrapper language spec;
          in
          {
            name = spec.serverName;
            value = {
              enable = true;
              package = wrapper;
              command = spec.wrapperName;
            };
          }
        ) mcpLspLanguages
      );

  mcpManagedServerNames = [
    "nixos"
    "github"
    "hyprland"
  ]
  ++ map (language: lspLanguageSpecs.${language}.serverName) (
    lib.filter (language: builtins.hasAttr language lspLanguageSpecs) mcpLspLanguages
  );

  mcpLspRuntimePackages =
    if !mcpLspEnable || !validMcpLspLanguages then
      [ ]
    else
      lib.unique (lib.concatMap (language: lspLanguageSpecs.${language}.runtimeInputs) mcpLspLanguages);

  mcpServers = lib.filterAttrs (_: server: server.enable && server.package != null) (
    {
      nixos = {
        enable = mcpNixosEnable;
        package = mcpNixosPackage;
        command = "mcp-nixos";
      };
      github = {
        enable = mcpGithubEnable;
        package = mcpGithubPackage;
        command = "github-mcp-server";
      };
      hyprland = {
        enable = mcpHyprlandEnable;
        package = mcpHyprlandPackage;
        command = "j0nix-mcp-hyprland";
      };
    }
    // mcpLspServers
  );

  compatAvailable =
    (inputs ? codex-cli-nix)
    && (inputs.codex-cli-nix ? packages)
    && (builtins.hasAttr pkgs.stdenv.hostPlatform.system inputs.codex-cli-nix.packages)
    && (inputs.codex-cli-nix.packages.${pkgs.stdenv.hostPlatform.system} ? default);

  upstreamPackage = pkgs.writeShellApplication {
    name = "codex";
    runtimeInputs = [ pkgs.nodejs ];
    text = ''
      exec ${pkgs.nodejs}/bin/npx --yes @openai/codex@latest "$@"
    '';
  };

  cliPackage =
    if provider == "compat" then
      if compatAvailable then
        inputs.codex-cli-nix.packages.${pkgs.stdenv.hostPlatform.system}.default
      else
        null
    else
      upstreamPackage;

  marketplace = pkgs.nix-vscode-extensions.vscode-marketplace or { };
  vscodeExtension = lib.attrByPath [ "openai" "chatgpt" ] null marketplace;
in
{
  inherit
    enabled
    provider
    vscodeEnable
    compatAvailable
    cliPackage
    vscodeExtension
    mcpNixosEnable
    mcpNixosPackage
    mcpGithubEnable
    mcpGithubPackage
    mcpHyprlandEnable
    mcpHyprlandPackage
    mcpLspEnable
    mcpLspLanguages
    mcpLspPackage
    mcpLspRuntimePackages
    mcpManagedServerNames
    mcpServers
    mcpRemotes
    validMcpLspLanguages
    supportedMcpLspLanguages
    ;

  validProvider = builtins.elem provider [
    "upstream"
    "compat"
  ];

  providerMessage = "settings.dev.ai.codex.provider must be one of: upstream, compat";

  compatMessage = "settings.dev.ai.codex.provider=compat requires inputs.codex-cli-nix for this system";
}
