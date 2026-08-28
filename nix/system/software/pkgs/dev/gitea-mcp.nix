{
  buildGoModule,
  fetchFromGitea,
  lib,
}:

buildGoModule rec {
  pname = "gitea-mcp";
  version = "1.6.0";

  src = fetchFromGitea {
    domain = "gitea.com";
    owner = "gitea";
    repo = "gitea-mcp";
    rev = "v${version}";
    hash = "sha256-A4HqHEicIdq7L/hmQ+tWeTJWnVscSIfCn3ku1dKSCkY=";
  };

  vendorHash = "sha256-BYHcV5WSklGqdeTN7S2AMtscJDCA/8n1gEOgLzr9Gmk=";

  ldflags = [
    "-s"
    "-w"
    "-X main.Version=v${version}"
  ];

  meta = {
    description = "Official MCP server for Gitea";
    homepage = "https://gitea.com/gitea/gitea-mcp";
    license = lib.licenses.mit;
    mainProgram = "gitea-mcp";
    platforms = lib.platforms.linux;
    maintainers = [ ];
  };
}
