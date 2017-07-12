﻿#define waptsetup 
#define default_repo_url "http://wapt.tranquil.it/wapt"
#define default_wapt_server ""
#define AppName "WaptStarter"
#define output_dir "."
#define Company "Tranquil IT Systems"
;#define signtool "kSign /d $qWAPT Client$q /du $qhttp://www.tranquil-it-systems.fr$q $f"
#define install_certs "checked"

#include "wapt.iss"

[Files]
; sources of installer to rebuild a custom installer
Source: "innosetup\*"; DestDir: "{app}\waptsetup\innosetup";
Source: "wapt.iss"; DestDir: "{app}\waptsetup";
Source: "waptsetup.iss"; DestDir: "{app}\waptsetup";
Source: "services.iss"; DestDir: "{app}\waptsetup";

Source: "..\wapt.ico"; DestDir: "{app}";

; authorized public keys
Source: "..\ssl\*"; DestDir: "{app}\ssl"; Flags: createallsubdirs recursesubdirs

[Setup]
OutputBaseFilename=waptstarter
DefaultDirName={pf}\wapt
WizardImageFile=..\tranquilit.bmp

[INI]
Filename: {app}\wapt-get.ini; Section: global; Key: repo_url; String: {#default_repo_url};
Filename: {app}\wapt-get.ini; Section: global; Key: use_hostpackages; String: "0"
Filename: {app}\wapt-get.ini; Section: global; Key: waptservice_password; String: "NOPASSWORD"

[Icons]
Name: "{commonprograms}\WaptStarter"; IconFilename: "{app}\wapt.ico"; Filename: "http://localhost:8088";
Name: "{commondesktop}\WaptStarter"; IconFilename: "{app}\wapt.ico"; Filename: "http://localhost:8088";

[Run]
Filename: "{app}\wapt-get.exe"; Parameters: "--direct update"; Flags: runhidden; StatusMsg: {cm:UpdateAvailablePkg}; Description: "{cm:UpdateAvailablePkg}"
Filename: "{app}\wapt-get.exe"; Parameters: "add-upgrade-shutdown"; Flags: runhidden; StatusMsg: {cm:UpdateOnShutdown}; Description: "{cm:UpdateOnShutdown}"

[Languages]
Name:"en";MessagesFile: "compiler:Default.isl"
Name:"fr";MessagesFile: "compiler:Languages\French.isl"
Name:"de";MessagesFile: "compiler:Languages\German.isl"

[CustomMessages]
fr.UpdateAvailablePkg=Mise à jour des paquets disponibles sur le dépôt principal
fr.UpdateOnShutdown=Mise à jour des paquets à l'extinction du poste

;English translation here
en.UpdateAvailablePkg=Update packages available on the main repository
en.UpdateOnShutdown=Update packages upon shutdown

;German translation here
de.UpdateAvailablePkg=Verfügbare Pakete auf Main Repository aktualisieren
de.UpdateOnShutdown=Pakete aktualisieren beim Herunterfahren

[Code]
procedure DeinitializeUninstall();
var
    installdir: String;
begin
    installdir := ExpandConstant('{app}');
    if DirExists(installdir) and not runningSilently() and 
       (MsgBox('Des fichiers restent présents dans votre répertoire ' + installdir + ', souhaitez-vous le supprimer ainsi que tous les fichiers qu''il contient ?',
               mbConfirmation, MB_YESNO) = IDYES) then
        Deltree(installdir, True, True, True);
end;
