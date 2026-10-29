# printf Newline Bug in Generated Filter Scripts

## Synopsis

When generating a standalone bash script via `printf` for use as a `git-filter-branch` `--parent-filter`, using `printf '%s\\n'` (two backslashes) produces **literal backslash-n characters** instead of actual newline bytes. This causes the script to collapse into a single line, its shebang to break, and `git-filter-branch` to fail with `Not a valid object name` on merge commits (two parents).

## Reproduction

```bash
# BROKEN — double-backslash produces literal \n characters
printf '%s\\n' "line1" "line2" | cat -A
# Output: line1\nline2\n  (no $ markers = no real newlines)

# CORRECT — single-backslash produces real newlines
printf '%s\n' "line1" "line2" | cat -A
# Output: line1$
#         line2$   ($ = actual 0x0A newline byte)
```

## The Cascade in Parent-Filter Generation

| Source code | Generated script content | Runtime behavior |
|---|---|---|
| `printf '%s\\n'` | `printf '%s\n'` | Literal `\n` in output |
| `printf '%s\n'` | `printf '%s\n'` | Actual newline byte in output |

When the generated script itself contains a `printf` call, you need two levels of escaping awareness. The most common error is the four-backslash form in the outer printf, which becomes double-backslash in the generated file, which becomes literal backslash-n at runtime.

## Why Merge Commits Break

Normal commits have one parent (`-p sha1`). Even with a broken script, the shell might still pass the line through.

Merge commits have two parents on one line (`-p sha1 -p sha2`). The broken parent-filter outputs the entire unsplit line as a single "object name", which git refuses to resolve:

```
fatal: Not a valid object name 56e1aabb... 6ec3a232...
```

## Fix

Use single-backslash newlines when generating scripts with `printf`:

```bash
printf '%s\n' "#!/usr/bin/env bash" \
              "while IFS= read -r line; do" \
              "    line=\"\${line//-p ${cutoff_commit}/}\"" \
              "    printf '%s\n' \"\$line\"" \
              "done" > "$parent_filter_script"
```

## Verification

```bash
# After generating, always verify with cat -A (shows $ for newline)
cat -A "$parent_filter_script"
# Every line should end with $

# Or check with bash -n (catches shebang-in-the-middle syntax errors)
bash -n "$parent_filter_script"
```
