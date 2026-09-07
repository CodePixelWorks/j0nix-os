#!/usr/bin/env python3
"""Deploy No Man's Sky PAK mods without modifying unowned game files."""

import argparse
import hashlib
import json
import os
import shutil
import sys
from pathlib import Path


STATE_DIR = Path(os.environ.get("XDG_STATE_HOME", Path.home() / ".local/state")) / "nms-patcher"
STATE_FILE = STATE_DIR / "deployment.json"
DISABLE_MODS = "DISABLEMODS.TXT"
DISABLED_BACKUP = ".DISABLEMODS.TXT.nms-patcher-disabled"


def fail(message: str) -> None:
    print(f"Error: {message}", file=sys.stderr)
    raise SystemExit(1)


def sha256(path: Path) -> str:
    digest = hashlib.sha256()
    with path.open("rb") as handle:
        for block in iter(lambda: handle.read(1024 * 1024), b""):
            digest.update(block)
    return digest.hexdigest()


def load_state() -> dict:
    if not STATE_FILE.exists():
        return {}
    try:
        return json.loads(STATE_FILE.read_text())
    except json.JSONDecodeError as error:
        fail(f"Invalid deployment state at {STATE_FILE}: {error}")


def save_state(state: dict) -> None:
    STATE_DIR.mkdir(parents=True, exist_ok=True)
    temporary = STATE_FILE.with_suffix(".tmp")
    temporary.write_text(json.dumps(state, indent=2, sort_keys=True) + "\n")
    temporary.replace(STATE_FILE)


def game_mod_directory(game_dir: Path) -> Path:
    game_data = game_dir / "GAMEDATA"
    if not game_data.is_dir():
        fail(f"Not a No Man's Sky game directory: {game_dir}")
    # NMS 5.5 and later loads PAKs from game-specific directories here. Keeping
    # this tool's files in their own directory makes ownership and rollback exact.
    return game_data / "MODS" / "j0nix-nms-patcher"


def collect_paks(mods_dir: Path) -> list[Path]:
    if not mods_dir.is_dir():
        fail(f"Mods directory does not exist: {mods_dir}")
    paks = sorted(path for path in mods_dir.rglob("*") if path.is_file() and path.suffix.lower() == ".pak")
    if not paks:
        fail(f"No .pak files found below {mods_dir}")
    names = [path.name.casefold() for path in paks]
    if len(names) != len(set(names)):
        fail("Multiple PAK files have the same name; resolve the collision before deployment")
    return paks


def remove_owned_files(state: dict) -> int:
    removed = 0
    for entry in state.get("files", []):
        destination = Path(entry["destination"])
        source = Path(entry["source"])
        if destination.is_symlink() and destination.resolve() == source.resolve():
            destination.unlink()
            removed += 1
        elif destination.is_file() and entry.get("method") == "copy" and sha256(destination) == entry["sha256"]:
            destination.unlink()
            removed += 1
    return removed


def deploy(args: argparse.Namespace) -> None:
    game_dir = args.game_dir.expanduser().resolve()
    mods_dir = args.mods_dir.expanduser().resolve()
    target_dir = game_mod_directory(game_dir)
    paks = collect_paks(mods_dir)
    state = load_state()

    if state and Path(state.get("game_dir", "/nonexistent")) != game_dir:
        fail("A deployment for another game directory exists; run undeploy there first")

    if args.dry_run:
        for pak in paks:
            print(f"Would deploy {pak} -> {target_dir / pak.name}")
        return

    target_dir.mkdir(parents=True, exist_ok=True)
    managed_destinations = {entry["destination"] for entry in state.get("files", [])}
    for pak in paks:
        destination = target_dir / pak.name
        if (destination.exists() or destination.is_symlink()) and str(destination) not in managed_destinations:
            fail(f"Refusing to overwrite unowned mod file: {destination}")

    if state:
        remove_owned_files(state)

    bank_dir = game_dir / "GAMEDATA" / "PCBANKS"
    disable_marker = bank_dir / DISABLE_MODS
    backup_marker = bank_dir / DISABLED_BACKUP
    marker_was_disabled = False
    if disable_marker.exists():
        if backup_marker.exists():
            fail(f"Refusing to overwrite existing backup marker: {backup_marker}")
        disable_marker.rename(backup_marker)
        marker_was_disabled = True

    deployed = []
    for pak in paks:
        destination = target_dir / pak.name
        if args.copy:
            shutil.copy2(pak, destination)
            method = "copy"
        else:
            destination.symlink_to(pak)
            method = "symlink"
        deployed.append({
            "source": str(pak),
            "destination": str(destination),
            "sha256": sha256(pak),
            "method": method,
        })

    save_state({
        "game_dir": str(game_dir),
        "mods_dir": str(mods_dir),
        "files": deployed,
        "disabled_marker_moved": marker_was_disabled,
    })
    print(f"Deployed {len(deployed)} PAK file(s) to {target_dir}")


def undeploy(args: argparse.Namespace) -> None:
    state = load_state()
    if not state:
        print("No NMS patcher deployment is recorded.")
        return
    game_dir = Path(state["game_dir"])
    if args.game_dir and args.game_dir.expanduser().resolve() != game_dir:
        fail("The requested game directory does not match the recorded deployment")
    removed = remove_owned_files(state)
    bank_dir = game_dir / "GAMEDATA" / "PCBANKS"
    backup_marker = bank_dir / DISABLED_BACKUP
    disable_marker = bank_dir / DISABLE_MODS
    if state.get("disabled_marker_moved") and backup_marker.exists():
        if disable_marker.exists():
            fail(f"Refusing to overwrite unowned mod marker: {disable_marker}")
        backup_marker.rename(disable_marker)
    STATE_FILE.unlink(missing_ok=True)
    print(f"Removed {removed} managed PAK file(s).")


def status(_: argparse.Namespace) -> None:
    state = load_state()
    if not state:
        print("No NMS patcher deployment is recorded.")
        return
    print(f"Game directory: {state['game_dir']}")
    print(f"Staging directory: {state['mods_dir']}")
    print(f"Managed PAK files: {len(state.get('files', []))}")
    for entry in state.get("files", []):
        destination = Path(entry["destination"])
        status_text = "present" if destination.exists() or destination.is_symlink() else "missing"
        print(f"  {status_text:7} {destination.name}")


def main() -> None:
    parser = argparse.ArgumentParser(description="Deploy No Man's Sky PAK mods safely")
    commands = parser.add_subparsers(dest="command", required=True)

    deploy_parser = commands.add_parser("deploy", help="Deploy PAKs from a staging directory")
    deploy_parser.add_argument("--mods-dir", type=Path, required=True, help="Directory containing built .pak files")
    deploy_parser.add_argument("--game-dir", type=Path, required=True, help="No Man's Sky installation directory")
    deploy_parser.add_argument("--copy", action="store_true", help="Copy PAKs instead of symlinking them")
    deploy_parser.add_argument("--dry-run", action="store_true", help="Show the deployment plan without changing files")
    deploy_parser.set_defaults(func=deploy)

    undeploy_parser = commands.add_parser("undeploy", help="Remove only PAKs managed by this tool")
    undeploy_parser.add_argument("--game-dir", type=Path, help="Verify the recorded game directory before removal")
    undeploy_parser.set_defaults(func=undeploy)

    status_parser = commands.add_parser("status", help="Show the recorded deployment")
    status_parser.set_defaults(func=status)

    nexus_parser = commands.add_parser("nexus", help="Pass a command through to nexus-dl")
    nexus_parser.add_argument("arguments", nargs=argparse.REMAINDER)
    nexus_parser.set_defaults(func=lambda args: os.execvp("nexus-dl", ["nexus-dl", *args.arguments]))

    args = parser.parse_args()
    args.func(args)


if __name__ == "__main__":
    main()
