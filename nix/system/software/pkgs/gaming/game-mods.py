#!/usr/bin/env python3
"""Resolve Steam games and dispatch safe, backend-specific mod deployments."""

import argparse
import json
import os
import re
import subprocess
import sys
from pathlib import Path


CONFIG = Path(os.environ.get("XDG_CONFIG_HOME", Path.home() / ".config")) / "j0nix/game-mods.json"


def fail(message: str) -> None:
    print(f"Error: {message}", file=sys.stderr)
    raise SystemExit(1)


def load_config() -> dict:
    if not CONFIG.exists():
        fail(f"configuration does not exist: {CONFIG}; rebuild the system first")
    try:
        return json.loads(CONFIG.read_text())
    except json.JSONDecodeError as error:
        fail(f"invalid configuration at {CONFIG}: {error}")


def targets(config: dict) -> dict:
    if not config.get("enable", False):
        fail("game mod management is disabled")
    result = config.get("targets", {})
    if not isinstance(result, dict) or not result:
        fail("no game-mod targets are configured")
    return result


def steam_roots() -> list[Path]:
    candidates = [
        Path.home() / ".local/share/Steam",
        Path.home() / ".steam/steam",
        Path.home() / ".steam/root",
    ]
    return list(dict.fromkeys(path for path in candidates if path.is_dir()))


def library_roots() -> list[Path]:
    roots = []
    for root in steam_roots():
        roots.append(root)
        library_file = root / "steamapps/libraryfolders.vdf"
        if library_file.exists():
            text = library_file.read_text(errors="replace")
            roots.extend(Path(path) for path in re.findall(r'"path"\s+"([^"]+)"', text))
    return list(dict.fromkeys(path for path in roots if path.is_dir()))


def resolve_game(target: dict) -> Path:
    explicit = target.get("gameDir")
    if explicit:
        game_dir = Path(explicit).expanduser()
        if not game_dir.is_dir():
            fail(f"configured game directory does not exist: {game_dir}")
        return game_dir.resolve()

    app_id = target.get("steamAppId")
    if not isinstance(app_id, int):
        fail("target requires an integer steamAppId or an explicit gameDir")
    for root in library_roots():
        manifest = root / f"steamapps/appmanifest_{app_id}.acf"
        if not manifest.exists():
            continue
        text = manifest.read_text(errors="replace")
        match = re.search(r'"installdir"\s+"([^"]+)"', text)
        if match:
            game_dir = root / "steamapps/common" / match.group(1)
            if game_dir.is_dir():
                return game_dir.resolve()
    fail(f"Steam game {app_id} is not installed or its library is not readable")


def run_backend(target_name: str, target: dict, action: str) -> None:
    backend = target.get("backend")
    if backend != "nms-pak":
        fail(f"unsupported backend for {target_name}: {backend!r} (supported: nms-pak)")
    game_dir = resolve_game(target)
    mods_dir_value = target.get("modsDir")
    if not isinstance(mods_dir_value, str) or not mods_dir_value:
        fail(f"target {target_name} requires modsDir")
    mods_dir = Path(mods_dir_value).expanduser()
    command = ["nms-patcher", action]
    if action in ("deploy", "status"):
        if action == "deploy":
            command += ["--mods-dir", str(mods_dir), "--game-dir", str(game_dir)]
        else:
            command += []
    elif action == "undeploy":
        command += ["--game-dir", str(game_dir)]
    print(f"{target_name}: {game_dir}")
    if action == "deploy":
        print(f"Staging mods: {mods_dir}")
    subprocess.run(command, check=True)


def main() -> None:
    parser = argparse.ArgumentParser(description="Manage configured Steam game mods")
    commands = parser.add_subparsers(dest="command", required=True)
    commands.add_parser("list", help="list configured targets")
    target_parser = commands.add_parser("install", help="deploy staged mods")
    target_parser.add_argument("target")
    target_parser = commands.add_parser("remove", help="remove managed mods")
    target_parser.add_argument("target")
    target_parser = commands.add_parser("status", help="show deployment status")
    target_parser.add_argument("target")
    args = parser.parse_args()
    configured = targets(load_config())

    if args.command == "list":
        for name, target in configured.items():
            print(f"{name}: Steam {target.get('steamAppId', 'custom')} ({target.get('backend', 'unset')})")
        return
    if args.target not in configured:
        fail(f"unknown target {args.target!r}; use `game-mods list`")
    action = {"install": "deploy", "remove": "undeploy", "status": "status"}[args.command]
    run_backend(args.target, configured[args.target], action)


if __name__ == "__main__":
    main()
