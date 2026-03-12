{
  default = [
    # Do not center every floating window globally: popup/context menus in Flatpak apps
    # can also be floating and would otherwise jump to screen center.
    "match:modal 1, float 1, center 1"
    "match:group 1, float 1, center 1"

    # Common utility windows that are almost always better as floating dialogs.
    "match:class ^(pavucontrol)$, float 1, center 1"
    "match:class ^(nm-connection-editor)$, float 1, center 1"
    "match:class ^(blueman-manager)$, float 1, center 1"
    "match:class ^(org\\.gnome\\.Calculator)$, float 1, center 1"
    "match:class ^(zenity)$, float 1, center 1"
    "match:class ^(yad)$, float 1, center 1"
    "match:class ^(pinentry.*)$, float 1, center 1"
    "match:class ^(polkit-gnome-authentication-agent-1)$, float 1, center 1"
    "match:class ^(org\\.freedesktop\\.secrets)$, float 1, center 1"
    "match:class ^(org\\.gnome\\.FileRoller)$, float 1, center 1"
    "match:class ^(qt5ct|qt6ct)$, float 1, center 1"
    "match:class ^(xdg-desktop-portal-gtk)$, float 1, center 1"
    "match:class ^(org\\.freedesktop\\.impl\\.portal\\.FileChooser)$, float 1, center 1"

    # Bambu Studio popup dialogs (e.g. filament selection) position themselves;
    # forcing center breaks the in-window send/print flow. Keep this before generic
    # title rules in case the parser/runtime applies first-match semantics.
    "match:class ^(BambuStudio)$, float 1, center 0"
    "match:title ^(bambu-studio)$, float 1, center 0"

    # Generic dialog-like titles (file choosers, properties, about/preferences dialogs).
    "match:title ^(Open( File)?|Save( File)?|Select (File|Folder)|Choose (File|Folder)|Properties|Preferences|Settings|About)( .*)?$, float 1, center 1"
    "match:title ^(Datei öffnen|Datei speichern|Datei auswählen|Ordner auswählen|Eigenschaften|Einstellungen|Über)( .*)?$, float 1, center 1"
    "match:title ^(Save As|Open Folder|Open Files|Choose Application|Authentication Required|Confirm|Confirmation|Warning|Error|Information)( .*)?$, float 1, center 1"
    "match:title ^(Speichern unter|Bestätigung|Warnung|Fehler|Information|Authentifizierung erforderlich|Anmeldung|Anmelden)( .*)?$, float 1, center 1"
    "match:title ^(Sign In|Sign in|Login|Log in|Authenticate|Authentication)( .*)?$, float 1, center 1"
    "match:title ^(.*(Preferences|Settings|Properties|Dialog|Picker|Chooser).*)$, float 1, center 1"
    "match:title ^(.*(Einstellungen|Eigenschaften|Auswahl|Dialog|Anmeldung|Anmelden).*)$, float 1, center 1"

    # Duplicate Bambu exceptions after generic rules as well, so they still win if
    # Hyprland applies last-match semantics for rule actions.
    "match:class ^(BambuStudio)$, float 1, center 0"
    "match:title ^(bambu-studio)$, float 1, center 0"
  ];

  extra = [
    # Terminal TUIs: keep nmtui readable and centered.
    "match:class ^(foot)$, match:title ^(nmtui)$, float 1, size 60% 70%, center 1"

    # Larger settings dialogs benefit from a predictable size.
    "match:class ^(org\\.gnome\\.Settings)$, float 1, size 70% 80%, center 1"
    "match:class ^(org\\.pulseaudio\\.pavucontrol|pavucontrol|yad-icon-browser)$, float 1, size 60% 70%, center 1"
    "match:class ^(nwg-look)$, float 1, size 50% 60%, center 1"
    "match:class ^(wineboot\\.exe)$, match:title ^(Wine)$, float 1, center 1"
    "match:class ^(naps2)$, match:title negative:^NAPS2.*, float 1, center 1"

    # Picture-in-picture windows: keep them floating, pinned and ratio-safe.
    "match:title ^(Picture(-| )in(-| )[Pp]icture)$, float 1, pin 1, keep_aspect_ratio 1, move 100%-w-2% 100%-h-3%"

    # Steam friends list should behave like a utility window.
    "match:class ^(steam)$, match:title ^(Friends List)$, float 1, center 1"

    # Route dedicated workflow apps onto their shell special workspaces.
    "match:class ^(discord|Discord|vesktop|Vesktop|equibop|Equibop|ArmCord|armcord|WebCord|webcord|element-desktop|Element)$, workspace special:discord"
    "match:class ^(spotify|Spotify|feishin|Feishin|supersonic|Supersonic|cider|Cider|com\\.github\\.th_ch\\.youtube_music)$, workspace special:media"
    "match:class ^(KeePassXC|org\\.keepassxc\\.KeePassXC)$, workspace special:passwords"

    # Hide blur artefacts in Fusion overlays.
    "match:class ^(fusion360\\.exe)$, match:title ^(Fusion360|(Marking Menu))$, no_blur 1"

    # Ueberzugpp helper surfaces should not steal focus.
    "match:class ^(ueberzugpp_.*)$, float 1, no_initial_focus 1"
  ];
}
