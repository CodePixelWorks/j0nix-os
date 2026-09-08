#!/bin/sh
# ci-prepare.sh — nix + git auth preparation for the nix-flake-check step
# (runs inside the nixos/nix image).
#
# Kept as a separate script so the CI log shows one curated line instead
# of raw command traces (Drone echoes only `+ ./scripts/ci-prepare.sh`).
#
# Auth strategy: Nix's flake fetcher is built on libgit2 and ignores
# `git config url.*.insteadOf` — it dereferences `git+ssh://` URLs
# directly and fails on host-key verification when the CI container has
# no SSH key. The reliable intercept is `--override-input <name>=<url>`
# on every `nix eval` call: Nix happily substitutes the URL on the fly.
# We extract the bot token once, verify reachability, then export the
# assembled `--override-input ...` flag string as CI_FLAKE_OVERRIDE_ARGS
# for ci-flake-check.sh to splice in.

set -eu

log() { printf '[prepare] %s\n' "$1"; }

# 1) flake experimental features.
echo 'experimental-features = nix-command flakes' >> /etc/nix/nix.conf
log "nix flakes enabled"

# 2) Extract the Gitea bot token from the composed secret.
log "git auth: resolving bot token from gitea_api_tokens"
test -n "${GITEA_API_TOKENS:-}" || { log "FATAL gitea_api_tokens secret missing"; exit 1; }
TOKEN=$(printf '%s' "$GITEA_API_TOKENS" | grep -o '"gitea_bot_ai": *"[^\"]*"' | cut -d'"' -f4)
test -n "$TOKEN" || { log "FATAL gitea_bot_ai entry not found in gitea_api_tokens"; exit 1; }

# 3) Build --override-input flags for each private flake input.
#    Format: name|NixOS/repo-name. The real input `name` must match the
#    corresponding `inputs.<name>` in flake.nix.
#
#    We use a here-string (not a pipe) for the loop so that
#    `set -eu` failures inside the loop propagate to the parent
#    shell — `... | while read ...; do ...; done` runs the loop in
#    a subshell where `exit 1` only kills the subshell.
: > /tmp/ci-override-args
while IFS='|' read -r input_name repo; do
    [ -z "$input_name" ] && continue
    url="https://oauth2:${TOKEN}@git.j0lab.xyz/${repo}.git"
    if git ls-remote "$url" HEAD > /dev/null 2>&1; then
        log "git auth: private flake input reachable (${repo} HEAD ok)"
    else
        log "FATAL cannot fetch ${repo} via HTTPS (token invalid?)"
        exit 1
    fi
    printf -- '--override-input %s=%s\n' "$input_name" "$url" \
        >> /tmp/ci-override-args
done <<PRIVATE_INPUTS
j0nix-identity-secrets|NixOS/j0nix-identity-secrets
resolve-patch|NixOS/davinci-resolve-studio-patch
PRIVATE_INPUTS

# Single space-separated line, no trailing newline.
export CI_FLAKE_OVERRIDE_ARGS="$(tr '\n' ' ' < /tmp/ci-override-args | sed 's/ $//')"
log "git auth: override args prepared (token hidden)"