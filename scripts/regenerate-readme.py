#!/usr/bin/env python3
"""
Regenerate README.md from templates/README.md.tmpl

Uses Python stdlib string.Template — no external dependencies.

Usage:
    python scripts/regenerate-readme.py --scope private
    python scripts/regenerate-readme.py --scope public
    python scripts/regenerate-readme.py --scope private --check   # CI mode
"""
import argparse
import sys
from pathlib import Path
from string import Template


SCOPE_CONFIGS = {
    "private": {
        "source_notice": """> [!NOTE]
> This repository is the **private source**. A public mirror is maintained separately with secrets and host keys stripped out.""",
        "clone_command": "git clone git@github.com:j0nix/j0nix-os.git ~/j0nix-os",
        "public_mirror_section": """A secrets-stripped version of this repository is maintained for public reference.

```bash
# Export to a clean directory
./scripts/export-public-github.sh /tmp/j0nix-public
cd /tmp/j0nix-public

# Validate the export
nix flake check --no-build

# Publish (if you have push access)
./scripts/publish-public-github.sh
```

The export script:
- Removes `settings.nix`, `.sops.yaml`, host/user secret files
- Replaces `settings.nix` with `settings.nix.example`
- Replaces `details.nix` and `hardware-configuration.nix` with their `.example` templates
- Keeps all system modules, user modules, docs, and scripts""",
    },
    "public": {
        "source_notice": """> [!IMPORTANT]
> This is the **public mirror** of j0nix-os. Secrets and machine-specific data have been stripped for public reference.
>
> The private source is maintained separately and synced continuously.""",
        "clone_command": "git clone https://github.com/j0nix/j0nix-os.git ~/j0nix-os",
        "public_mirror_section": """This is the **public mirror** of j0nix-os. Secrets and machine-specific data have been stripped for public reference.

The private source is maintained separately and synced continuously. Contributions are welcome — open an issue or PR.

While the full setup instructions below are shown for context, the secret-dependent files (`settings.nix`, `.sops.yaml`, host/user secrets) are not present in the mirror. Use `settings.nix.example` as your starting point.""",
    },
}


def render(scope: str) -> str:
    """Render README for the given scope."""
    template_path = Path("templates/README.md.tmpl")
    if not template_path.exists():
        print("ERROR: templates/README.md.tmpl not found", file=sys.stderr)
        sys.exit(1)

    config = SCOPE_CONFIGS.get(scope)
    if not config:
        print(f"ERROR: Unknown scope '{scope}'", file=sys.stderr)
        sys.exit(1)

    template = Template(template_path.read_text(encoding="utf-8"))
    return template.substitute(**config)


def main():
    parser = argparse.ArgumentParser(description="Regenerate README.md from template")
    parser.add_argument(
        "--scope",
        choices=["private", "public"],
        required=True,
        help="Which variant to generate: private source or public mirror"
    )
    parser.add_argument(
        "--output",
        default="README.md",
        help="Output filename (default: README.md)"
    )
    parser.add_argument(
        "--check",
        action="store_true",
        help="Exit with error if the output would change (for CI)"
    )
    args = parser.parse_args()

    rendered = render(args.scope)
    output_path = Path(args.output)

    if args.check:
        if not output_path.exists():
            print("ERROR: README.md does not exist", file=sys.stderr)
            sys.exit(1)
        existing = output_path.read_text(encoding="utf-8")
        if existing != rendered:
            print("ERROR: README.md is out of date. Run regenerate-readme.py", file=sys.stderr)
            sys.exit(1)
        print("OK: README.md is up to date")
        return

    output_path.write_text(rendered, encoding="utf-8")
    print(f"Generated {args.output} (scope: {args.scope})")


if __name__ == "__main__":
    main()
