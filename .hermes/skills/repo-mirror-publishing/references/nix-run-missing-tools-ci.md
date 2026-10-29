# Nix Shell for Missing POSIX Tools in CI Containers

When a Drone CI container (e.g. `nixos/nix:2.26.1`) ships without common POSIX
utilities like `sed`, `awk`, `grep`, or `find`, prefer `nix shell nixpkgs#<pkg> --command <tool>`
over `nix run` or Python workarounds.

## Why `nix shell` over `nix run`

`nix run` forwards arguments through the Nix CLI parser, which destroys quote
characters in sed expressions and mangles characters like `|`. `nix shell --command`
preserves quoting correctly because the tool is invoked directly from the shell.

**Example — `nix run` breaks sed expressions:**
```
$ nix run nixpkgs#gnused -- sed -i 's#foo#bar#g' test.txt
/nix/store/...-gnused/bin/sed: -e expression #1, char 3: unterminated `s' command
```

**Same command with `nix shell`:**
```
$ nix shell nixpkgs#gnused --command sed -i 's#foo#bar#g' test.txt
# succeeds
```

```bash
# WRONG — fails when run_sed resolves to nix run
run_sed -i "s|old|new|g" "$file"

# CORRECT — '#' is safe in all contexts
run_sed -i "s#old#new#g" "$file"
```

## `run_sed` helper

```bash
# Run sed, pulling it from nixpkgs if the host doesn't have it.
run_sed() {
    if command -v sed >/dev/null 2>&1; then
        command sed "$@"
    elif command -v nix >/dev/null 2>&1; then
        nix --extra-experimental-features 'nix-command flakes' run nixpkgs#gnused -- sed "$@"
    else
        printf '%s\n' "ERROR: sed not found and nix not available" >&2
        exit 1
    fi
}
```

## Common missing tools and their nixpkgs names

| Tool | nixpkgs attr | Notes |
|---|---|---|
| `sed` | `gnused` | GNU sed — `sed -i` support |
| `awk` | `gawk` | GNU awk |
| `grep` | `gnugrep` | GNU grep |
| `find` | `findutils` | GNU find + xargs |
| `xargs` | `findutils` | Bundled with findutils |
| `tar` | `gnutar` | GNU tar |
| `make` | `gnumake` | GNU make |

## When NOT to use `nix run`

- **Offline/air-gapped runners** — if the container cannot reach cache.nixos.org,
  `nix run` will hang or fail. In that case, use pure bash builtins or bake
  the tools into the container image.
- **Non-Nix containers** — obviously only works when `nix` is present.

## Integration with git-filter-branch

The missing-tool problem affects **two layers**:

1. **Parent shell (CI step):** Where `publish-public-github.sh` generates temp
   filter scripts. Use `run_sed` here.
2. **Filter subshells:** Where `git-filter-branch` executes the filters.
   These are *even more minimal* and may not have `nix` either. For these,
   generate **standalone bash scripts** using only POSIX builtins
   (see `repo-mirror-publishing` skill §4.8).
