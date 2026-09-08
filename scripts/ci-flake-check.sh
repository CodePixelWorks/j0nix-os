#!/bin/sh
# Static CI evaluation of the flake — the Drone gate (nix-flake-check step).
#
# j0nix-os exposes nixosConfigurations + homeConfigurations (no checks
# output). We evaluate each nixosConfiguration's toplevel derivation and
# each homeConfiguration's activation package, one at a time for bounded
# memory (a monolithic `nix flake check` holds every output in one
# evaluator process and gets OOM-killed on modest CI runners — same
# lesson as nixos-server-base build #3).
#
# Signal is identical to `nix flake check` for the outputs that matter:
# - forcing a host's `system.build.toplevel.drvPath` evaluates the full
#   NixOS configuration, so option errors, assertion failures, and
#   systemd cycle problems fail the gate
# - forcing a homeConfiguration's `activationPackage.drvPath` evaluates
#   the full Home Manager user configuration
#
# Private flake inputs (ssh://git@git.j0lab.xyz/...) are fetched via the
# insteadOf rewrite installed by ci-prepare.sh into ~/.gitconfig. Nix
# spawns git subprocesses for git-type flake fetches, which transparently
# pick up the rewrite — no SSH keys needed in the CI container.

set -eu

echo ">>> evaluating nixosConfigurations (one at a time for bounded memory)"
HOSTS=$(nix eval --raw ".#nixosConfigurations" \
    --apply 'attrs: builtins.concatStringsSep "\n" (builtins.attrNames attrs)')
for host in $HOSTS; do
    echo "  checking nixosConfigurations.$host"
    nix eval ".#nixosConfigurations.$host.config.system.build.toplevel.drvPath" > /dev/null
done

echo ">>> evaluating homeConfigurations (one at a time for bounded memory)"
HOMES=$(nix eval --raw ".#homeConfigurations" \
    --apply 'attrs: builtins.concatStringsSep "\n" (builtins.attrNames attrs)')
for home in $HOMES; do
    echo "  checking homeConfigurations.$home"
    nix eval ".#homeConfigurations.$home.activationPackage.drvPath" > /dev/null
done

echo ">>> all host and home configurations evaluated"