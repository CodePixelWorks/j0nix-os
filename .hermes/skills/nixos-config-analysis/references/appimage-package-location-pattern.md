# Vergleich: AppImage-Package-Lokation — `system/`-Package vs. `user/`-Package

## Kontext

In `j0nix-os` gibt es zwei Muster, wo AppImage-Package-Definitionen leben:

| Muster | Pfad | Beispiel | Wann sinnvoll |
|--------|------|----------|---------------|
| **System-Paket** | `system/software/pkgs/<kategorie>/<name>.nix` | `system/software/pkgs/streaming/streambert.nix` | Paket hat eigenständige Wiederverwendung, wird via Overlay/CallPackage genutzt, oder ist ein upstream-Build von Nix-Paket-Quelle |
| **User-lokales Paket** | `user/programs/<name>/appimage-package.nix` | `user/programs/bambulab/appimage-package.nix` | Paket ist ausschließlich für diese eine HM-Module-Integration, wird nirgendwo anders referenziert, und ist per `pkgs.callPackage` an Ort und Stelle gebunden |

## Entscheidungsregel

1. **Wird das Paket via `pkgs.<name>` (Overlay) referenziert?** → `system/software/pkgs/`
2. **Wird das Paket nur von einem einzigen HM-Modul per `callPackage` geladen?** → `user/programs/<name>/` ist akzeptabel, aber `system/software/pkgs/` ist ebenfalls korrekt und konsistenter
3. **Gibt es eine Overlay-Definition in `system/lib/flake/overlays.nix`?** → Dann MUSS das Paket unter `system/software/pkgs/` liegen, da Overlays auf Pfade relativ zum Repo-Root auflösen und `user/`-Pfade dort unüblich sind

## Beispiele aus dem Repo

| App | Package-Pfad | Overlay-Eintrag | Einheitlich? |
|-----|-------------|-----------------|--------------|
| streambert | `system/software/pkgs/streaming/` | `overlay.nix` | JA |
| bambulab | `user/programs/bambulab/appimage-package.nix` | ❌ (callPackage direkt) | Nein — sollte nach `system/software/pkgs/` |
| better-soundcloud | `system/software/pkgs/audio/` | `overlay.nix` | JA |
| autodesk-fusion | `integrations/autodesk-fusion-nixos/pkgs/` | `overlay.nix` | JA (externes Submodul) |

## Migration: bambulab AppImage → system/

```bash
# 1. Verschieben
mv user/programs/bambulab/appimage-package.nix \
   system/software/pkgs/3d-printing/bambu-studio-appimage.nix

# 2. Overlay-Eintrag hinzufügen
bambu-studio-appimage = final.callPackage (baseDir + "/system/software/pkgs/3d-printing/bambu-studio-appimage.nix") { };

# 3. HM-Modul aktualisieren
# In user/programs/bambulab/default.nix:
#   bambuAppImagePackage = pkgs.bambu-studio-appimage;
# statt pkgs.callPackage
```

## Korollar: AppImage-Package-Unterordner

Wenn ein Paket unter `system/software/pkgs/` landet, verwende einen semantischen Unterordner:
- `streaming/` für Media-Streaming-Apps
- `audio/` für Musik-Clients
- `3d-printing/` für Slicer/Druck-Software
- `dev/` für Entwickler-Tools
- `windows/` für Windows-Kompatibilitäts-Tools (Wine/Bottles)

Vermeide flache Listen in `system/software/pkgs/` — sie skalieren nicht.
