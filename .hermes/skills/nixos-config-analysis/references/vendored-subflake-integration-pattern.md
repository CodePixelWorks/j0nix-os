# Vendored Subflake Integration Pattern

When a flake needs a third-party NixOS/Home Manager module that is:
(a) not upstreamed to nixpkgs, and
(b) needed â€œalwaysâ€ (not gated behind a user toggle that might render the input unused),
embed it as a vendor directory under `integrations/<name>/` and import it via a local path flake input.
This is more reproducible than `fetchTarball` and keeps the module source in the repo where patches can be applied.

## Directory layout

```
integrations/
  README.md            # Pattern documentation for contributors
  <repo-name>/
    flake.nix          # The vendored subflake (kept intact from upstream)
    ...                # Upstream source files
```

The `integrations/README.md` should explain that these are vendored subflakes, kept in sync with upstream manually, and must not host host-specific or secret data.

## Flake wiring

In the root `flake.nix`:

```nix
inputs = {
  # ... usual inputs ...

  autodesk-fusion = {
    url = "path:./integrations/autodesk-fusion-nixos";
    inputs.nixpkgs.follows = "nixpkgs";
    inputs.home-manager.follows = "home-manager";
  };
};
```

The `path:` scheme is required for local subdirectories. The `follows` entries are mandatory so that nixpkgs and home-manager versions stay aligned with the main flake â€” otherwise the subflake pins its own versions and eval-cache thrashes.

After adding the input, run `nix flake lock` to regenerate `flake.lock`.

## Import in a user/system module

```nix
{ inputs
, pkgs
, ...
}:

# Import path: subflake from local vendor directory
imports = [ inputs.autodesk-fusion.nixosModules.default ];
```

Add a source-code comment above the `imports` line documenting the origin path, so future readers know it resolves to `integrations/`.

## When NOT to use this pattern

- If the module is only needed behind an optional toggle that is off by default, prefer a `fetchTarball` or a conditional `builtins.getFlake` in the module code itself. Dead flake inputs in `flake.lock` add eval overhead even when unused.
- If the dependency is large (e.g. a full desktop environment with heavy packages), prefer a separate flake that is composed via `follows` at consumer choice.

## Validation checklist

- [ ] `nix flake check --no-build` passes
- [ ] `nix flake lock` was run and `flake.lock` diff is clean
- [ ] `integrations/<repo-name>/` contains `flake.nix`
- [ ] `inputs.<name>.inputs.nixpkgs.follows` is set
- [ ] Source-code comment in the importing module documents the path
