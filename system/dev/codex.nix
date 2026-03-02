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
  inherit enabled provider vscodeEnable compatAvailable cliPackage vscodeExtension;

  validProvider = builtins.elem provider [ "upstream" "compat" ];

  providerMessage = "settings.dev.ai.codex.provider must be one of: upstream, compat";

  compatMessage = "settings.dev.ai.codex.provider=compat requires inputs.codex-cli-nix for this system";
}
