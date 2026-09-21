# Integrating an AppImage Application into a NixOS Flake

**Scope**: Adding a third-party Electron or Qt application distributed as an AppImage into a `j0nix-os`-style flake.

## Pattern

### 1. Fetch the AppImage hash

```bash
nix-prefetch-url "https://github.com/<owner>/<repo>/releases/download/<tag>/<AppImage>"
```

### 2. Create the package

`system/software/pkgs/<category>/<pname>.nix`:

Note: Some AppImages ship **no desktop entry or icon** inside the squashfs. `extraInstallCommands` must generate them manually. Do not assume `$out/share/applications/*.desktop` exists.

```nix
{
  lib,
  fetchurl,
  appimageTools,
}:

let
  icon = fetchurl {
    url = "https://raw.githubusercontent.com/<owner>/<repo>/main/public/icon.png";
    hash = "sha256-AAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAA=";
  };
in
appimageTools.wrapType2 rec {
  pname = "mystream";
  version = "1.0.0";

  src = fetchurl {
    url = "https://github.com/<owner>/<repo>/releases/download/v${version}/MyStream-${version}.AppImage";
    hash = "sha256-AAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAA=";
  };

  extraInstallCommands = ''
    mkdir -p $out/share/applications
    cat > $out/share/applications/mystream.desktop <<EOF
[Desktop Entry]
Name=MyStream
Exec=mystream
Type=Application
Terminal=false
Icon=mystream
Categories=AudioVideo;Video;Player;
EOF

    install -Dm644 ${icon} $out/share/icons/hicolor/256x256/apps/mystream.png
  '';

  meta = {
    description = "...";
    homepage = "https://github.com/...";
    license = lib.licenses.unfree;
    sourceProvenance = [ lib.sourceTypes.binaryNativeCode ];
    platforms = [ "x86_64-linux" ];
    mainProgram = "mystream";
  };
}
```

### 3. Wire into overlay

`system/lib/flake/overlays.nix`:

```nix
mystream = final.callPackage (baseDir + "/system/software/pkgs/streaming/mystream.nix") { };
```

### 4. Create minimal Home Manager module

`user/programs/<pname>/default.nix`:

```nix
{
  lib,
  pkgs,
  settings,
  ...
}:
let
  cfg = (settings.programs or { }).mystream or { };
  enabled = cfg.enable or false;
in
lib.mkIf enabled {
  j0nix.user.software.packages = [ pkgs.mystream ];
}
```

**Important**: In Home Manager modules for this repo, `settings` IS the per-user merged settings object (from `mkUserSettings username`). Use `settings.programs.<name>.enable`, NOT `settings.userSettings.<name>.programs.<name>.enable`.

### 5. Import in `user/programs/default.nix`

```nix
imports = [
  # ...existing imports...
  ./mystream
];
```

### 6. Add to settings.nix.example

```nix
programs = {
  mystream = {
    enable = false;
  };
};
```

### 7. Validate

```bash
nix flake check --no-build
```

Then do a **real build** -- `nix flake check --no-build` does NOT run `extraInstallCommands`:

```bash
nix build --impure --expr "with import <nixpkgs> {}; appimageTools.wrapType2 { pname = \"mystream\"; version = \"1.0.0\"; src = builtins.fetchurl { url = \"...\"; sha256 = \"...\"; }; }"
ls -la result/share/applications/  # verify .desktop exists
ls -la result/share/icons/         # verify icon exists
```

### 8. Enable per-user in settings.nix

```nix
userSettings = {
  jonas = {
    programs.mystream.enable = true;
  };
};
```

### 9. Commit

```text
feat(mystream): add MyStream 1.0.0 media streaming app

Package:
- system/software/pkgs/streaming/mystream.nix
- AppImage-based from GitHub releases
- Includes manual .desktop entry and icon (none in AppImage)

Wiring:
- Overlay: pkgs.mystream
- Home Manager module: user/programs/mystream/default.nix

nix flake check --no-build passed.
```

## Pitfalls

- **`nix flake check --no-build` misses build-time failures**: It validates evaluation only. A broken `install` or `substituteInPlace` in `extraInstallCommands` only surfaces during real `nix build` or `nixos-rebuild switch`.
- **Missing upstream `.desktop`**: Many AppImages ship without `.desktop` or icon files. Always verify by extracting with `--appimage-extract` or checking the build output.
- **Hash mismatch**: AppImage releases can be silently replaced. Always re-prefetch after upstream updates.
- **Hardcoded username in HM module**: `settings` IS already per-user merged. Never hardcode a username like `lib.attrByPath ["userSettings" "jonas" "programs" "..."]`.
- **Untracked git paths**: Nix flakes require all imported paths to be in git's index. Run `git add <path>` before `nix flake check`.
- **Icon fetch**: Use `fetchurl` for raw GitHub URLs (like `raw.githubusercontent.com/.../icon.png`). Run `nix-prefetch-url --type sha256 <url>` to get the hash.
  - `nix-prefetch-url` outputs a **base-32** hash by default (e.g., `08zs7sqs9diqyz335nflg7051cxrl5gn260m3l499gl5aan0yqrq`).
  - Convert to SRI base-64 for `fetchurl.hash`: `nix-hash --to-base64 --type sha256 <base32-hash>`
  - Or use `nix-prefetch-url --type sha256 --name <name> <url>` and pass the raw output into `sha256-<base64>`.
- **Desktop entry name collision**: If the AppImage provides a generic name, override or drop it in `extraInstallCommands` to avoid duplicate menu entries.
- **Large icon files**: If the icon exceeds a few KB, consider `fetchurl` with `sha256` instead of inlining base64. The store deduplicates anyway.
