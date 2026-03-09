#!/usr/bin/env bash
set -euo pipefail

usage() {
  cat <<'USAGE'
Usage: scripts/find-working-hyprland-variant.sh [options]

Interactive helper to locate the last known-good Hyprland/Caelestia config
from recent commits. It checks out candidate commits in temporary worktrees,
applies them via `nixos-rebuild test` (or switch), and asks for a manual
"works / broken" decision.

Options:
  --host <name>        NixOS host in the flake (default: Jonas-PC)
  --since <range>      git --since range (default: 14 days ago)
  --max <n>            max commits to test (default: 20)
  --mode <test|switch> rebuild mode per candidate (default: test)
  --restore <mode>     restore mode at end (default: switch)
  -h, --help           show this help

Environment alternatives:
  HOST, SINCE, MAX_COMMITS, MODE, RESTORE_MODE
USAGE
}

HOST="${HOST:-Jonas-PC}"
SINCE="${SINCE:-14 days ago}"
MAX_COMMITS="${MAX_COMMITS:-20}"
MODE="${MODE:-test}"
RESTORE_MODE="${RESTORE_MODE:-switch}"

while [ "$#" -gt 0 ]; do
  case "$1" in
    --host)
      HOST="$2"
      shift 2
      ;;
    --since)
      SINCE="$2"
      shift 2
      ;;
    --max)
      MAX_COMMITS="$2"
      shift 2
      ;;
    --mode)
      MODE="$2"
      shift 2
      ;;
    --restore)
      RESTORE_MODE="$2"
      shift 2
      ;;
    -h|--help)
      usage
      exit 0
      ;;
    *)
      echo "Unknown argument: $1" >&2
      usage >&2
      exit 2
      ;;
  esac
done

if [ "$MODE" != "test" ] && [ "$MODE" != "switch" ]; then
  echo "--mode must be test or switch" >&2
  exit 2
fi

if [ "$RESTORE_MODE" != "test" ] && [ "$RESTORE_MODE" != "switch" ]; then
  echo "--restore must be test or switch" >&2
  exit 2
fi

ROOT="$(git rev-parse --show-toplevel)"
ORIG_HEAD="$(git -C "$ROOT" rev-parse HEAD)"

TARGET_PATHS=(
  settings.nix
  system/wm/hyprland.nix
  user/wm/hyprland/default.nix
  user/wm/shell-launcher.nix
  user/wm/hyprland/shells/caelestia-shell/default.nix
)

mapfile -t COMMITS < <(
  git -C "$ROOT" log \
    --since "$SINCE" \
    --format='%H' \
    -- "${TARGET_PATHS[@]}" \
    | awk '!seen[$0]++' \
    | head -n "$MAX_COMMITS"
)

if [ "${#COMMITS[@]}" -eq 0 ]; then
  echo "No candidate commits found for SINCE='$SINCE'." >&2
  exit 1
fi

echo "Host: $HOST"
echo "Since: $SINCE"
echo "Candidates: ${#COMMITS[@]}"
echo "Apply mode: $MODE"
echo

auto_restore() {
  echo
  echo "Restoring current HEAD ($ORIG_HEAD) with nixos-rebuild $RESTORE_MODE ..."
  sudo nixos-rebuild "$RESTORE_MODE" --flake "$ROOT#$HOST"
}

cleanup_worktree() {
  if [ -n "${WT_DIR:-}" ] && [ -d "${WT_DIR:-}" ]; then
    git -C "$ROOT" worktree remove --force "$WT_DIR" >/dev/null 2>&1 || true
  fi
  WT_DIR=""
}

trap 'cleanup_worktree' EXIT

FOUND_COMMIT=""
for COMMIT in "${COMMITS[@]}"; do
  SHORT="$(git -C "$ROOT" rev-parse --short "$COMMIT")"
  SUBJECT="$(git -C "$ROOT" log -1 --format='%cs %s' "$COMMIT")"

  WT_DIR="$(mktemp -d /tmp/j0nix-hypr-variant-XXXXXX)"
  git -C "$ROOT" worktree add --detach "$WT_DIR" "$COMMIT" >/dev/null

  echo "============================================================"
  echo "Testing commit $SHORT"
  echo "$SUBJECT"
  echo "worktree: $WT_DIR"

  if sudo nixos-rebuild "$MODE" --flake "$WT_DIR#$HOST"; then
    echo
    echo "Test now in the live session, then choose:"
    echo "  y = works"
    echo "  n = broken"
    echo "  s = skip / unsure"
    echo "  q = quit"
    read -r -p "Result for $SHORT [y/n/s/q]: " ANSWER
  else
    echo "Build/apply failed for $SHORT -> treated as broken"
    ANSWER="n"
  fi

  cleanup_worktree

  case "$ANSWER" in
    y|Y)
      FOUND_COMMIT="$COMMIT"
      break
      ;;
    n|N|s|S)
      continue
      ;;
    q|Q)
      break
      ;;
    *)
      echo "Unknown answer '$ANSWER', continuing..."
      ;;
  esac

done

auto_restore

if [ -n "$FOUND_COMMIT" ]; then
  echo
  echo "Found working commit: $FOUND_COMMIT"
  git -C "$ROOT" log -1 --oneline "$FOUND_COMMIT"
  exit 0
fi

echo

echo "No working commit confirmed in tested candidate set."
exit 1
