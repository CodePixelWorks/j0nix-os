# Autodesk Fusion Renderer-Testmatrix

## Ziel
Die Kombination finden, unter der Fusion 360 auf Jonas-PC (NVIDIA RTX 4070 Ti SUPER, NixOS, Hyprland)
ein Fenster zeigt UND der Workspace (3D-Viewport) funktioniert.

## Verfügbare Bausteine (Stand 2026-09-25)

| Baustein | Version | Herkunft |
|---|---|---|
| Wine (staging) | wine-wow64-staging-11.16 | NixOS home-manager |
| Wine (patched) | fusion-wine-build 11.0 (wine-mode) | j0nix Wine mode |
| GE-Proton | GE-Proton10-9 | Steam compatibilitytools |
| wineland | wineland-11.0-20260917 | Steam compat tool |
| Proton-cachyos | proton-cachyos 11.0 | Steam compat tool |

## Getestete Kombinationen (aus git history + live)

| # | GPU-Backend | Runner | Ergebnis | Datum |
|---|---|---|---|---|
| 1 | DXVK | wine-wow64-staging 11.16 | kein Fenster, exit 53 | 2026-09-25 |
| 2 | OpenGL | wine-wow64-staging 11.16 | Fenster da, kein Workspace | 2026-09-16/17 |

## Offen / als Nächstes testen

| Kombi | GPU-Backend | Runner | Erwartung |
|---|---|---|---|
| A | DXVK | GE-Proton10-9 | — |
| B | OpenGL | GE-Proton10-9 | — |
| C | OpenGL | wine-wow64-staging 11.16 | Fenster (siehe #2) | 
| D | DXVK | wineland-11.0-20260917 | — |
| E | OpenGL | wineland-11.0-20260917 | — |
