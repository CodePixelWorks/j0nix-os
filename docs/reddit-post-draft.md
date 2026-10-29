# Half a year without Windows — my CachyOS + Hyprland daily driver runs on my own NixOS config

I was one of those *"NixOS for work, but let me quickly dual-boot back into Windows for the occasional game"* people. I kept telling myself I needed that Windows partition.

Reality check: **that Windows install has been sitting untouched for half a year now.** Everything I actually do — including gaming — happens on NixOS.

## What sealed the deal

**Gaming.** Steam, Proton, controller drivers, launchers, Sunshine streaming — plus a kernel preset system. I run the CachyOS kernel (x86_64-v4) through a flake input with a pinned overlay, pulled straight from a binary cache. No more multi-hour kernel builds after every bump, no more "I'll just boot Windows for this one game".

**Bambu Lab Studio.** The 3D printing workflow is fully on NixOS.

**Autodesk Fusion 360.** Yes, the Windows-only CAD suite. That one took some real AI-assisted hacking to get working, and it works.

My daily desktop is the **Caelestia shell on Hyprland** — quickshell based, and it's the first shell where I stopped endlessly tweaking the bar and just use the machine.

## What the config is

It's called j0nix-os and it's been quietly becoming the foundation for every machine I rebuild:

- Multi-User from one settings file — per-user editors, shells, dev tools, window-manager shells. Add a user, flip a few options.
- Multi-WM — Hyprland-first, GNOME / Niri / MangoWc switchable per user.
- Pluggable Hyprland shells — Caelestia, Dark Material Shell, Noctalia, AGS.
- Secret-safe — SOPS-nix, per-user and per-host encrypted secrets.
- Dev ready — Docker / BuildKit, AI CLI agents wired in as MCP servers, per-host git identities.
- Typed monitor config — declarative monitors, no xrandr scripts.
- Kernel presets — CachyOS / Zen / LTS / stock as a one-line switch.

The whole thing separates **what your machine does** (a single settings file — cross-platform toggles, user preferences) from **which hardware it runs on** (per-host profiles). Same setup, new machine = change one file.

There's also a fully wired CI pipeline (Drone) doing flake checks and AI-assisted fix loops, plus a Renovate setup that keeps every flake input pinned to commit digests with grouped, automergeable PRs.

## On the vibecoding thing

Let's address it up front: a lot of this is vibecoded. AI agents wrote a lot of the code.

But here's my position: the thinking work — the architecture, the module boundaries, the settings/profiles split, what goes where and why — that was all done by me, deliberately, before any prompt was written. The AI typed; I designed.

And the CI pipeline keeps the result controlled instead of vibe-drifting. Vibecoded doesn't have to mean unmaintainable — it can mean you architect and the machine does the typing.

Screenshots of the daily driver (Caelestia shell on Hyprland) are attached as image uploads.

## The mirror

There's a public mirror of the config up — cleaned up, with settings templates included:

**https://github.com/CodePixelWorks/j0nix-os**

AMA about any of it.
