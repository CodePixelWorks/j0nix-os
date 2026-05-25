{ buildGoModule, lib, src }:

buildGoModule {
  pname = "mcp-language-server-j0nix";
  version = "unstable-2026-03-19";

  inherit src;

  vendorHash = "sha256-WcYKtM8r9xALx68VvgRabMPq8XnubhTj6NAdtmaPa+g=";
  subPackages = [ "." ];

  ldflags = [
    "-s"
    "-w"
  ];

  meta = with lib; {
    description = "MCP bridge for Language Server Protocol backends";
    homepage = "https://github.com/isaacphi/mcp-language-server";
    license = licenses.bsd3;
    mainProgram = "mcp-language-server";
    platforms = platforms.linux;
    maintainers = [ ];
  };
}
