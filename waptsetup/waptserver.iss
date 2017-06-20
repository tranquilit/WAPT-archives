#define waptserver 
#define AppName "WAPT Server"
#define default_repo_url "http://localhost:8080/wapt/"
#define default_wapt_server "http://localhost:8080"
#define output_dir "."
#define Company "Tranquil IT Systems"
;#define signtool "kSign /d $qWAPT Client$q /du $qhttp://www.tranquil-it-systems.fr$q $f"
#define install_certs 0

#include "wapt.iss"


[Files]
; sources of installer to rebuild a custom installer (ignoreversion because issc has no version)
Source: "innosetup\*"; DestDir: "{app}\waptsetup\innosetup"; Flags: createallsubdirs recursesubdirs ignoreversion;
Source: "wapt.iss"; DestDir: "{app}\waptsetup";
Source: "waptsetup.iss"; DestDir: "{app}\waptsetup";
Source: "services.iss"; DestDir: "{app}\waptsetup";
Source: "..\wapt.ico"; DestDir: "{app}";

; sources to regenerate waptupgrade package
Source: "..\waptupgrade\setup.py"; DestDir: "{app}\waptupgrade"; Flags: ignoreversion;
Source: "..\waptupgrade\WAPT\*"; DestDir: "{app}\waptupgrade\WAPT"; Flags: createallsubdirs recursesubdirs ignoreversion;

; global management console
Source: "..\waptconsole.exe.manifest"; DestDir: "{app}";
Source: "..\waptconsole.exe"; DestDir: "{app}"; Flags: ignoreversion
Source: "..\waptdevutils.py"; DestDir: "{app}";

; server postconf utility
Source: "..\waptserverpostconf.exe"; DestDir: "{app}"; Flags: ignoreversion

; deployment/upgrade tool
Source: "..\waptdeploy.exe"; DestDir: "{app}\waptserver\repository\wapt\"; Flags: ignoreversion

; Sources for server application
Source: "waptserver.iss"; DestDir: "{app}\waptsetup";
Source: "..\waptserver\waptserver.ini.template"; DestDir: "{app}\conf"; DestName: "waptserver.ini"
Source: "..\waptserver\*.py"; DestDir: "{app}\waptserver";       
Source: "..\waptserver\*.template"; DestDir: "{app}\waptserver";  
Source: "..\waptserver\templates\*"; DestDir: "{app}\waptserver\templates"; Flags: createallsubdirs recursesubdirs
Source: "..\waptserver\translations\*"; DestDir: "{app}\waptserver\translations"; Flags: createallsubdirs recursesubdirs
Source: "..\waptserver\scripts\*"; DestDir: "{app}\waptserver\scripts"; Flags: createallsubdirs recursesubdirs
Source: "..\waptserver\apache-win32\*"; DestDir: "{app}\waptserver\apache-win32"; Flags: createallsubdirs recursesubdirs

; For UninstallRun
Source: "..\waptserver\uninstall-services.bat"; Destdir: "{app}\waptserver\"

[Languages]
Name: "en"; MessagesFile: "compiler:Default.isl"
Name:"fr";MessagesFile: "compiler:Languages\French.isl"
Name:"de";MessagesFile: "compiler:Languages\German.isl"

[Dirs]
Name: "{app}\waptserver\repository"
Name: "{app}\waptserver\log"
Name: "{app}\waptserver\repository\wapt"
Name: "{app}\waptserver\repository\wapt-host"
Name: "{app}\waptserver\repository\wapt-group"
Name: "{app}\waptserver\apache-win32\ssl"

[Setup]
OutputBaseFilename=waptserversetup
DefaultDirName=c:\wapt
WizardImageFile=..\tranquilit.bmp

[INI]
Filename: {app}\wapt-get.ini; Section: global; Key: use_hostpackages; String: "1";

[RUN]
Filename: "{app}\wapt-get.exe"; Parameters: "add-upgrade-shutdown"; Flags: runhidden; StatusMsg: {cm:UpdatePkg}; Description: "{cm:UpdatePkg}"
Filename: "{app}\waptpythonw.exe"; Parameters: """{app}\waptserver\waptserver.py"" install {code:GetWaptServerInstallFlags}"; StatusMsg: {cm:RegisteringService}; Description: "{cm:SetupService}"
Filename: "{app}\waptserverpostconf.exe"; Parameters: "-l {code:CurrentLanguage}"; Flags: nowait postinstall runascurrentuser skipifsilent; StatusMsg: {cm:LaunchingPostconf}; Description: "{cm:LaunchingPostconf}"

[Icons]
Name: "{commonstartup}\WAPT session setup"; Filename: "{app}\wapt-get.exe"; Parameters: "session-setup ALL"; Flags: runminimized excludefromshowinnewinstall;
Name: "{commonstartup}\WAPT tray helper"; Tasks: autorunTray; Filename: "{app}\wapttray.exe"; Flags: excludefromshowinnewinstall;
Name: "{group}\Console WAPT"; Filename: "{app}\waptconsole.exe"; WorkingDir: "{app}"
Name: "{group}\Logiciels install�s avec WAPT"; Filename: "http://localhost:8088/status"

[Tasks]
Name: autorunSessionSetup; Description: "{cm:LaunchSession}"
Name: installApache; Description: "{cm:InstallApache}"

[UninstallRun]
Filename: "{app}\waptserver\uninstall-services.bat"; Flags: runhidden; StatusMsg: "Stopping and deregistering waptserver"

[CustomMessages]
fr.UpdatePkg=Mise � jour des paquets � l'extinction du poste
fr.RegisteringService=Enregistrement de WAPTservice
fr.SetupService=Mise en place du service WAPTserver
fr.LaunchingPostconf=Lancement de la post-configuration du serveur
fr.InstallApache=Installer Apache (utilisera les ports 80 et 443)

en.UpdatePkg=Update packages upon shutdown
en.RegisteringService=Registering WaptServer Service
en.SetupService=Setup WaptServer Service
en.LaunchingPostconf=Launch server post-configuration
en.InstallApache=Install Apache (will use ports 80 and 443)

de.UpdatePkg=Pakete beim Herunterfahren aktualisieren
de.RegistreringService=Registrierung auf WaptServer Service
de.SetupService=Setup WaptServer Service
de.LaunchingPostconf=Server Post-Konfiguration starten
de.InstallApachek=Apache installieren (verwendet Ports 80 und 443)

[Code]
procedure DeinitializeUninstall();
var
    installdir: String;
begin
    installdir := ExpandConstant('{app}');
    if DirExists(installdir) and not runningSilently() and
       (MsgBox('Des fichiers restent pr�sents dans votre r�pertoire ' + installdir + ', souhaitez-vous le supprimer ainsi que tous les fichiers qu''il contient ?',
               mbConfirmation, MB_YESNO) = IDYES) then
        Deltree(installdir, True, True, True);
end;

function CurrentLanguage(Param: String):String;
var
  Current: String;
begin
  Result := 'en';
  Current := ActiveLanguage;
  // Whitelist
  if Current = 'fr' then
    Result := 'fr';
end;

function GetWaptServerInstallFlags(Param: String):String;
begin
  Result := '';
  if IsTaskSelected('installApache') = False then
    Result := '-- --without-apache';
end;

function NextButtonClick(CurPageID: Integer):Boolean;
var
  Reply: Integer;
  NetstatOutput, ConflictingService: AnsiString;
begin

  if CurPageID <> wpSelectTasks then
  begin
    Result := True;
    Exit;
  end;

  if not IsTaskSelected('installApache') then
  begin
    Result := True;
    Exit;
  end;

  ConflictingService := '';

  NetstatOutput := RunCmd('netstat -a -n -p tcp', True);
  if Pos('0.0.0.0:443 ', NetstatOutput) > 0 then
    ConflictingService := '443'
  else if Pos('0.0.0.0:80 ', NetstatOutput) > 0 then
    ConflictingService := '80'
  ;

  if ConflictingService = '' then
  begin
    Result := True;
    Exit;
  end;

  Reply := MsgBox('There already is a Web server listening on port '+ ConflictingService +'. ' +
   'You have several choices: abort the installation, ignore this warning (NOT RECOMMENDED), ' +
   'deactivate the conflicting service and replace it with our bundled Apache server, or choose ' +
   'not to install Apache.  In the latter case it is advised to set up your Web server as a reverse ' +
   'proxy to http://localhost:8080/.' , mbError, MB_ABORTRETRYIGNORE);
  if Reply = IDABORT then
    Abort;

  Result := Reply = IDIGNORE;

end;

function InstallCertCheck:Boolean;
begin
	Result := {#install_certs} <> 0;
end;
