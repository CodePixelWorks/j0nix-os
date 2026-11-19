{
  lib,
  buildNpmPackage,
  fetchFromGitHub,
  nodejs,
}:
# Vercel's next-devtools-mcp — MCP server for Next.js dev workflows
# (log tailing, error detection, route inspection against a running
# next dev server). npm package with a TS build; consumed as a hermes
# mcp_servers entry (ai-cli.nix).
buildNpmPackage rec {
  pname = "next-devtools-mcp";
  version = "0.4.0";

  src = fetchFromGitHub {
    owner = "vercel";
    repo = "next-devtools-mcp";
    rev = "v${version}";
    hash = "sha256-QqHLUJk/TGnB3ZIUij9d5RjWSQN0NBHN1nMIlgLhQGY=";
  };

  npmDepsHash = "sha256-tBT9WWKLxWKa6QIY7YRWJkZwHn5XnQdLvCxLAKxKp9s=";

  # tsc build (npm run build); no lifecycle scripts needed.
  npmInstallFlags = [ "--ignore-scripts" ];

  meta = {
    description = "Next.js development MCP server for coding agents (Vercel)";
    homepage = "https://github.com/vercel/next-devtools-mcp";
    license = lib.licenses.asl20;
    mainProgram = "next-devtools-mcp";
  };
}
