#!/usr/bin/env bash
# scripts/sops-migrate-between-repos.sh — One-shot SOPS secret migration.
#
# Pulls a subset of keys from a legacy SOPS file and re-encrypts them
# under a destination repo's recipient set. The destination repo's
# `.sops.yaml` is the source of truth for recipients (this script just
# mirrors them at invocation time).
#
# Safety contract:
#   - Operates only inside a `chmod 700` temp directory created by
#     `mktemp -d`.
#   - Plaintext material lives ONLY in `chmod 600` temp files inside
#     that directory.
#   - No `cat`, `echo`, `tee`, or `printf` of plaintext to
#     stdout/stderr at any point.
#   - Temp directory is `shred -u`ed + `rm -rf`'d on EXIT, INT, TERM.
#   - Exit code is non-zero on any failure (set -euo pipefail).
#
# Required inputs (env vars):
#   LEGACY_FILE         absolute path to the source .yaml (encrypted)
#   LEGACY_SOPS_CONFIG  absolute path to the source .sops.yaml
#   DEST_REPO           absolute path to the destination repo root
#   DEST_SOPS_CONFIG    absolute path to the destination .sops.yaml
#   SSH_KEY             absolute path to a working age key file
#
# Required CLI arg:
#   PROJECTION          yq/jq expression that projects the desired
#                       subtree(s) out of the legacy file. Example:
#                         '{"ssh": .ssh, "ssh_passphrases": ."ssh_passphrases"}'
#                       The result must be a single YAML document.
#
# Required CLI arg:
#   OUTPUT_NAME         filename to write into $DEST_REPO/secrets/
#                       (used as the --filename-override for the regex)
#
# Usage:
#   LEGACY_FILE=... LEGACY_SOPS_CONFIG=... DEST_REPO=... \
#   DEST_SOPS_CONFIG=... SSH_KEY=... \
#   ./scripts/sops-migrate-between-repos.sh \
#       '{"ssh": .ssh, "ssh_passphrases": ."ssh_passphrases"}' \
#       ssh.yaml
#
# This script is meant to be deleted after the migration is committed.
# If you find yourself running it twice, something went wrong.

set -euo pipefail

# --- input validation -------------------------------------------------------
: "${LEGACY_FILE:?LEGACY_FILE is required}"
: "${LEGACY_SOPS_CONFIG:?LEGACY_SOPS_CONFIG is required}"
: "${DEST_REPO:?DEST_REPO is required}"
: "${DEST_SOPS_CONFIG:?DEST_SOPS_CONFIG is required}"
: "${SSH_KEY:?SSH_KEY is required (must be chmod 600)}"

PROJECTION="${1:?usage: $0 PROJECTION OUTPUT_NAME}"
OUTPUT_NAME="${2:?usage: $0 PROJECTION OUTPUT_NAME}"

[ -f "$LEGACY_FILE" ]      || { echo "ERR: legacy file not found: $LEGACY_FILE" >&2; exit 1; }
[ -f "$LEGACY_SOPS_CONFIG" ] || { echo "ERR: legacy sops config not found" >&2; exit 1; }
[ -f "$DEST_SOPS_CONFIG" ]   || { echo "ERR: dest sops config not found" >&2; exit 1; }
[ -f "$SSH_KEY" ]          || { echo "ERR: age key not found: $SSH_KEY" >&2; exit 1; }

# --- temp workspace ---------------------------------------------------------
WORK="$(mktemp -d -t sops-mig.XXXXXX)"
chmod 700 "$WORK"

LEGACY_PLAIN="${WORK}/legacy.yaml"
PROJECTED="${WORK}/projected.yaml"
touch "$LEGACY_PLAIN" "$PROJECTED"
# chmod AFTER touch — chmod on a non-existent file fails with exit 1
# under set -e and aborts the script before the files exist.
chmod 600 "$LEGACY_PLAIN" "$PROJECTED"

cleanup() {
    # shred if available (more thorough on most filesystems), else plain delete.
    if command -v shred >/dev/null 2>&1; then
        find "$WORK" -type f -exec shred -u {} + 2>/dev/null || true
    else
        find "$WORK" -type f -delete 2>/dev/null || true
    fi
    chmod -R u+w "$WORK" 2>/dev/null || true
    rm -rf "$WORK"
}
trap cleanup EXIT INT TERM

# --- step 1: decrypt legacy file into chmod 600 temp ------------------------
# Redirect to file (never stdout/stderr) so plaintext never traverses
# a pipe that humans can intercept.
SOPS_AGE_KEY_FILE="$SSH_KEY" sops \
    --config "$LEGACY_SOPS_CONFIG" \
    --input-type yaml --output-type yaml \
    --decrypt "$LEGACY_FILE" > "$LEGACY_PLAIN"

# --- step 2: project the desired subtree into another temp file ------------
# yq reads from $LEGACY_PLAIN, writes to $PROJECTED. Plaintext never
# leaves the temp directory.
yq -y "$PROJECTION" "$LEGACY_PLAIN" > "$PROJECTED"

# --- step 3: encrypt under destination recipient set ------------------------
# --filename-override makes sops use the destination path for
# path_regex matching in DEST_SOPS_CONFIG, even though the plaintext
# lives under $WORK (which would not match any rule).
sops --config "$DEST_SOPS_CONFIG" \
    --filename-override "secrets/${OUTPUT_NAME}" \
    --input-type yaml --output-type yaml \
    --encrypt "$PROJECTED" > "${DEST_REPO}/secrets/${OUTPUT_NAME}"

# --- step 4: verify decryptability without showing contents ----------------
# `sops -d >/dev/null` exits 0 on success, non-zero on any error
# (missing recipient, corrupted ciphertext, MAC mismatch, …).
if ! SOPS_AGE_KEY_FILE="$SSH_KEY" sops --config "$DEST_SOPS_CONFIG" \
        --decrypt "${DEST_REPO}/secrets/${OUTPUT_NAME}" >/dev/null 2>&1; then
    echo "ERR: ${OUTPUT_NAME} did not decrypt cleanly" >&2
    exit 1
fi

echo "OK: secrets/${OUTPUT_NAME} migrated and verified decryptable."
