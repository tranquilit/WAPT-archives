unit uvisloading;

{$mode objfpc}{$H+}

interface

uses
  Classes, SysUtils, FileUtil, Forms, Controls, Graphics, Dialogs, ComCtrls,
  ExtCtrls, StdCtrls, Buttons, DefaultTranslator;

type

  EStopRequest = class(Exception);

  { TVisLoading }

  TVisLoading = class(TForm)
    BitBtn1: TBitBtn;
    AMessage: TLabel;
    AProgressBar: TProgressBar;
    procedure BitBtn1Click(Sender: TObject);
    procedure FormCreate(Sender: TObject);
  private
    { private declarations }
  public
    { public declarations }
    StopRequired : Boolean;
    OnStop :TNotifyEvent;
    ExceptionOnStop:Boolean;
    function ProgressForm:TVisLoading;
    procedure ProgressTitle(Title:String);
    procedure ProgressStep(step,max:integer);
    procedure Start(Max:Integer=100);
    procedure Finish;
    procedure DoProgress(Sender:TObject);
  end;

  procedure ShowLoadWait(Msg:String;Progress:Integer=0;MaxProgress:Integer = 100);
  procedure ShowProgress(Msg:String;Progress:Integer=0);
  procedure HideLoadWait;

var
  VisLoading: TVisLoading;

implementation
uses uWaptConsoleRes,uScaleDPI;

procedure ShowLoadWait(Msg: String; Progress: Integer; MaxProgress: Integer);
begin
  if VisLoading = Nil then
      VisLoading := TVisLoading.Create(Application);
  VisLoading.Show;
  VisLoading.ProgressStep(Progress,MaxProgress);
  VisLoading.ProgressTitle(Msg);
end;

procedure ShowProgress(Msg: String; Progress: Integer);
begin
  VisLoading.ProgressTitle(Msg);
  VisLoading.ProgressStep(Progress,VisLoading.AProgressBar.Max);;
end;

procedure HideLoadWait;
begin
  if VisLoading<> Nil then
  begin
    VisLoading.Finish;
    VisLoading.Close;
  end;
end;

{$R *.lfm}

{ TVisLoading }

procedure TVisLoading.BitBtn1Click(Sender: TObject);
begin
  StopRequired:=True;
  if Assigned(OnStop) then
    OnStop(Self);
end;

procedure TVisLoading.FormCreate(Sender: TObject);
begin
  ScaleDPI(Self,96); // 96 is the DPI you designed
  AProgressBar.Min:=0;
end;

function TVisLoading.ProgressForm: TVisLoading;
begin
  result := Self;
end;

procedure TVisLoading.ProgressTitle(Title: String);
begin
  AMessage.Caption := Title;
  Application.ProcessMessages;
  ShowOnTop;
end;

procedure TVisLoading.ProgressStep(step, max: integer);
begin
  if Step <= 0 then
      StopRequired:=False;
  AProgressBar.Max:=Max;
  AProgressBar.position:=step;
  ShowOnTop;
  Application.ProcessMessages;
end;

procedure TVisLoading.Start(Max: Integer);
begin
  AProgressBar.position:=0;
  AProgressBar.Max:=Max;
  ShowOnTop;
  Application.ProcessMessages;
end;

procedure TVisLoading.Finish;
begin
  AProgressBar.position:=AProgressBar.Max;
  ShowOnTop;
  Application.ProcessMessages;
end;

procedure TVisLoading.DoProgress(Sender: TObject);
begin
  if StopRequired and ExceptionOnStop then
    Raise EStopRequest.CreateFmt(rsCanceledByUser,[AMessage.Caption]);

  if AProgressBar.position >= AProgressBar.Max then
      AProgressBar.position := AProgressBar.Min
  else
    AProgressBar.position := AProgressBar.position+1;
  ShowOnTop;
  Application.ProcessMessages;
end;

end.

