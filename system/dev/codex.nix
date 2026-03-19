{ inputs, lib, pkgs, settings }:
let
  dev = settings.dev or { };
  ai = dev.ai or { };
  rawCodex = ai.codex or true;
  codexCfg =
    if builtins.isAttrs rawCodex then
      rawCodex
    else
      { enable = rawCodex; };
  enabled = (ai.enable or true) && (codexCfg.enable or true);
  provider = codexCfg.provider or "upstream";
  vscodeEnable = codexCfg.vscode or true;
  mcp = codexCfg.mcp or { };
  mcpNixosEnable = enabled && (mcp.nixos or false);
  mcpGithubEnable = enabled && (mcp.github or false);
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
  mcpGithubPackage =
    if pkgs ? github-mcp-server then
      pkgs.github-mcp-server
    else
      null;
  mcpManagedServerNames = [ "nixos" "github" ];

  mcpServers =
    lib.filterAttrs (_: server: server.enable && server.package != null) {
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
    };

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
      if compatAvailable then inputs.codex-cli-nix.packages.${pkgs.stdenv.hostPlatform.system}.default else null
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
    mcpManagedServerNames
    mcpServers
    ;

  validProvider = builtins.elem provider [ "upstream" "compat" ];

  providerMessage = "settings.dev.ai.codex.provider must be one of: upstream, compat";

  compatMessage = "settings.dev.ai.codex.provider=compat requires inputs.codex-cli-nix for this system";
}
