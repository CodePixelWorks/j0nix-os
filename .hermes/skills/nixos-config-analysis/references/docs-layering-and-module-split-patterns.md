# AI-Ergonomic Docs Layering + Module Split Mechanics

From the nixos-server-base architecture optimization (2026-08, phases 2-3).
Goal stated by Jonas: make structure easier for AI to navigate AND save
tokens. Two patterns resulted.

## Pattern A: Documentation Authority Split + Per-Directory Agent Guides

Problem: root AGENTS.md (~14 KB) + README (~16 KB) load every session;
module-status docs duplicate option lists from module READMEs; app long-form
guides (AUTHENTIK.md) restate the option contract. Every fact in two places
equals drift risk plus wasted context.

### Authority rule (codified in root AGENTS.md Documentation section)

Each fact lives in EXACTLY one layer; every other mention links instead of
repeating:

- Root README: entry point, repo layout, quick start, cross-stack overview
  tables.
- Owning module README: usage/options/side effects — SINGLE usage authority.
- docs/module-status/: architecture maturity snapshots (integration matrix,
  runtime state, security posture, gaps, roadmap). Never restate option lists
  or usage steps owned by the module README.
- docs/agent-memory/: debugging facts (symptom, root cause, verified fix),
  committed lab credentials, verification commands.
- modules/**/<APP>.md long-form guides: only helper-script/workflow docs that
  fit no README; MUST link to module-status and the options source.

### Per-directory AGENTS.md guides

One compact (<1 KB) AGENTS.md per top-level directory (server-base, stacks,
profiles, hosts, labs, tests, lib, docs, customers). Contents, in order:

1. One-line purpose of the directory.
2. Where to start reading (entry files, public namespace).
3. Directory-specific conventions that differ from root (e.g. stacks:
   mkDefault priority contract, mandatory-access registration requirement,
   checkmkAgent guard).
4. Pointer to owning README/status/memory docs.

Why it works: agents only load the guide for the directory they work in —
root stays lean, local conventions are discoverable exactly where needed.
Keep them under ~15 lines; signposts, not manuals.

Rollout gotcha: dedupe BEFORE adding guides (fix the worst duplication
first — e.g. delete an option table duplicating the module contract and link
to the options source instead) or the guides will enshrine the duplication.

## Pattern B: Splitting Monolithic Stack Modules (authentik pattern)

Trigger: any .nix stack module over ~1000 lines. Candidates ranked by size
(sites.nix 2330, restic.nix 1977, gitea.nix 1530, nextcloud.nix 1335).

Reference implementation: modules/stacks/apps/authentik/ — default.nix plus
containers/bootstrap/proxy/monitoring/username-validator, sharing computed
values via a ctx attribute passed into submodule files.

Split recipe (learned doing gitea):

1. Map the file: let-bindings (lines 1-72), options block (73-713), config
   block (715-end). Note which let-bindings the OPTIONS block needs versus
   which the CONFIG needs — usually disjoint.
2. Options file must be self-contained: copy the few small derivations it
   needs (stateDir/LFS path/backup paths) rather than threading a ctx
   through. KISS beats DRY for pure path strings duplicated once.
3. Keep config-side let-bindings in the main file; import ./options.nix from
   it. Submodule files needing shared values receive a ctx argument
   (authentik style: config, lib, pkgs, authentikCtx).
4. MECHANICAL HAZARD: assembling a new file from extracted line ranges easily
   produces a missing final closing brace or stray trailing brace. ALWAYS run
   nix-instantiate --parse <newfile> immediately after assembly. Symptom if
   skipped: "syntax error, unexpected ';', expecting end of file" on the last
   line.
5. Verify with the stack eval-check AND its VM test. Eval checks assert
   option values only; they miss publication/backend paths lost in transit —
   authentik's Apache httpd block was silently dropped by an earlier split
   and only apache eval coverage caught it.
6. Commit per concern (options extraction, then behavior fixes discovered on
   the way), never one mega-commit.

Sequencing note from Jonas: do the Phase-4 restic registry refactor BEFORE or
WITH the restic.nix split — removing the include*/or{} fallbacks shrinks the
file and reshapes its internals anyway; splitting first would be rework.
