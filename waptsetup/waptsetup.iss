﻿#define waptsetup 
#define default_repo_url ""
#define default_wapt_server ""
#define AppName "WAPT"
#define output_dir "."
#define Company "Tranquil IT Systems"
#define install_certs 0
#define send_usage_report 0
#define is_waptagent 0
;#define signtool "kSign /d $qWAPT Client$q /du $qhttp://www.tranquil-it-systems.fr$q $f"

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

; authorized public keys
Source: "..\ssl\*"; DestDir: "{app}\ssl"; Flags: createallsubdirs recursesubdirs; Check: InstallCertCheck();
;Source: "..\ssl\*"; DestDir: "{app}\ssl"; Tasks: installCertificates; Flags: createallsubdirs recursesubdirs

[Setup]
OutputBaseFilename=waptsetup
DefaultDirName={pf32}\wapt
WizardImageFile=..\tranquilit.bmp
DisableProgramGroupPage=yes

[Languages]
Name:"en"; MessagesFile: "compiler:Default.isl"
Name:"fr";MessagesFile: "compiler:Languages\French.isl"
Name:"de";MessagesFile: "compiler:Languages\German.isl"

[Tasks]
;Name: installCertificates; Description: "{cm:InstallSSLCertificates}";  GroupDescription: "Base";

[INI]
Filename: {app}\wapt-get.ini; Section: global; Key: wapt_server; String: {code:GetWaptServerURL}; 
Filename: {app}\wapt-get.ini; Section: global; Key: repo_url; String: {code:GetRepoURL};
Filename: {app}\wapt-get.ini; Section: global; Key: use_hostpackages; String: "1"; 
Filename: {app}\wapt-get.ini; Section: global; Key: send_usage_report; String:  {#send_usage_report}; 

[Run]
Filename: "{app}\wapt-get.exe"; Parameters: "--direct register"; Flags: runasoriginaluser runhidden postinstall; StatusMsg: StatusMsg: {cm:RegisterHostOnServer}; Description: "{cm:RegisterHostOnServer}"
Filename: "{app}\wapt-get.exe"; Parameters: "--direct update"; Flags: runasoriginaluser runhidden postinstall; StatusMsg: {cm:UpdateAvailablePkg}; Description: "{cm:UpdateAvailablePkg}"
Filename: "{app}\wapt-get.exe"; Parameters: "add-upgrade-shutdown"; Flags: runhidden; StatusMsg: {cm:UpdatePkgUponShutdown}; Description: "{cm:UpdatePkgUponShutdown}"

[Icons]
Name: "{commonstartup}\WAPT session setup"; Filename: "{app}\wapt-get.exe"; Parameters: "session-setup ALL"; Flags: runminimized excludefromshowinnewinstall;
Name: "{group}\Console WAPT"; Filename: "{app}\waptconsole.exe"; WorkingDir: "{app}" ; Check: IsWaptAgent();

[CustomMessages]
;English translations here
en.StartAfterSetup=Launch WAPT setup session upon session opening
en.RegisterHostOnServer=Register this computer onto WAPT server
en.UpdateAvailablePkg=Update the list of packages available on the main repository
en.UpdatePkgUponShutdown=Update packages upon shutdown
en.EnableCheckCertificate=Get and enable the check of WaptServer https certificate
en.UseWaptServer=Report computer status to a waptserver and enable remote management
en.InstallSSLCertificates=Install the certificates provided by this installer

;French translations here
fr.StartAfterSetup=Lancer WAPT session setup à l'ouverture de session
fr.RegisterHostOnServer=Enregistre l'ordinateur sur le serveur WAPT
fr.UpdateAvailablePkg=Mise à jour des paquets disponibles sur le dépôt principal
fr.UpdatePkgUponShutdown=Mise à jour des paquets à l'extinction du poste
fr.EnableCheckCertificate=Activer la vérification du certificat https du serveur Wapt
fr.UseWaptServer=Activer l'utilisation d'un serveur Wapt et la gestion centralisée de cet ordinateur
fr.InstallSSLCertificates=Installer les certificats fournis par cet installeur.

;German translation here
de.StartAfterSetup=WAPT Setup-Sitzung bei Sitzungseröffnung starten
de.RegisterHostOnServer=Diesen Computer auf WAPT Server speichern
de.UpdateAvailablePkg=Liste der verfügbaren Pakete auf Main Repostitory aktualisieren
de.UpdatePkgUponShutdown=Packete aktualisieren beim herunterfahren

[Code]
var
  rbStaticUrl,rbDnsServer: TNewRadioButton;
  CustomPage: TWizardPage;
  teWaptServerUrl:TEdit;
  TLabelRepo,TLabelServer: TLabel;

procedure OnServerClicked(Sender:TObject);
begin
   teWaptServerUrl.Enabled:= not rbDnsServer.Checked;
   teWaptRepoUrl.Enabled:= not rbDnsServer.Checked;
end;

function GetRepoURL(Param:String):String;
begin
  if rbDnsServer.Checked and not rbStaticUrl.Checked then
    result := ''
  else
  if teWaptRepoUrl.Text <> 'unknown' then
    result := teWaptRepoUrl.Text
  else
  begin
    result := ExpandConstant('{param:repo_url|unknown}');
    if result='unknown' then
      result := GetIniString('Global', 'repo_url','{#default_repo_url}', ExpandConstant('{app}\wapt-get.ini'))
  end;
end;

function GetWaptServerURL(Param: String):String;
begin
  if rbDnsServer.Checked and not rbStaticUrl.Checked then
    result := ''
  else
  if teWaptServerURL.Text <> 'unknown' then
    result := teWaptServerURL.Text
  else
  begin
    result := ExpandConstant('{param:wapt_server|unknown}');
    if result='unknown' then
      result := GetIniString('Global', 'wapt_server','{#default_wapt_server}', ExpandConstant('{app}\wapt-get.ini'));
  end;
end;

procedure RemoveWaptServer();
begin
  DeleteIniEntry('Global','wapt_server',ExpandConstant('{app}\wapt-get.ini'));
end;

procedure InitializeWizard;
begin
  CustomPage := CreateCustomPage(wpSelectTasks, 'Installation options', '');
  
  rbDnsServer := TNewRadioButton.Create(WizardForm);
  rbDnsServer.Parent := CustomPage.Surface;
  rbDnsServer.Width := CustomPage.SurfaceWidth;
  rbDnsServer.Caption := 'Detect WAPT Info with DNS records';
  rbDnsServer.Onclick := @OnServerClicked;

  rbStaticUrl := TNewRadioButton.Create(WizardForm);
  rbStaticUrl.Parent := CustomPage.Surface; 
  rbStaticUrl.Caption := 'Static WAPT Info';
  rbStaticUrl.Top := rbStaticUrl.Top + rbDnsServer.Height + 3 * ScaleY(15);
  rbStaticUrl.Onclick := @OnServerClicked;

  TLabelRepo := TLabel.Create(WizardForm);
  TLabelRepo.Parent := CustomPage.Surface; 
  TLabelRepo.Left := rbStaticUrl.Left + 14;
  TLabelRepo.Caption := 'Repos URL:';
  TLabelRepo.Top := TLabelRepo.Top + rbDnsServer.Height + 5 * ScaleY(15);
  
  TLabelServer := TLabel.Create(WizardForm);
  TLabelServer.Parent := CustomPage.Surface; 
  TLabelServer.Left := rbStaticUrl.Left + 14; 
  TLabelServer.Caption := 'Server URL:';
  TLabelServer.Top := TLabelServer.Top + rbDnsServer.Height + 9 * ScaleY(15);

  teWaptRepoUrl := TEdit.Create(WizardForm);
  teWaptRepoUrl.Parent := CustomPage.Surface; 
  teWaptRepoUrl.Left :=TLabelRepo.Left + TLabelRepo.Width + 5;
  teWaptRepoUrl.Width :=CustomPage.SurfaceWidth - rbStaticUrl.Width;
  teWaptRepoUrl.Top := teWaptRepoUrl.Top + rbDnsServer.Height + 5 * ScaleY(15);
  teWaptRepoUrl.text := 'unknown';

  TLabelRepo := TLabel.Create(WizardForm);
  TLabelRepo.Parent := CustomPage.Surface; 
  TLabelRepo.Left := teWaptRepoUrl.Left + 5;
  TLabelRepo.Caption := 'example: http://srvwapt.domain.lan/wapt';
  TLabelRepo.Top := teWaptRepoUrl.Top + teWaptRepoUrl.Height + ScaleY(2);


  teWaptServerUrl := TEdit.Create(WizardForm);;
  teWaptServerUrl.Parent := CustomPage.Surface; 
  teWaptServerUrl.Left :=TLabelServer.Left + TLabelServer.Width+5;
  teWaptServerUrl.Width :=CustomPage.SurfaceWidth - rbStaticUrl.Width;
  teWaptServerUrl.Top := teWaptServerUrl.Top + teWaptRepoUrl.Height + 9 * ScaleY(15); 
  teWaptServerUrl.Text := 'unknown';  

  TLabelServer := TLabel.Create(WizardForm);
  TLabelServer.Parent := CustomPage.Surface; 
  TLabelServer.Left := teWaptServerUrl.Left + 5; 
  TLabelServer.Caption := 'example: https://srvwapt.domain.lan';
  TLabelServer.Top := teWaptServerUrl.Top + teWaptServerUrl.Height + ScaleY(2);


end;


procedure DeinitializeUninstall();
var
    installdir: String;
begin
    installdir := ExpandConstant('{app}');
    if DirExists(installdir) then
    begin
      if (not runningSilently() and  (MsgBox('Des fichiers restent présents dans votre répertoire ' + installdir + ', souhaitez-vous le supprimer ainsi que tous les fichiers qu''il contient ?',
               mbConfirmation, MB_YESNO) = IDYES))
               
         or (ExpandConstant('{param:purge_wapt_dir|0}')='1') then
        Deltree(installdir, True, True, True);
    End;
end;


procedure CurPageChanged(CurPageID: Integer);
var
  WaptRepo: String;
  WaptServer: String;
begin
  if curPageId=customPage.Id then
  begin
    teWaptRepoUrl.Text := GetRepoURL('');
    teWaptServerUrl.Text := GetWaptServerURL('');  
    rbDnsServer.Checked := (teWaptRepoUrl.Text='');
    rbStaticUrl.Checked := (teWaptRepoUrl.Text<>'') and (teWaptRepoUrl.Text<>'unknown');

	//teWaptServerUrl.Visible := IsTaskSelected('use_waptserver');
    //TLabelServer.Visible := teWaptServerUrl.Visible;
  end
end;

function InstallCertCheck:Boolean;
begin
	Result := {#install_certs} <> 0;
end;

function IsWaptAgent:Boolean;
begin
	Result := {#is_waptagent} <> 0;
end;

