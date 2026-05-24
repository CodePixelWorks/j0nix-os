#!/usr/bin/env bash
# drone-publish-step.sh — called by Drone CI public-mirror pipeline.
# Simple wrapper around the full/incremental mode dispatch.
set -euo pipefail

echo "Mirror mode: ${PUBLIC_MIRROR_MODE:-full}"
echo "Identity mode: ${PUBLIC_GITHUB_IDENTITY_MODE:-selective}"
env | grep '^PUBLIC' | cut -d= -f1 | sort

case "${PUBLIC_MIRROR_MODE:-full}" in
  incremental)
    scripts/mirror-sync-forward.sh "$PUBLIC_GITHUB_REMOTE" "$PUBLIC_GITHUB_BRANCH"
    ;;
  *)
    scripts/publish-public-github.sh "$PUBLIC_GITHUB_REMOTE" "$PUBLIC_GITHUB_BRANCH"
    ;;
esac
