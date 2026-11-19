# bubblewrap-ai.nix — bubblewrap-ai (bwai) AI agent sandbox (bwrap-based).
#
# bubblewrap-ai runs AI coding agents (Claude Code, Gemini CLI, Goose)
# inside a bubblewrap sandbox:
#   - host filesystem mounted read-only
#   - only the current working directory is writable
#   - only whitelisted dotfiles and env vars are exposed
#
# This is the lightweight alternative to terok (Podman-based):
# no container daemon, no image pulls, kernel-enforced user namespaces,
# millisecond startup.
#
# Upstream: https://github.com/umago/bubblewrap-ai
# Pinned to v0.3.1. Go 1.21, stdlib only → no vendor hash needed.
{
  lib,
  buildGoModule,
  fetchFromGitHub,
}:

buildGoModule {
  pname = "bwai";
  version = "0.3.1";

  src = fetchFromGitHub {
    owner = "umago";
    repo = "bubblewrap-ai";
    rev = "v0.3.1";
    hash = "sha256-SNvhlhVyEm3jq8/SizL+l7C/3P4gfsvKLNdGk/dRKVo=";
  };

  vendorHash = null;

  postInstall = ''
    mv $out/bin/bubblewrap-ai $out/bin/bwai 2>/dev/null || true
    [ -f $out/bin/bwai ] || mv $out/bin/* $out/bin/bwai 2>/dev/null || true
  '';

  # No test sandbox here (chicken-and-egg with bwrap).
  doCheck = false;

  meta = with lib; {
    description = "Bubblewrap sandbox for AI coding agents (Claude, Gemini, Goose)";
    homepage = "https://github.com/umago/bubblewrap-ai";
    license = licenses.mit;
    mainProgram = "bwai";
  };
}
