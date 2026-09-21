# Building a Python Package from PyPI in Nix

## When to Use

- A Python package is required at runtime but **not available in nixpkgs**.
- You need to bridge a Nix derivation (e.g. Hermes Agent) with a PyPI-only
  dependency not declared in the upstream flake.
- The package is installable via `pip` outside Nix, but Nix's read-only store
  and PEP 668 enforcement prevent that inside the system.

## Symptom

```python
ModuleNotFoundError: No module named 'firecrawl'
```

and `nix search nixpkgs#python3Packages.firecrawl` returns nothing.

## Solution: buildPythonPackage + fetchurl

### Step 1: Discover Available Versions

PyPI versions are not always contiguous, and `fetchPypi` uses normalized
package names with underscores. Probing directly with `nix-prefetch-url` is
faster than guessing:

```bash
# Probe a range of versions
for v in 2.16.0 2.16.5 2.20.0; do
  result=$(nix-prefetch-url \
    "https://files.pythonhosted.org/packages/source/f/firecrawl-py/firecrawl_py-${v}.tar.gz" 2>&1)
  if echo "$result" | grep -q "^path"; then
    # parse sha256 from output line 2
    sha=$(echo "$result" | sed -n '2p')
    echo "FOUND $v : $sha"
  else
    echo "MISSING $v"
  fi
done
```

Alternatively, for packages with predictable versions, use `nix-prefetch-url`
once and let Nix tell you the expected hash on 404.

### Step 2: Write the derivation

```nix
# nix/pkgs/firecrawl-py/default.nix
{ lib
, fetchurl
, buildPythonPackage
, setuptools
, requests
, pydantic
, python-dotenv
, typing-extensions
, websockets
, nest-asyncio
, aiohttp
}:

buildPythonPackage rec {
  pname = "firecrawl-py";
  version = "2.16.5";

  src = fetchurl {
    url = "https://files.pythonhosted.org/packages/source/f/firecrawl-py/firecrawl_py-${version}.tar.gz";
    sha256 = "10scr8f9p2ajg5sysgd3xpxjprh4lr8ba9v818a2d92rlfxqclbz";
  };

  # The package ships both pyproject.toml and setup.py;
  # setuptools works with pyproject = true here.
  pyproject = true;
  build-system = [ setuptools ];

  propagatedBuildInputs = [
    requests
    pydantic
    python-dotenv
    typing-extensions
    websockets
    nest-asyncio
    aiohttp
  ];

  pythonImportsCheck = [ "firecrawl" ];

  meta = with lib; {
    description = "Python SDK for Firecrawl API";
    homepage = "https://github.com/mendableai/firecrawl";
    license = licenses.agpl3Only;
  };
}
```

### Step 3: Build iteratively to find missing deps

```bash
# First attempt — fails with "BackendUnavailable" or import errors
nix-build -E 'with import <nixpkgs> {}; python312Packages.callPackage ./default.nix {}'

# Read the failure, add missing packages to propagatedBuildInputs, retry.
# Typical progression:
#   1. Missing build-system  → add setuptools / poetry-core / hatchling
#   2. Missing runtime deps  → add packages from "X not installed" errors
#   3. pythonImportsCheck    → add package name from import test
```

### Step 4: Register in overlay

```nix
# overlays.nix
firecrawl-py = final.python312Packages.callPackage (baseDir + "/nix/pkgs/firecrawl-py") { };
```

This exposes `pkgs.firecrawl-py` everywhere in the flake.

## Build-System Choices

| Upstream metadata | build-system entry |
|---|---|
| `pyproject.toml` with `[build-system] requires = ["setuptools"]` | `build-system = [ setuptools ]; pyproject = true;` |
| `pyproject.toml` with `[tool.poetry]` | `build-system = [ poetry-core ]; pyproject = true;` |
| `setup.py` only, no `pyproject.toml` | `pyproject = false; build-system = [ setuptools ];` |

If the build fails with `Cannot import 'setuptools.build_meta'`, switch
`pyproject` to `false` and ensure `setuptools` is in `build-system`.

## Hash Discovery Shortcuts

### Option A: nix-prefetch-url (recommended for exact versions)

```bash
nix-prefetch-url https://files.pythonhosted.org/packages/source/f/FOO/FOO-${version}.tar.gz
```

### Option B: lib.fakeSha256 (let Nix tell you)

```nix
sha256 = lib.fakeSha256;
```

Run the build, Nix will fail and print the correct base32 SRI hash in the
error message. Copy-paste it into the derivation.

### Option C: fetchPypi (uses normalized name)

```nix
src = fetchPypi {
  inherit pname version;
  sha256 = lib.fakeSha256;
};
```

Note: `fetchPypi` normalizes underscores to hyphens in URLs. Some packages
(mixed hyphen/underscore naming in PyPI metadata) break with this. In those
cases, use `fetchurl` with the explicit URL.

## Pitfalls

1. **Underscore vs hyphen in filename**: The PyPI source URL uses the
   **canonical** package name, which may differ from the display name on
   pypi.org. Probe with `nix-prefetch-url` to verify the URL exists.

2. **Version gaps**: Some packages skip patch versions. If `2.16.5` exists
   but `2.16.4` doesn't, don't assume linear progression. Check `2.15.x` or
   jump to `2.17.0`.

3. **propagatedBuildInputs vs build-system**: Packages needed at **runtime**
   go in `propagatedBuildInputs` (they are installed alongside your package).
   Packages only needed to **build** the wheel go in `build-system`.

4. **The `doCheck = false` escape hatch**: If tests fail due to network
   access or missing test fixtures, disable them:
   ```nix
   doCheck = false;
   # or skip specific test files
   preCheck = ''
     rm -rf firecrawl/__tests__
   '';
   ```

5. **Python version alignment**: If your target binary (Hermes Agent) runs
   Python 3.12, build the package with `python312Packages.callPackage`. A
   Python 3.13 package will be importable but may crash on ABI differences.
   Always match major.minor exactly.

## Verification

After the derivation builds:

```bash
# Confirm import works
nix-build -E 'with import <nixpkgs> {}; python312Packages.callPackage ./default.nix {}'
result=$(nix-build -E 'with import <nixpkgs> {}; python312Packages.callPackage ./default.nix {}')
"$result/bin/python" -c "import firecrawl; print(firecrawl.__version__)"
```

Or, if the package is an import-only library with no binaries:

```bash
# Inspect the site-packages directory
ls "$(nix-build -A outPath pkgs.firecrawl-py)/lib/python3.12/site-packages"
```
