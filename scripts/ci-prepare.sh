#!/bin/sh
# ci-prepare.sh — nix + git auth preparation for the nix-flake-check step
# (runs inside the nixos/nix image).
#
# Auth strategy for private flake inputs (ssh://git@git.j0lab.xyz/...):
# write an insteadOf rewrite (ssh → https+token) into the global git
# config. Nix spawns git subprocesses for git-type flake fetches; those
# subprocesses read ~/.gitconfig, so the rewrite applies transparently
# without changing any flake.lock URL and without SSH keys.
#
# Note on Drone: each `commands:` entry runs as a separate subprocess.
# An `export` here would be lost by the time ci-flake-check.sh runs, so
# all communication happens through files (~/.gitconfig), not env vars.
# sed is NOT available in the nixos/nix image — use printf / git config.

set -eu

log() { printf '[prepare] %s\n' "$1"; }

# 1) flake experimental features.
echo 'experimental-features = nix-command flakes' >> /etc/nix/nix.conf
log "nix flakes enabled"

# 2) Extract the Gitea bot token from the composed secret.
log "git auth: resolving bot token from gitea_api_tokens"
test -n "${GITEA_API_TOKENS:-}" || { log "FATAL gitea_api_tokens secret missing"; exit 1; }
TOKEN=$(printf '%s' "$GITEA_API_TOKENS" | grep -o '"gitea_bot_ai": *"[^"]*"' | cut -d'"' -f4)
test -n "$TOKEN" || { log "FATAL gitea_bot_ai entry not found in gitea_api_tokens"; exit 1; }

# 3) Write the insteadOf rewrite (ssh → https+token) into the global
#    git config. Any git subprocess spawned by nix reads this file and
#    transparently rewrites ssh://git@git.j0lab.xyz/... URLs to
#    https://oauth2:TOKEN@git.j0lab.xyz/... before connecting.
rm -f "${HOME:-/root}/.gitconfig"
git config --file "${HOME:-/root}/.gitconfig" \
    "url.https://oauth2:${TOKEN}@git.j0lab.xyz/.insteadOf" \
    "ssh://git@git.j0lab.xyz/"
log "git auth: ssh transport rewritten to HTTPS (token hidden)"

# 4) Fail fast with a clear message instead of a deep nix fetch error.
#    ls-remote goes through the insteadOf rewrite too.
PRIVATE_INPUT_REPOS="NixOS/j0nix-identity-secrets NixOS/davinci-resolve-studio-patch"
for repo in $PRIVATE_INPUT_REPOS; do
    if git ls-remote "ssh://git@git.j0lab.xyz/${repo}.git" HEAD > /dev/null 2>&1; then
        log "git auth: private flake input reachable (${repo} HEAD ok)"
    else
        log "FATAL cannot fetch ${repo} via HTTPS (token invalid?)"
        exit 1
    fi
done