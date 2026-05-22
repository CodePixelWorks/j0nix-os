#!/usr/bin/env bash
set -euo pipefail

# CI helper: run flake check with required experimental features enabled.
# Usage: scripts/ci-check.sh
# Can also be used locally when NIX_CONFIG is not already set.

export NIX_CONFIG="experimental-features = nix-command flakes"
nix flake check --no-build
