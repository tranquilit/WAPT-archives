unit uvislogin;

{$mode objfpc}{$H+}

interface

uses
  Classes, SysUtils, FileUtil, Forms, Controls, Graphics, Dialogs, StdCtrls,
  ExtCtrls, Buttons, ButtonPanel, LCLType,uwaptconsole,waptcommon, DefaultTranslator;

type

  { TVisLogin }

  TVisLogin = class(TForm)
    BitBtn1: TBitBtn;
    ButtonPanel1: TButtonPanel;
    edPassword: TEdit;
    edUser: TEdit;
    edWaptServerName: TEdit;
    labServer: TLabel;
    laPassword: TLabel;
    labUser: TLabel;
    procedure BitBtn1Click(Sender: TObject);
    procedure edPasswordKeyDown(Sender: TObject; var Key: Word;
      Shift: TShiftState);
    procedure FormShow(Sender: TObject);
  private
    { private declarations }
  public
    { public declarations }
  end;

var
  VisLogin: TVisLogin;

implementation

{$R *.lfm}

{ TVisLogin }

procedure TVisLogin.edPasswordKeyDown(Sender: TObject; var Key: Word;
  Shift: TShiftState);
begin
    if Key = VK_RETURN then
  begin
    edPassword.SelectAll;
  end;
end;

procedure TVisLogin.FormShow(Sender: TObject);
begin
  if edUser.Text<>'' then
    edPassword.SetFocus;
end;

procedure TVisLogin.BitBtn1Click(Sender: TObject);
begin
  if VisWaptGUI.EditIniFile then
  begin
    VisWaptGUI.ActReloadConfig.Execute;
    edWaptServerName.Text:=waptcommon.GetWaptServerURL;
  end;
end;

end.

