#!/usr/bin/env bash
set -euo pipefail

# CI helper: run flake check with required experimental features enabled.
# Usage: scripts/ci-check.sh
#
# Uses --extra-experimental-features rather than NIX_CONFIG because the
# nixos/nix container image and some CI environments ignore the env var.

nix --extra-experimental-features 'nix-command flakes' flake check --no-build
