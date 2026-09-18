# drone-ci-mcp — Rust MCP server exposing Drone CI as MCP tools.
#
# Consumes the Gitea release tarballs published by the Rust/drone-ci-mcp
# release pipeline (x86_64 + aarch64, sha256-pinned via `lib.fakeHash`
# until the first release populates real hashes — update after the first
# v-tag build).
{
  lib,
  fetchurl,
  stdenv,
}:

let
  version = "0.1.0";
  base = "https://git.j0lab.xyz/Rust/drone-ci-mcp/releases/download/v${version}";
in
stdenv.mkDerivation {
  pname = "drone-ci-mcp";
  inherit version;

  # The release pipeline ships per-arch tarballs containing the stripped
  # release binary. Pass the matching system via the package call or use
  # the platform-selecting default below.
  src =
    let
      assets = {
        "x86_64-linux" = {
          url = "${base}/drone-ci-mcp_x86_64.tar.gz";
          hash = "sha256-AAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAA=";
        };
        "aarch64-linux" = {
          url = "${base}/drone-ci-mcp_aarch64.tar.gz";
          hash = "sha256-sha256-AAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAA=";
        };
      };
      system = stdenv.hostPlatform.system;
      asset = assets.${system} or (throw "drone-ci-mcp: unsupported system ${system}");
    in
    fetchurl {
      url = asset.url;
      hash = asset.hash;
    };

  # The tarball contains only the stripped binary.
  sourceRoot = ".";

  dontConfigure = true;
  dontBuild = true;

  installPhase = ''
    runHook preInstall
    install -Dm0755 drone-ci-mcp "$out/bin/drone-ci-mcp"
    runHook postInstall
  '';

  meta = {
    description = "MCP server exposing Drone CI as tools (read + opt-in write), built on the rmcp SDK";
    homepage = "https://git.j0lab.xyz/Rust/drone-ci-mcp";
    license = lib.licenses.mit0;
    mainProgram = "drone-ci-mcp";
    platforms = [
      "x86_64-linux"
      "aarch64-linux"
    ];
    maintainers = [ ];
  };
}
