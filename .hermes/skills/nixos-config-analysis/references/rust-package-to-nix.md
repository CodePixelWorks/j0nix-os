# Building a Rust Package from Source in Nix (buildRustPackage)

## When to Use

- A Rust application is required but **not available in nixpkgs**.
- A Rust project provides only a GitHub repo / crates.io release — no nix
  derivation exists upstream.
- You want a native NixOS module (systemd service, firewall rules) rather than
  a manually downloaded static binary.

## Symptom

```bash
nix eval --json 'nixpkgs#crw-server'
# error: flake 'flake:nixpkgs' does not provide attribute 'packages.x86_64-linux.crw-server'...
```

## Solution: buildRustPackage + fetchFromGitHub

### Step 1: Check Existing Packages

```bash
nix eval --json 'nixpkgs#crw-server' 2>&1 | head -c 200
```

If it 404s, you need to package it manually.

### Step 2: Get the Source Hash

For a specific commit or tag:

```bash
nix-prefetch-url --unpack \
  "https://github.com/<owner>/<repo>/archive/<rev>.tar.gz"
```

Example for a tag:
```bash
nix-prefetch-url --unpack "https://github.com/us/crw/archive/v0.12.0.tar.gz"
# -> sha256: 13546ydicmicbnw3f48a0ad21ipc6j6sqz9rqlhgd5s7fns9wffw
```

Example for a commit:
```bash
nix-prefetch-url --unpack \
  "https://github.com/us/crw/archive/a3ab2ad1f254bdd6f24f690c89d466c3f0c3f5e9.tar.gz"
# -> sha256: 1gmi6y55d65hnqh075m1rqr41q1l63cc7dcx58bvq96k42snvxmx
```

### Step 3: Discover the cargoHash

```nix
# nix/system/dev/crw.nix  (or nix/pkgs/crw-server/default.nix)
{ lib, pkgs, ... }:

let
  crw-server = pkgs.rustPlatform.buildRustPackage rec {
    pname = "crw-server";
    version = "0.12.1-unstable-2025-06-05";

    src = pkgs.fetchFromGitHub {
      owner = "us";
      repo = "crw";
      rev = "a3ab2ad1f254bdd6f24f690c89d466c3f0c3f5e9";
      sha256 = "1gmi6y55d65hnqh075m1rqr41q1l63cc7dcx58bvq96k42snvxmx";
    };

    # Placeholder — let the build fail and print the correct hash
    cargoHash = "sha256-AAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAA=";
  };
in { ... }
```

Run once with the fake hash. Nix will fail and print the expected hash:

```
error: hash mismatch in fixed-output derivation '...-vendor-staging.drv':
         specified: sha256-AAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAA=
            got:    sha256-qJK0yjvlOeGvux4TxuEqZbCJJFlGIdS50vWsQSr/t6A=
```

Copy the **got** value into `cargoHash` and rebuild.

### Step 4: Handle Workspace Dependency Version Mismatches

Rust workspaces with path-based internal dependencies sometimes ship with
**mismatched version pins** — e.g. `crw-diff/Cargo.toml` depends on
`crw-core = "^0.11.0"` while the workspace manifest declares version `0.12.0`.

**Symptom:**
```
error: failed to select a version for the requirement `crw-core = "^0.11.0"`
candidate versions found which didn't match: 0.12.0
location searched: /build/source/crates/crw-core
required by package `crw-diff v0.12.0 (/build/source/crates/crw-diff)`
As a reminder, you're using offline mode (--offline)...
```

`buildRustPackage` runs Cargo in `--offline` mode after staging the vendored
dependencies. If the `Cargo.lock` does not exactly match the `Cargo.toml`
version requirements, resolution fails.

**Diagnostic steps:**

1. Check upstream `Cargo.toml` files for version mismatches:
```bash
for crate in crw-core crw-diff crw-server; do
  curl -sL "https://raw.githubusercontent.com/us/crw/main/crates/$crate/Cargo.toml" | grep -F 'crw-'
done
```

2. Check the `Cargo.lock` in the repo for what versions it actually resolved.

3. **Try a newer commit** — the mismatch may already be fixed on `main`:
```bash
# List recent commits
curl -sL "https://api.github.com/repos/us/crw/commits?per_page=20" | \
  python3 -c "import sys,json; [print(f\"{i}: {c['sha'][:8]} {c['commit']['message'].split(chr(10))[0][:50]}\") for i,c in enumerate(json.load(sys.stdin)[:15])]"
```

4. If a fixed commit exists, use it instead of the tagged release.

**Workaround: force workspace update**

If the `Cargo.lock` is stale but you have network access during postPatch
(before offline mode kicks in):

```nix
postPatch = ''
  cargo update --workspace
'';
```

This regenerates the lockfile so the internal dependency versions match
before the vendored dependencies are validated.

> ⚠️ **Caveat:** This requires the workspace to be self-consistent (all path
dependencies exist and their mutual version ranges are satisfiable). If the
up repo has a genuinely broken dependency graph, `cargo update` will also fail.

### Step 5: Wire into NixOS Module

```nix
# nix/system/dev/crw.nix
{ config, lib, pkgs, ... }:

let
  cfg = config.settings.dev.crw;

  crw-server = pkgs.rustPlatform.buildRustPackage rec {
    pname = "crw-server";
    version = "0.12.1-unstable-2025-06-05";

    src = pkgs.fetchFromGitHub {
      owner = "us";
      repo = "crw";
      rev = "a3ab2ad1f254bdd6f24f690c89d466c3f0c3f5e9";
      sha256 = "1gmi6y55d65hnqh075m1rqr41q1l63cc7dcx58bvq96k42snvxmx";
    };

    cargoHash = "sha256-qJK0yjvlOeGvux4TxuEqZbCJJFlGIdS50vWsQSr/t6A=";

    meta = with lib; {
      description = "Self-hosted Rust-native web crawler and scraper";
      homepage = "https://github.com/us/crw";
      license = licenses.agpl3Only;
      mainProgram = "crw-server";
    };
  };
in
{
  options.settings.dev.crw = {
    enable = lib.mkEnableOption "fastCRW self-hosted crawler/scraper API";
    port = lib.mkOption { type = lib.types.port; default = 3331; };
    openFirewall = lib.mkOption { type = lib.types.bool; default = true; };
    extraEnv = lib.mkOption { type = lib.types.attrsOf lib.types.str; default = {}; };
  };

  config = lib.mkIf cfg.enable {
    networking.firewall.allowedTCPPorts = lib.optional cfg.openFirewall cfg.port;

    systemd.services.crw-server = {
      description = "fastCRW server";
      after = [ "network-online.target" ];
      wantedBy = [ "multi-user.target" ];
      serviceConfig = {
        Type = "simple";
        ExecStart = "${crw-server}/bin/crw-server";
        Restart = "on-failure";
        DynamicUser = true;
        StateDirectory = "crw";
        WorkingDirectory = "/var/lib/crw";
      };
      environment = { CRW_PORT = toString cfg.port; } // cfg.extraEnv;
    };
  };
}
```

## Using `cargoLock` Instead of `cargoHash`

For larger workspaces where vendor hash churn is annoying, pin the entire
`Cargo.lock` explicitly:

```nix
cargoLock = {
  lockFile = ./Cargo.lock;
  outputHashes = {
    "crw-core-0.12.1" = "sha256-...";
  };
};
```

This requires extracting the `Cargo.lock` from upstream and committing it
alongside your module. Rarely needed unless you patch the source.

## Pitfalls

1. **Offline mode trap**: `buildRustPackage` always runs with `--offline`.
   Networked `cargo` commands must happen in `postPatch` (before offline
   validation hooks). `cargoUpdateHook` exists in some versions but is
   unreliable — prefer `postPatch`.

2. **Tag vs main branch drift**: A tagged release (e.g. `v0.12.0`) may have
   broken internal deps, while `main` at HEAD is already fixed. Always verify
   the tagged release actually compiles before committing to it.

3. **Sandbox test failures — CA certs / network access**: Tests that call
   `reqwest::Client::new()` or perform any HTTPS/network I/O fail in the
   Nix sandbox because no CA certificate bundle is available:
   ```
   Client::new(): reqwest::Error { kind: Builder,
     source: General("No CA certificates were loaded from the system") }
   ```
   **Fix:** Disable checks with `doCheck = false;` in the derivation.
   This is safe for packaging a binary — the upstream tests exercised the
   networking client code, which is irrelevant to whether the compiled
   artifact works on NixOS. The alternative (injecting `cacert` into
   `nativeCheckInputs` and patching every test client) is usually not
   worth the effort for a leaf package.

4. **Long build times**: Large Rust projects (especially with `html5ever`,
   `hyper`, `tokio`) can compile for 5–15 minutes. Use `terminal(background=true)`
   with `notify_on_complete=true` rather than blocking the session.

5. **Git tracking requirement**: New `.nix` files must be `git add`ed before
   `nix flake check --no-build` can see them. The error is:
   > Path 'foo.nix' in the repository "/path/to/repo" is not tracked by Git.

6. **fetchFromGitHub vs fetchCrate**: If the project also publishes to
   crates.io, `fetchCrate` can work — but crates.io may 403 or serve stale
   versions. `fetchFromGitHub` with a specific commit is more reliable for
   bleeding-edge Rust software.

## Verification

After wiring the module:

```bash
cd /path/to/flake
# Must git-add new files first!
git add nix/system/dev/crw.nix

nix flake check --no-build
# all checks passed! → derivation is valid

# Optionally, build just the package (no full system rebuild)
nix-build -E 'with import <nixpkgs> {}; pkgs.rustPlatform.buildRustPackage {
  pname = "crw-server"; version = "0.12.1";
  src = pkgs.fetchFromGitHub { owner = "us"; repo = "crw"; rev = "..."; sha256 = "..."; };
  cargoHash = "sha256-...";
}'
```

## When to Prefer OCI Containers Instead

If the Rust project:
- Is a multi-service stack (API + worker + Redis + browser sidecar), or
- Has a published official Docker image, or
- Is known to be fragile / has complex runtime deps (headless Chromium,
  Playwright, GPU drivers)

...then the OCI container route (`virtualisation.oci-containers`) may be
preferable to a native Rust build. The tradeoff is purely architectural
(ease of updates vs. purity of native Nix build).
