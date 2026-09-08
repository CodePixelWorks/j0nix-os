#!/bin/sh
# ci-prepare.sh — nix + git auth preparation for the nix-flake-check step
# (runs inside the nixos/nix image).
#
# Kept as a separate script so the CI log shows one curated line instead
# of raw command traces (Drone echoes only `+ ./scripts/ci-prepare.sh`).

set -eu

log() { printf '[prepare] %s\n' "$1"; }

# 1) flake experimental features.
echo 'experimental-features = nix-command flakes' >> /etc/nix/nix.conf
log "nix flakes enabled"

# 2) Rewrite the ssh transport to HTTPS + token for the private
#    flake inputs (j0nix-identity-secrets, davinci-resolve-studio-patch).
#    GIT_CONFIG_GLOBAL is honored by the git subprocesses nix spawns
#    for flake fetches. Nix normalizes `git+ssh://` to `ssh://` before
#    git sees it, and insteadOf on the normalized form intercepts the
#    fetch (same pattern as nixos-server-base).
log "git auth: resolving bot token from gitea_api_tokens"
test -n "${GITEA_API_TOKENS:-}" || { log "FATAL gitea_api_tokens secret missing"; exit 1; }
TOKEN=$(printf '%s' "$GITEA_API_TOKENS" | grep -o '"gitea_bot_ai": *"[^"]*"' | cut -d'"' -f4)
test -n "$TOKEN" || { log "FATAL gitea_bot_ai entry not found in gitea_api_tokens"; exit 1; }
git config --file /tmp/ci-gitconfig \
    "url.https://oauth2:$TOKEN@git.j0lab.xyz/.insteadOf" \
    "ssh://git@git.j0lab.xyz/"
export GIT_CONFIG_GLOBAL=/tmp/ci-gitconfig
log "git auth: ssh transport rewritten to HTTPS (token hidden)"

# 3) Fail fast with a clear message instead of a deep nix fetch error.
PRIVATE_FLAKE_INPUTS="NixOS/j0nix-identity-secrets NixOS/davinci-resolve-studio-patch"
for repo in $PRIVATE_FLAKE_INPUTS; do
    if git ls-remote "ssh://git@git.j0lab.xyz/$repo.git" HEAD > /dev/null 2>&1; then
        log "git auth: private flake input reachable ($repo HEAD ok)"
    else
        log "FATAL cannot fetch $repo via HTTPS (token invalid?)"
        exit 1
    fi
done
