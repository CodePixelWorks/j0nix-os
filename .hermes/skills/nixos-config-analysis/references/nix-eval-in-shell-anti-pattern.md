# Topic: Nix Eval in Shell Scripts — Anti-Pattern and Fix

## Problem

Scripts that embed multiline Nix expressions inside bash double-quoted strings (`"..."`) for `nix eval --expr` break deterministically on:

- `$` → bash expansion (use `"\$foo"` or `'$foo'` inside escaped string)
- `"` → nested quoting hell
- `\` → escaping order ambiguity (bash → nix → nix string)
- Newlines in Nix string literals → lost or mangled

This is not a rare edge case. It is a fundamental impedance mismatch.

## Example of Broken Code

```bash
# scripts/generate-keybind-docs.sh (broken version)
nix eval --json --impure --expr "
  let
    flake = builtins.getFlake (toString ./.);
    pkgs = flake.inputs.nixpkgs.legacyPackages.x86_64-linux;  # ← hardcoded arch
    lib = pkgs.lib;
    # ... 80 more lines of Nix inside bash double-quotes
  in
  keybindLib.categorizeBinds allParsed
" > /tmp/keybinds.json
```

**Failures observed:**
1. `x86_64-linux` hardcoded fails on aarch64 or when cross-evaluating.
2. `"\$\$mainMod"`-Escaping eventually desyncs and produces `"mainMod"` without `$`.
3. Adding a Nix string `"foo"` requires `"\"foo\""` in bash (14 characters for 2 quotes).
4. The script is un-verifiable as Nix syntax (`nix-instantiate --parse` can't read the bash wrapper).

## Fix: Separate `.nix` File + `--expr 'import ...'`

Extract the Nix expression into a standalone `.nix` file and import it via `--expr`:

```bash
# scripts/generate-keybind-docs.sh (fixed)
nix eval --json --impure --expr 'import ./scripts/generate-keybind-data.nix' > /tmp/keybinds.json
```

```nix
# scripts/generate-keybind-data.nix
let
  # --expr preserves CWD as repo root; --file would set CWD to scripts/
  repoRoot = builtins.dirOf (builtins.toPath ./.);
  flake = builtins.getFlake (toString repoRoot);
  system = builtins.currentSystem;
  pkgs = flake.inputs.nixpkgs.legacyPackages.${system};
  lib = pkgs.lib;
in
keybindLib.categorizeBinds allParsed
```

**Why `--expr 'import ./path'` instead of `--file path`**: When using `--file scripts/foo.nix`, Nix resolves `./.` inside that file to `scripts/`, not the repo root. All relative imports of `user/wm/hyprland/...` break. With `--expr 'import ./scripts/foo.nix'`, the CWD stays the repo root and `./.` resolves correctly. If the `.nix` file lives in a subdirectory but imports modules from sibling directories, `--expr` is mandatory.

## Advantages

| Dimension | Inline `--expr` in bash | Separate `.nix` |
|---|---|---|
| Arch portability | Hardcoded `x86_64-linux` | `builtins.currentSystem` |
| Quoting complexity | Exponential (bash + nix) | O(1) — plain Nix |
| Tooling | None (can't lint/preview) | `nix-instantiate --parse`, `nix eval --json --file` directly |
| IDE support | Broken (".sh" with embedded Nix) | Works (syntax highlighting, flycheck) |
| Mocking for tests | Inline string manipulation | Load `.nix` with test inputs via `import` override |
| Copy-paste for testing | Impossible (escaping leaks) | Full expression copy-paste into `nix repl` |

## Additional Nix Pitfalls

### `or` in lambda parameters is illegal

Nix `or` works on attribute access (`attr.foo or bar`) but NOT on bare identifiers in function parameters. This fails at parse time:

```nix
# ILLEGAL (causes: error: undefined variable 'or')
parseShellBinds = type: lines:
  map (line: ...)
    (lines or [ ]);   # lines is a parameter, not an attr path
```

The legal pattern: pass the fallback at the call site, not inside the lambda body:

```nix
# Correct
parseShellBinds = type: lines:
  map (line: ...)
    lines;            # lines is guaranteed to be a list by caller

# At call site
caelestiaData.bindle or [ ]  # attr access — this IS legal
```

### Bash stdout redirection scope

A heredoc redirect (`cat > file <<'EOF'`) only redirects the heredoc body, not any code after it. A `for` loop after the heredoc will print to stdout instead of the file. Wrap the entire generation block:

```bash
# BUG: only header goes to file; loop output goes to terminal
 cat > "$OUTFILE" <<'HEADER'
# Header
HEADER
for x in ...; do echo "$x"; done   # goes to stdout!

# FIX: wrap everything in a block redirected to the file
{
  cat <<'HEADER'
# Header
HEADER
  for x in ...; do echo "$x"; done
} > "$OUTFILE"
```

## When a Hybrid is Acceptable

**Only** if the Nix expression is genuinely one-liner (e.g. `nix eval --impure --expr 'builtins.currentSystem'`). The threshold: if the expression spans > 2 lines or contains `"` or `$`, extract it to a file immediately.

## Mocking Pattern for Module Evaluation

When the standalone `.nix` file imports submodules that expect flake-time arguments, mock them with minimal valid substitutes:

```nix
# Mock dependencies
homeBinDir = "$HOME/.local/bin";
appExec = x: x;
workspaceSwitchBinds = lib.concatMap (i:
  let key = if i == 10 then "0" else toString i;
  in [ "\$mainMod, ${key}, workspace, ${toString i}" ]
) (lib.range 1 10);
```

**Critical**: ensure the mock types match the real function signatures. A `null` default where the real code expects a string list will silently produce empty attrsets dropped by downstream categorizers.
