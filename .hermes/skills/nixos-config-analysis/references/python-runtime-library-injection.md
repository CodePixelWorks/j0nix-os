# Nix Python Runtime Library Injection via makeWrapper

## When to Use

- A Nix derivation runs an embedded Python interpreter (e.g. a CLI tool that
  exposes `HERMES_PYTHON`), and the tool crashes because a Python module is
  missing at runtime.
- The missing module is **not** part of the upstream derivation's closure
  (e.g. `firecrawl-py` for a custom web extraction backend).
- You **cannot** modify the upstream flake (e.g. `hermes-agent` is an external
  input you do not control).
- The app is evaluated in a read-only Nix environment where `pip install` is
  impossible or forbidden (PEP 668, Nix store read-only).

## Symptom

```python
ModuleNotFoundError: No module named 'firecrawl'
```

or internally the tool falls back to a worse backend (e.g. browser-based
extraction instead of a direct API client) because it catches the import
error silently.

## Root Cause

Nix Python derivations only see packages explicitly listed in the derivation's
`propagatedBuildInputs` or `pythonPath`. An external flake input was built
without awareness of your local extra dependency.

## Solution: Wrap the Binary with --prefix PYTHONPATH

Create a **shim derivation** that re-exports the upstream binaries with an
augmented `PYTHONPATH`.

### Step 1: Build the missing Python package

If the package is not in nixpkgs, build it from PyPI (see
`pypi-package-to-nix.md`).

Assume you already have `firecrawl-py` as a derivation:

```nix
firecrawl-py = final.python312Packages.callPackage (baseDir + "/nix/pkgs/firecrawl-py") { };
```

### Step 2: Create the wrapper derivation

```nix
# nix/pkgs/hermes-agent-ext/default.nix
{ stdenv
, makeWrapper
, hermesPackage          # the raw upstream derivation
, firecrawlPy            # the extra Python package derivation
}:

stdenv.mkDerivation {
  pname = "hermes-agent-firecrawl";
  inherit (hermesPackage) version;

  nativeBuildInputs = [ makeWrapper ];

  buildCommand = ''
    mkdir -p $out/bin $out/share $out/ui-tui

    # Preserve bundled assets from upstream
    cp -r ${hermesPackage}/share/*       $out/share/    2>/dev/null || true
    cp -r ${hermesPackage}/ui-tui/*      $out/ui-tui/   2>/dev/null || true

    firecrawlSitePackages="${firecrawlPy}/lib/python3.12/site-packages"

    for bin in hermes hermes-agent hermes-acp; do
      if [[ -e ${hermesPackage}/bin/$bin ]]; then
        makeWrapper ${hermesPackage}/bin/$bin $out/bin/$bin \
            --prefix PYTHONPATH : "$firecrawlSitePackages"
      fi
    done
  '';
}
```

Key details:
- `--prefix PYTHONPATH : ...` **prepends** the extra path so it takes priority
- `makeWrapper` handles idempotency correctly (won't duplicate paths)
- Preserve **all** assets the upstream derivation exports (`share/`, `ui-tui/`,
  bundled skills/plugins, etc.) — the wrapper becomes the canonical package

### Step 3: Register in overlay and consume

```nix
# overlays.nix
hermes-agent-with-firecrawl =
  let
    system = final.stdenv.hostPlatform.system;
    hermesPkg =
      if (inputs ? hermes-agent)
         && (inputs.hermes-agent.packages.${system} or null) != null
      then inputs.hermes-agent.packages.${system}.default
      else null;
  in
  if hermesPkg != null then
    final.callPackage (baseDir + "/nix/pkgs/hermes-agent-ext") {
      hermesPackage = hermesPkg;
      firecrawlPy = final.firecrawl-py;
    }
  else null;
```

Then consume the wrapped package everywhere you previously used the raw one:

```nix
hermesPackage = pkgs.hermes-agent-with-firecrawl or null;
```

Both user-scope installs (`nix/user/dev/ai-cli.nix`) and system-scope installs
(`nix/system/dev/default.nix`) should point to the overlay package, not the raw
flake input.

## Pitfalls

1. **Do NOT use `--set PYTHONPATH`** — this **replaces** the entire PYTHONPATH
   and breaks every other module the upstream binary depends on.
   Always use `--prefix PYTHONPATH :`.

2. **Python version mismatch**: The extra package must be built for the same
   Python major.minor as the upstream interpreter. Hermes Agent currently uses
   Python 3.12, so build `firecrawl-py` with `python312Packages.callPackage`.
   If you build with 3.13, the module won't be importable at runtime.

3. **Missing transitive deps**: `buildPythonPackage` checks runtime deps.
   If the PyPI package declares `aiohttp`, `websockets`, etc., add them to
   `propagatedBuildInputs`. The Nix build will fail with `X not installed`
   if you forget.

4. **Updatability**: When the upstream Hermes flake updates, your wrapper
   automatically rebuilds because the `hermesPackage` input changed. No manual
   intervention needed.

5. **Verification after switch**:
   ```bash
   # Confirm shebang shows PYTHONPATH prefix
   head /run/current-system/sw/bin/hermes

   # Confirm firecrawl imports successfully
   $HERMES_PYTHON -c "import firecrawl; print(firecrawl.__version__)"
   ```

## Alternative (Not Recommended): PYTHONPATH via wrapper script

You could also write a shell wrapper:

```bash
# BAD — harder to compose, loses systemd units, desktop entries
export PYTHONPATH="/nix/store/...-firecrawl-py/lib/python3.12/site-packages:$PYTHONPATH"
exec /run/current-system/sw/bin/hermes "$@"
```

This works interactively but does **not** compose with systemd services,
Home Manager activation scripts, or other Nix modules that reference the
package directly. Prefer the derivation wrapper.
