# Autodesk Fusion 360: Wayland- und Login-Status

Stand: 2026-09-26

## Revalidiertes Ergebnis (ersetzt den experimentellen Zielpfad)

Der native CachyOS-WineWayland-Proton-Weg ist auf Jonas-PC derzeit **nicht
installierbar**: Der Lolig4-Installer kann Prefix, WebView2 und DXVK einrichten,
doch `FusionClientInstaller.exe --quiet` bleibt sowohl mit
`PROTON_ENABLE_WAYLAND=1` als auch explizit mit `=0` ohne Netzwerk, Programmdateien
oder sichtbares Fenster hängen. Das ist ein reproduzierbarer Fehler im
FusionClient-/CachyOS-Proton-Zusammenspiel und kein Desktop-File- oder
Browser-Callback-Problem.

Der produktive Pfad ist daher Lolig4 `fusion-wine` auf dem Hyprland-Wayland-
Desktop über XWayland. Der vorhandene Prefix `fusion-1` wurde erneut gestartet:
`Fusion360.exe`, `ADPClientService.exe` und `AdskIdentityManager.exe` laufen,
und das Fusion-Fenster erscheint. Dieser Pfad nutzt den gemeinsamen
Host-Namespace, wodurch die früher erfolgreiche Login-IPC beibehalten wird.

`settings.programs.autodeskFusion.installerMode` ist deshalb auf
`"fusion-wine"` gesetzt. Der verwaltete Launcher normalisiert die Renderer wie
beim Lolig4-Referenzpfad: OpenGL für Fusion-Shell/Cloud-Sidebar und DXVK/D3D11
für den 3D-Canvas. `PROTON_ENABLE_WAYLAND=1` bleibt nur ein später erneut zu
prüfendes Experiment; es darf nicht mehr als Standard oder Reparaturpfad
verwendet werden.
Geltungsbereich: Jonas-PC, NixOS, Hyprland, NVIDIA RTX 4070 Ti SUPER

## Ziel

Fusion 360 soll mit dem experimentellen CachyOS WineWayland-Proton-Runner unter
Wayland laufen, dabei einen normalen, fensterbasierten Start haben und den
Autodesk-Browser-Login vollständig an den laufenden Fusion-Prozess zurückgeben.

Die zentrale Konfiguration liegt in `settings.nix` unter
`settings.programs.autodeskFusion`. Die Implementierung und alle verwalteten
Starter liegen in `nix/user/programs/autodesk-fusion/default.nix`.

## Aktueller Stand

| Bereich | Status | Befund |
|---|---|---|
| Installation | teilweise funktionsfähig | Ein neuer Proton-Prefix kann mit dem Lolig4-Installer erstellt werden. |
| Start von Fusion | funktioniert | `Fusion360.exe` startet über `cachyos-wineland-11.0-Fusion` mit `PROTON_ENABLE_WAYLAND=1`. |
| Wayland-Fenster | teilweise funktionsfähig | Fusion startet, kann aber einen Fullscreen-Zustand anfordern. Eine Hyprland-Regel soll dies unterdrücken. |
| Systembrowser-Login | funktioniert bis zum Redirect | Der Browser öffnet sich; nach **Open Product** liegt ein gültiger `adskidmgr:`-Callback vor. |
| Rückgabe des Logins | nicht funktionsfähig | Der Callback erreicht den gestarteten Identity Manager, aber nicht den SSO-Server der laufenden Fusion-Instanz. |
| Cloud-Dateien / 3D-Viewport | nicht funktionsfähig | UI-Bereiche waren weiß, schwarz oder nicht nutzbar; dies ist unabhängig vom nachgewiesenen Login-IPC-Problem noch offen. |
| alter `fusion-wine`-Prefix | Login funktionierte einmal | Der anfängliche Login nach der Installation war erfolgreich; das ist der Vergleichs- und Referenzpfad, jedoch keine Wayland-Lösung. |

## Gesicherte Erkenntnisse

### 1. Der Callback und der Identity Manager sind vorhanden

Fusion bringt `AdskIdentityManager.exe` im aktiven Prefix mit. Der verwaltete
URI-Handler `autodesk-fusion-adskidmgr.desktop` ist für
`x-scheme-handler/adskidmgr` registriert. Außerdem ersetzt der Installations-
Post-Processing-Schritt den Upstream-`adskidmgr-opener.sh` durch den j0nix-
Handler.

Der Browser kann daher den Login starten und einen `adskidmgr:/login?...`-
Callback erzeugen. Das Problem ist nicht, dass ein falsches oder zweites
Desktop-File den Browser grundsätzlich blockiert.

### 2. Die Anmeldung scheitert an getrennten Steam-Runtime-Sandboxen

Der aktuelle Wayland-Starter führt Fusion mit folgendem Prinzip aus:

```text
steam-run proton run Fusion360.exe
```

Der Callback-Starter führt den Identity Manager separat aus:

```text
steam-run wine AdskIdentityManager.exe adskidmgr:/login?...
```

`steam-run` verwendet Bubblewrap und erzeugt unter anderem ein eigenes
temporäres Dateisystem pro Aufruf. Damit laufen Fusion und der nachträglich
gestartete Identity Manager in unterschiedlichen Namespaces. Autodesk' lokale
SSO-/IPC-Verbindung ist dadurch nicht gemeinsam sichtbar.

Der aussagekräftige Logbefund lautet sinngemäß:

```text
Found valid http route: /login
Send oauth2 code skipped. No SSO server is running.
```

Das beweist: Der Callback wird geparst, doch der Identity Manager findet die
SSO-Gegenstelle von Fusion nicht. Ein manuelles Ausführen des Openers oder ein
weiteres `.desktop`-File kann diesen Namespace-Bruch nicht beheben.

### 3. Der frühere erfolgreiche Login erklärt sich durch einen gemeinsamen Host-Kontext

Der frühere `fusion-wine`-Prefix verwendete den lokalen gepatchten Wine-Runner
direkt. Fusion und Identity Manager konnten dadurch dieselben lokalen
Wine-/SSO-Ressourcen sehen. Dieser Pfad ist der Beleg, dass Browser, Autodesk-
Konto und URI-Callback grundsätzlich funktionieren.

Er löst jedoch nicht die Wayland- und Renderer-Anforderungen und darf daher
nicht als endgültige Lösung zurückkehren.

### 4. NixOS-spezifische Ursache für die Steam-Runtime-Umwege

Der CachyOS-Proton-Runner benötigt auch einen 32-Bit ELF-Loader. Beim direkten
Start außerhalb von `steam-run` trat auf:

```text
/lib/ld-linux.so.2: could not open
```

Zusätzlich brauchte der Proton-Python-Start `libvulkan.so.1`. `steam-run`
lieferte diese Laufzeitumgebung zwar, isolierte aber gleichzeitig den Login.
`programs.nix-ld` stellt derzeit die allgemeinen Laufzeitbibliotheken bereit,
aber der für diesen Runner benötigte i686-Loaderpfad ist nicht zuverlässig
verfügbar.

## Was bereits angepasst wurde

Die folgenden Änderungen sind im Branch `fix/fusion-nvidia-egl-vendor-pin`
enthalten:

- Fusion verwendet den Lolig4-Upstream-Installer und den Runner
  `cachyos-wineland-11.0-Fusion`.
- Fusion startet mit `PROTON_ENABLE_WAYLAND=1`.
- Vulkan-Loader und GnuTLS wurden für die jeweiligen Startpfade ergänzt.
- Eigenes j0nix-Desktop-File, Icon und eigener `adskidmgr:`-URI-Handler wurden
  angelegt; Upstream-Duplikate werden beim Home-Manager-Aktivieren entfernt.
- Der Installationsprozess erzeugt bzw. ersetzt den lokalen
  `adskidmgr-opener.sh` mit dem verwalteten Handler.
- Geerbte Qt-/Electron-Umgebungsvariablen werden bereinigt, weil sie Fusion-
  Chromium-/Qt-Panels schwarz machen können.
- Eine Hyprland-Regel versucht, einen von Fusion ausgelösten Fullscreen-
  Zustand wieder zu unterdrücken.

Diese Änderungen schaffen die Voraussetzungen für Wayland und den Callback;
sie beheben den Namespace-Konflikt noch nicht.

## Nicht funktionierende Ansätze und warum

| Ansatz | Ergebnis | Grund |
|---|---|---|
| Upstream- und j0nix-Desktop-Dateien parallel behalten | unzuverlässiger Start | Mehrere Launcher/Handler erzeugen keine gemeinsame Zuständigkeit. |
| Callback manuell mit `adskidmgr-opener.sh` ausführen | Callback wird gelesen, Login bleibt aus | Der aufgerufene Identity Manager läuft weiterhin getrennt von Fusion. |
| `steam-run` vor dem Desktop-Launcher | verschlechtert die Lage | Ein zusätzlicher Bubblewrap-Kontext kann Fusion noch weiter vom Callback trennen. |
| `steam-run` nur für den Callback | Login bleibt aus | Auch damit entsteht ein zweiter Namespace. |
| auf XWayland/`fusion-wine` zurückfallen | Login historisch erfolgreich | Verfehlt das Ziel eines funktionierenden Wayland-Stacks und behebt die Viewport-/Sidebar-Probleme nicht. |

## Verbindlicher Lösungsweg

Der Zielpfad muss Fusion und den Callback im selben Host-Namespace ausführen.
`steam-run` darf daher nicht den laufenden Fusion- oder Callback-Prozess
umschließen.

1. Den i686-Dynamic-Loader und die nötigen 32-Bit-Laufzeitbibliotheken
   deklarativ in NixOS bereitstellen. Der Pfad `/lib/ld-linux.so.2` muss für
   den CachyOS-Runner funktionieren; dies darf kein manueller, flüchtiger
   Symlink sein.
2. Den direkten Runner vor einer Neuinstallation isoliert prüfen:

   ```text
   wine --version
   proton run wineboot --init
   Vulkan-Lader verfügbar
   ```

   Diese Tests erfolgen ohne Fusion-Prefix und ohne Browser-Login.
3. Erst wenn die Basistests direkt auf dem Host funktionieren, `steam-run` aus
   dem Fusion-Starter, dem Desktop-File und dem Callback-Starter entfernen.
   Die Wayland-Variablen bleiben für Fusion gesetzt; der Identity Manager darf
   für seine XWayland-Oberfläche Wayland deaktivieren, bleibt aber im selben
   Host-Namespace.
4. Einen frischen Proton-Prefix installieren. Die bisherige Installation
   referenziert temporäre Installer-Wrapper und ist kein belastbarer Endstand.
5. Den Login mit einem neuen Browser-Flow testen und ausschließlich in den
   Logs prüfen, ob der OAuth-Code an einen laufenden SSO-Server gesendet wird.
   Zugangscodes und Callback-URLs gehören nicht in Tickets, Commits oder diese
   Dokumentation.
6. Danach Renderer separat prüfen: zunächst 3D-Viewport, danach Cloud-Sidebar,
   anschließend die Fensterregel gegen Fullscreen. Die Renderer-Matrix bleibt
   in [fusion-renderer-matrix.md](./fusion-renderer-matrix.md).

## Betriebsregeln bis zur Fertigstellung

- Nur den verwalteten Launcher `autodesk-fusion` bzw. das j0nix-Desktop-File
  verwenden; keine Upstream-Desktop-Dateien reaktivieren.
- Nicht mehrere Fusion- oder Identity-Manager-Instanzen parallel starten.
- Fehler nicht durch Kopieren eines OAuth-Codes in Shell-Historie oder Doku
  behandeln; diese Codes sind kurzlebig und vertraulich.
- Alte Prefixe nicht löschen, bevor der neue direkte Wayland-Pfad vollständig
  getestet ist. Der alte `fusion-wine`-Prefix bleibt der Vergleichspunkt für
