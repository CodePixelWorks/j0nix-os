{ lib ? null }:
let
  asOnOff = value: if value then "1" else "0";
  renderMatch =
    name: value:
    "match:${name} "
    + (
      if builtins.isBool value then
        asOnOff value
      else if builtins.isList value then
        lib.concatStringsSep " " (map toString value)
      else
        toString value
    );
  renderEffect =
    name: value:
    "${name} "
    + (
      if builtins.isBool value then
        asOnOff value
      else if builtins.isList value then
        lib.concatStringsSep " " (map toString value)
      else
        toString value
    );
  renderRule = rule:
    lib.concatStringsSep ", " (
      (lib.mapAttrsToList renderMatch (rule.match or { }))
      ++ (lib.mapAttrsToList renderEffect (builtins.removeAttrs rule [ "match" "name" ]))
    );

  baseRules = [
    {
      name = "float-modal-dialogs";
      match.modal = true;
      float = true;
      center = true;
    }
    {
      name = "float-grouped-dialogs";
      match.group = true;
      float = true;
      center = true;
    }

    {
      name = "float-pavucontrol";
      match.class = "^(pavucontrol)$";
      float = true;
      center = true;
    }
    {
      name = "float-network-manager";
      match.class = "^(nm-applet|nm-connection-editor)$";
      float = true;
      center = true;
    }
    {
      name = "float-blueman";
      match.class = "^(blueman-manager)$";
      float = true;
      center = true;
    }
    {
      name = "float-gnome-calculator";
      match.class = "^(org\\.gnome\\.Calculator)$";
      float = true;
      center = true;
    }
    {
      name = "float-zenity";
      match.class = "^(zenity)$";
      float = true;
      center = true;
    }
    {
      name = "float-yad";
      match.class = "^(yad)$";
      float = true;
      center = true;
    }
    {
      name = "float-pinentry";
      match.class = "^(pinentry.*)$";
      float = true;
      center = true;
    }
    {
      name = "float-polkit";
      match.class = "^(polkit-gnome-authentication-agent-1)$";
      float = true;
      center = true;
    }
    {
      name = "float-secret-service";
      match.class = "^(org\\.freedesktop\\.secrets)$";
      float = true;
      center = true;
    }
    {
      name = "float-file-roller";
      match.class = "^(org\\.gnome\\.FileRoller)$";
      float = true;
      center = true;
    }
    {
      name = "float-pdf-load-dialog";
      match.class = "^(file-pdf-load)$";
      float = true;
      center = true;
    }
    {
      name = "float-pdf-export-dialog";
      match.class = "^(file-pdf-export)$";
      float = true;
      center = true;
    }
    {
      name = "float-qt-config-tools";
      match.class = "^(qt5ct|qt6ct)$";
      float = true;
      center = true;
    }
    {
      name = "float-xdg-desktop-portal-gtk";
      match.class = "^(xdg-desktop-portal-gtk)$";
      float = true;
      center = true;
    }
    {
      name = "float-filechooser-portal";
      match.class = "^(org\\.freedesktop\\.impl\\.portal\\.FileChooser)$";
      float = true;
      center = true;
    }
    {
      name = "float-gimp-child-dialogs";
      match = {
        class = "^(org\\.gimp\\.GIMP|gimp-2\\.10|Gimp-2\\.10|gimp)$";
        group = true;
      };
      float = true;
      center = true;
    }

    {
      name = "bambu-studio-class-no-center";
      match.class = "^(BambuStudio)$";
      float = true;
      center = false;
    }
    {
      name = "bambu-studio-title-no-center";
      match.title = "^(bambu-studio)$";
      float = true;
      center = false;
    }

    {
      name = "generic-open-save-dialogs";
      match.title = "^(Open( File)?|Save( File)?|Select (File|Folder)|Choose (File|Folder)|Properties|Preferences|Settings|About)( .*)?$";
      float = true;
      center = true;
    }
    {
      name = "generic-open-save-dialogs-de";
      match.title = "^(Datei öffnen|Datei speichern|Datei auswählen|Ordner auswählen|Eigenschaften|Einstellungen|Über)( .*)?$";
      float = true;
      center = true;
    }
    {
      name = "generic-utility-dialogs";
      match.title = "^(Save As|Open Folder|Open Files|Choose Application|Authentication Required|Confirm|Confirmation|Warning|Error|Information)( .*)?$";
      float = true;
      center = true;
    }
    {
      name = "generic-utility-dialogs-de";
      match.title = "^(Speichern unter|Bestätigung|Warnung|Fehler|Information|Authentifizierung erforderlich|Anmeldung|Anmelden)( .*)?$";
      float = true;
      center = true;
    }
    {
      name = "generic-auth-dialogs";
      match.title = "^(Sign In|Sign in|Login|Log in|Authenticate|Authentication)( .*)?$";
      float = true;
      center = true;
    }
    {
      name = "generic-settings-substring";
      match.title = "^(.*(Preferences|Settings|Properties|Dialog|Picker|Chooser).*)$";
      float = true;
      center = true;
    }
    {
      name = "generic-settings-substring-de";
      match.title = "^(.*(Einstellungen|Eigenschaften|Auswahl|Dialog|Anmeldung|Anmelden).*)$";
      float = true;
      center = true;
    }

    {
      name = "bambu-studio-class-no-center-override";
      match.class = "^(BambuStudio)$";
      float = true;
      center = false;
    }
    {
      name = "bambu-studio-title-no-center-override";
      match.title = "^(bambu-studio)$";
      float = true;
      center = false;
    }

    {
      name = "float-nmtui";
      match = {
        class = "^(foot)$";
        title = "^(nmtui)$";
      };
      float = true;
      size = [ "60%" "70%" ];
      center = true;
    }
    {
      name = "float-gnome-settings";
      match.class = "^(org\\.gnome\\.Settings)$";
      float = true;
      size = [ "70%" "80%" ];
      center = true;
    }
    {
      name = "float-pavucontrol-large";
      match.class = "^(org\\.pulseaudio\\.pavucontrol|pavucontrol|yad-icon-browser)$";
      float = true;
      size = [ "60%" "70%" ];
      center = true;
    }
    {
      name = "float-nwg-look";
      match.class = "^(nwg-look)$";
      float = true;
      size = [ "50%" "60%" ];
      center = true;
    }
    {
      name = "float-wineboot";
      match = {
        class = "^(wineboot\\.exe)$";
        title = "^(Wine)$";
      };
      float = true;
      center = true;
    }
    {
      name = "float-naps2-secondary-dialogs";
      match = {
        class = "^(naps2)$";
        title = "negative:^NAPS2.*";
      };
      float = true;
      center = true;
    }
    {
      name = "float-twintail-launcher";
      match.class = "^(app\\.twintaillauncher\\.ttl)$";
      float = true;
      center = true;
    }
    {
      name = "float-browser-utility-dialogs";
      match = {
        class = "^(firefox|org\\.mozilla\\.firefox|LibreWolf|librewolf|google-chrome|google-chrome-beta|chromium|chromium-browser|brave-browser)$";
        title = "^(Library|Downloads|Page Info|Bookmarks Manager|Extension Manager|Extensions|Add-ons Manager|Task Manager|Clear browsing data|Import bookmarks and settings|Choose Profile|Create Profile|About Mozilla Firefox|About Google Chrome|About Chromium|About Brave|Firefox Settings|Chrome Settings|Chromium Settings|Brave Settings)( .*)?$";
      };
      float = true;
      center = true;
    }
    {
      name = "picture-in-picture";
      match.title = "^(Picture(-| )in(-| )[Pp]icture)$";
      float = true;
      pin = true;
      keep_aspect_ratio = true;
      move = [ "100%-w-2%" "100%-h-3%" ];
    }
    {
      name = "steam-friends-list";
      match = {
        class = "^(steam)$";
        title = "^(Friends List)$";
      };
      float = true;
      center = true;
    }
    {
      name = "workspace-discord";
      match.class = "^(discord|Discord|vesktop|Vesktop|equibop|Equibop|ArmCord|armcord|WebCord|webcord|element-desktop|Element)$";
      workspace = "special:discord";
    }
    {
      name = "workspace-media";
      match.class = "^(spotify|Spotify|feishin|Feishin|supersonic|Supersonic|cider|Cider|com\\.github\\.th_ch\\.youtube_music)$";
      workspace = "special:media";
    }
    {
      name = "workspace-passwords";
      match.class = "^(KeePassXC|org\\.keepassxc\\.KeePassXC)$";
      workspace = "special:passwords";
    }
    {
      name = "ueberzugpp-no-initial-focus";
      match.class = "^(ueberzugpp_.*)$";
      float = true;
      no_initial_focus = true;
    }
  ];
in
{
  structured = baseRules;
  default = map renderRule (lib.take 30 baseRules);
  extra = map renderRule (lib.drop 30 baseRules);
}
