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
# Private flake inputs are fetched with --override-input (see
# ci-prepare.sh). CI_FLAKE_OVERRIDE_ARGS contains the assembled flag
# string with the bot token in the URL — we splice it into every nix
# eval call via a wrapper function.

set -eu

# Disable shellcheck array warning for the eval call below.
# shellcheck disable=SC2086
eval_set() {
    nix eval --raw "$@" \
        --apply 'attrs: builtins.concatStringsSep "\n" (builtins.attrNames attrs)'
}

echo ">>> evaluating nixosConfigurations (one at a time for bounded memory)"
HOSTS=$(eval_set ".#nixosConfigurations" $CI_FLAKE_OVERRIDE_ARGS)
for host in $HOSTS; do
    echo "  checking nixosConfigurations.$host"
    # shellcheck disable=SC2086
    nix eval ".#nixosConfigurations.$host.config.system.build.toplevel.drvPath" \
        $CI_FLAKE_OVERRIDE_ARGS > /dev/null
done

echo ">>> evaluating homeConfigurations (one at a time for bounded memory)"
HOMES=$(eval_set ".#homeConfigurations" $CI_FLAKE_OVERRIDE_ARGS)
for home in $HOMES; do
    echo "  checking homeConfigurations.$home"
    # shellcheck disable=SC2086
    nix eval ".#homeConfigurations.$home.activationPackage.drvPath" \
        $CI_FLAKE_OVERRIDE_ARGS > /dev/null
done

echo ">>> all host and home configurations evaluated"