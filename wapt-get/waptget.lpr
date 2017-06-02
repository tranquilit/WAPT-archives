program waptget;
{ -----------------------------------------------------------------------
#    This file is part of WAPT
#    Copyright (C) 2013  Tranquil IT Systems http://www.tranquil.it
#    WAPT aims to help Windows systems administrators to deploy
#    setup and update applications on users PC.
#
#    WAPT is free software: you can redistribute it and/or modify
#    it under the terms of the GNU General Public License as published by
#    the Free Software Foundation, either version 3 of the License, or
#    (at your option) any later version.
#
#    WAPT is distributed in the hope that it will be useful,
#    but WITHOUT ANY WARRANTY; without even the implied warranty of
#    MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
#    GNU General Public License for more details.
#
#    You should have received a copy of the GNU General Public License
#    along with WAPT.  If not, see <http://www.gnu.org/licenses/>.
#
# -----------------------------------------------------------------------
}

{$mode delphiunicode}
{.$mode objfpc}{$H+}

uses
  {$IFDEF UNIX}{$IFDEF UseCThreads}
  cthreads,
  {$ENDIF}{$ENDIF}
  Classes, SysUtils, CustApp,
  { you can add units after this }
  Interfaces,Windows, PythonEngine, zmqapi, superobject,soutils,
  tislogging,uWaptRes,waptcommon,waptwinutils,tiscommon,tisstrings,IdAuthentication;
type
  { pwaptget }

  pwaptget = class(TCustomApplication)
  private
    localuser,localpassword:AnsiString;
    FRepoURL: String;
    function GetRepoURL: String;
    procedure HTTPLogin(Sender: TObject; Authentication: TIdAuthentication; var Handled: Boolean);
    procedure SetRepoURL(AValue: String);
  protected
    APythonEngine: TPythonEngine;
    procedure DoRun; override;
  public
    Action : String;
    check_thread:TThread;
    lock:TRTLCriticalSection;
    tasks:ISuperObject;
    lastMessageTime : TDateTime;
    constructor Create(TheOwner: TComponent); override;
    destructor Destroy; override;
    procedure WriteHelp; virtual;
    property RepoURL:String read GetRepoURL write SetRepoURL;
    procedure pollerEvent(message:TStringList);
    function remainingtasks:ISuperObject;
  end;



  { TZMQPollThread }
  TZMQPollThread = Class(TThread)
    procedure HandleMessage;

  public
    PollTimeout:Integer;
    zmq_context:TZMQContext;
    zmq_socket :TZMQSocket;

    message : TStringList;
    msg:Utf8String;
    app:pwaptget;

    constructor Create(anapp:pwaptget);
    destructor Destroy; override;
    procedure Execute; override;
end;

{ TZMQPollThread }

procedure TZMQPollThread.HandleMessage;
begin
  if Assigned(app) then
    app.pollerEvent(message);
end;

constructor TZMQPollThread.Create(anapp:pwaptget);
begin
  inherited Create(True);
  message := TStringList.Create;
  app := anapp;
  // create ZMQ context.
  zmq_context := TZMQContext.Create;

  zmq_socket := zmq_context.Socket( stSub );
  zmq_socket.RcvHWM:= 1000001;
  Logger('Connecting to Waptservice event queue...',DEBUG);
  zmq_socket.connect( 'tcp://127.0.0.1:5000' );
  zmq_socket.Subscribe('');
  Logger('Connected to Waptservice event queue',DEBUG);
end;

destructor TZMQPollThread.Destroy;
begin
  message.Free;
  Logger('Leaving Waptservice event queue',DEBUG);
  if Assigned(zmq_socket) then
    FreeAndNil(zmq_socket);
  if Assigned(zmq_context) then
    FreeAndNil(zmq_context);

  inherited Destroy;
end;

procedure TZMQPollThread.Execute;
var
  res : integer;
  part:Utf8String;
begin
  try
    while not Terminated and not  zmq_socket.context.Terminated do
    begin
      res := zmq_socket.recv(msg);
      while zmq_socket.RcvMore do
      begin
        res := zmq_socket.recv(part);
        msg:=msg+#13#10+part;
      end;
      message.Text:=msg;
      HandleMessage;
      if zmq_socket.context.Terminated then
      begin
        Writeln(utf8decode(rsWinterruptReceived));
        break;
      end;
    end;
  finally
    writeln(utf8decode(rsStopListening));
  end;
end;


{ pwaptget }

var
  Application: pwaptget;

  function GetPassword(const InputMask: Char = '*'): string;
  var
    OldMode: Cardinal;
    c: char;
  begin
    Result:='';
    GetConsoleMode(GetStdHandle(STD_INPUT_HANDLE), OldMode);
    SetConsoleMode(GetStdHandle(STD_INPUT_HANDLE), OldMode and not (ENABLE_LINE_INPUT or ENABLE_ECHO_INPUT));
    try
      while not Eof do
      begin
        Read(c);
        if c = #13 then // Carriage Return
          Break;
        if (c = #8) then  // Back Space
        begin
          if (Length(Result) > 0) then
          begin
            Delete(Result, Length(Result), 1);
            Write(#8);
          end;
        end
        else
        begin
          Result := Result + c;
          Write(InputMask);
        end;
      end;
    finally
      SetConsoleMode(GetStdHandle(STD_INPUT_HANDLE), OldMode);
    end;
  end;

procedure pwaptget.HTTPLogin(Sender: TObject; Authentication: TIdAuthentication; var Handled: Boolean);
var
  newuser:AnsiString;
begin
  if (localuser<>'') and (localpassword<>'') then
  begin
    Authentication.Username:=localuser;
    Authentication.Password:=localpassword;
  end
  else
  begin
    Write('Waptservice User ('+localuser+') :');
    readln(newuser);
    if newuser<>'' then
      Authentication.Username:=newuser;
    if Authentication.Username='' then
      raise Exception.Create('Empty user');
    Write('Password: ');
    Authentication.Password := GetPassword;
    WriteLn;
    Handled := (Authentication.Password='');
    // cache for next use
    localuser := Authentication.Username;
    localpassword := Authentication.Password;
  end;
end;

function pwaptget.GetRepoURL: String;
begin
  if FRepoURL='' then
    FRepoURL:=GetMainWaptRepo;
  result := FRepoURL;
end;

procedure pwaptget.SetRepoURL(AValue: String);
begin
  if FRepoURL=AValue then Exit;
  FRepoURL:=AValue;
end;

procedure pwaptget.DoRun;
var
  MainModule : TStringList;
  logleveloption : String;
  Res,task:ISuperobject;
  package,sopackages:ISuperObject;

  procedure SetFlag( AFlag: PInt; AValue : Boolean );
  begin
    if AValue then
      AFlag^ := 1
    else
      AFlag^ := 0;
  end;

var
  i:integer;
  NextIsParamValue:Boolean;
begin
  Action:='';
  sopackages  := TSuperObject.Create(stArray);

  NextIsParamValue := False;

  for i:=1 to ParamCount do
  begin
    if (Pos('-',Params[i])<>1) and not NextIsParamValue then
    begin
      if (action='') then
        Action := lowercase(Params[i])
      else
        sopackages.AsArray.Add(Params[i]);
      NextIsParamValue := False;
    end
    else
      NextIsParamValue := StrIsOneOf(Params[i],['-c','-r','-l','-p','-s','-e','-k','-w','-U','-g','-t','-L'])
  end;

  // parse parameters
  if HasOption('?') or HasOption('h','help') then
  begin
    writeln(utf8decode(rsOptRepo));
    writeln(utf8decode(rsWaptgetHelp));
  end;

  if HasOption('c','config') then
    ReadWaptConfig(GetOptionValue('c','config'))
  else
    ReadWaptConfig();

  if HasOption('r','repo') then
    RepoURL := GetOptionValue('r','repo');

  if HasOption('l','loglevel') then
  begin
    logleveloption := UpperCase(GetOptionValue('l','loglevel'));
    if logleveloption = 'DEBUG' then
      currentLogLevel := DEBUG
    else if logleveloption = 'INFO' then
      currentLogLevel := INFO
    else if logleveloption = 'WARNING' then
      currentLogLevel := WARNING
    else if logleveloption = 'ERROR' then
      currentLogLevel := ERROR
    else if logleveloption = 'CRITICAL' then
      currentLogLevel := CRITICAL;
    Logger('Current loglevel : '+StrLogLevel[currentLogLevel],DEBUG);
  end;

  if HasOption('v','version') then
    writeln(format(rsWin32exeWrapper, [ApplicationName, GetApplicationVersion]));

  if (action = 'waptupgrade') then
  begin
    Writeln(format(rsWaptGetUpgrade, [RepoURL]));
    UpdateApplication(RepoURL+'/waptagent.exe','waptagent.exe','/VERYSILENT','wapt-get.exe','');
    Terminate;
    Exit;
  end
  else
  if (action = 'dnsdebug') then
  begin
    WriteLn(format(rsDNSserver, [Join(',',GetDNSServers)]));
    WriteLn(format(rsDNSdomain, [GetDNSDomain]));
    Writeln(utf8decode(format(rsMainRepoURL, [RepoURL])));
    Writeln(format(rsSRV, [DNSSRVQuery('_wapt._tcp.'+GetDNSDomain).AsJSon(True)]));
    Writeln(format(rsCNAME, [DNSCNAMEQuery('wapt.'+GetDNSDomain).AsJSon(True)]));
    Terminate;
    Exit;
  end
  else
  // use http service mode if --service or not --direct or not (--service and isadmin
  if  ((not IsAdminLoggedOn or HasOption('S','service')) and not HasOption('D','direct')) and
      StrIsOneOf(action,['update','upgrade','register','install','remove','forget','longtask','cancel','cancel-all','tasks','wuascan','wuadownload','wuainstall']) and
      CheckOpenPort(waptservice_port,'127.0.0.1',waptservice_timeout) then
  begin
    writeln('About to speak to waptservice...');
    // launch task in waptservice, waits for its termination
    check_thread :=TZMQPollThread.Create(Self);
    check_thread.Start;
    tasks := TSuperObject.create(stArray);
    try
      try
        res := Nil;
        //test longtask
        if action='longtask' then
        begin
          Logger('Call longtask URL...',DEBUG);
          res := WAPTLocalJsonGet('longtask.json');
          if res = Nil then
            WriteLn(utf8decode((format(rsLongtaskError, [res.S['message']]))))
          else
            tasks.AsArray.Add(res);
          Logger('Task '+res.S['id']+' added to queue',DEBUG);
        end
        else
        if action='tasks' then
        begin
          res := WAPTLocalJsonGet('tasks.json');
          if res = Nil then
            WriteLn(utf8decode(format(rsTaskListError, [res.S['message']])))
          else
          begin
            if res['running'].DataType<>stNull then
              writeln(utf8decode(format(rsRunningTask,[ res['running'].I['id'],res['running'].S['description'],res['running'].S['runstatus']])))
            else
              writeln(utf8decode(rsNoRunningTask));
            if res['pending'].AsArray.length>0 then
              writeln(utf8decode(rsPending));
              for task in res['pending'] do
                writeln(utf8decode('  '+task.S['id']+' '+task.S['description']));
          end;
        end
        else
        if action='cancel' then
        begin
          res := WAPTLocalJsonGet('cancel_running_task.json');
          if res = Nil then
            WriteLn(utf8decode(format(rsErrorCanceling, [res.S['message']])))
          else
            if res.DataType<>stNull then
              writeln(utf8decode(format(rsCanceledTask, [res.S['description']])))
            else
              writeln(rsNoRunningTask);
        end
        else
        if (action='cancel-all') or (action='cancelall') then
        begin
          res := WAPTLocalJsonGet('cancel_all_tasks.json');
          if res = Nil then
            WriteLn(utf8decode(format(rsErrorCanceling, [res.S['message']])))
          else
            if res.DataType<>stNull then
            begin
              for task in res do
                writeln(utf8decode(format(rsCanceledTask, [task.S['description']])))
            end
            else
              writeln(utf8decode(rsNoRunningTask));
        end
        else
        if action='update' then
        begin
          Logger('Call update URL...',DEBUG);
          if HasOption('f','force') then
            res := WAPTLocalJsonGet('update.json?notify_user=0&force=1')
          else
            res := WAPTLocalJsonGet('update.json?notify_user=0');
          if res = Nil then
            WriteLn(utf8decode(format(rsErrorLaunchingUpdate, [res.S['message']])))
          else
            tasks.AsArray.Add(res);
          Logger('Task '+res.S['id']+' added to queue',DEBUG);
        end
        else
        if action='register' then
        begin
          Logger('Call register URL...',DEBUG);
          res := WAPTLocalJsonGet('register.json?notify_user=0&notify_server=1','admin','',1000,HTTPLogin);
          if (res = Nil) or (res.AsObject=Nil) or not res.AsObject.Exists('id') then
            WriteLn(utf8decode(format(rsErrorLaunchingRegister, [res.AsString])))
          else
            tasks.AsArray.Add(res);
          Logger('Task '+res.S['id']+' added to queue',DEBUG);
        end
        else
        if (action='install') or (action='remove') or (action='forget') then
        begin
          for package in sopackages do
          begin
            Logger('Call '+action+'?package='+package.AsString,DEBUG);
            if HasOption('f','force') then
              res := WAPTLocalJsonGet(Action+'.json?package='+package.AsString+'&force=1&notify_user=0','admin','',1000,HTTPLogin)
            else
              res := WAPTLocalJsonGet(Action+'.json?package='+package.AsString+'&notify_user=0','admin','',1000,HTTPLogin);
            if (action='install') or (action='forget')  then
            begin
              // single action
              if (res = Nil) or (res.AsObject=Nil) or not res.AsObject.Exists('id') then
                WriteLn(utf8decode(format(rsErrorWithMessage, [res.AsString])))
              else
                tasks.AsArray.Add(res);
            end
            else
            if (action='remove') then
            begin
              // list of actions..
              if (res = Nil) or (res.AsArray=Nil) then
                WriteLn(utf8decode(format(rsErrorWithMessage, [res.AsString])))
              else
              for task in res do
              begin
                tasks.AsArray.Add(task);
                Logger('Task '+task.S['id']+' added to queue',DEBUG);
              end;
            end;
          end;
        end
        else if action='upgrade' then
        begin
          Logger('Call upgrade URL...',DEBUG);
          res := WAPTLocalJsonGet('upgrade.json?notify_user=0');
          if res.S['result']<>'OK' then
            WriteLn(utf8decode(format(rsErrorLaunchingUpgrade, [res.S['message']])))
          else
            for task in res['content'] do
            begin
              tasks.AsArray.Add(task);
              Logger('Task '+task.S['id']+' added to queue',DEBUG);
            end;
        end
        else
        if action='wuascan' then
        begin
          res := WAPTLocalJsonGet('waptwua_scan?notify_user=1');
          if res = Nil then
            WriteLn(utf8decode(format(rsErrorLaunchingUpdate, [res.S['message']])))
          else
            tasks.AsArray.Add(res);
          Logger('Task '+res.S['id']+' added to queue',DEBUG);
        end
        else
        if action='wuadownload' then
        begin
          res := WAPTLocalJsonGet('waptwua_download?notify_user=1');
          if res = Nil then
            WriteLn(utf8decode(format(rsErrorLaunchingUpdate, [res.S['message']])))
          else
            tasks.AsArray.Add(res);
          Logger('Task '+res.S['id']+' added to queue',DEBUG);
        end
        else
        if action='wuainstall' then
        begin
          res := WAPTLocalJsonGet('waptwua_install?notify_user=1');
          if res = Nil then
            WriteLn(utf8decode(format(rsErrorLaunchingUpdate, [res.S['message']])))
          else
            tasks.AsArray.Add(res);
          Logger('Task '+res.S['id']+' added to queue',DEBUG);
        end;

        while (tasks.AsArray.Length > 0) and not (Terminated) and not check_thread.Finished do
        try
          //if no message from service since more that 1 min, check if remaining tasks in queue...
          if (now-lastMessageTime>1*1/24/60) and (remainingtasks.AsArray.Length=0) then
            raise Exception.create('Timeout waiting for events')
          else
          begin
            Sleep(1000);
            write('.');
          end;
        except
          writeln(rsCanceled);
          for task in tasks do
              WAPTLocalJsonGet('cancel_task.json?id='+task.S['id']);
        end;
      except
        localpassword := '';
        ExitCode:=3;
        raise;
      end;
    finally
      for task in tasks do
          WAPTLocalJsonGet('cancel_task.json?id='+task.S['id']);
      if Assigned(check_thread) then
      begin
        TerminateThread(check_thread.Handle,0);
        FreeAndNil(check_thread);
      end;
    end;
  end
  else
  begin
    // Running python stuff
    APythonEngine := TPythonEngine.Create(Self);
    with ApythonEngine do
    begin
      DllName := 'python27.dll';
      //APIVersion := 1013;
      RegVersion := '2.7';
      UseLastKnownVersion := False;
      Initialize;
      Py_SetProgramName(PAnsiChar(ParamStr(0)));
      SetFlag(Py_VerboseFlag,     False);
      SetFlag(Py_InteractiveFlag, True);
      SetFlag(Py_NoSiteFlag,      True);
      SetFlag(Py_IgnoreEnvironmentFlag, True);
    end;

    // Load main python application
    try
      MainModule:=TStringList.Create;
      MainModule.LoadFromFile(ExtractFilePath(ParamStr(0))+'wapt-get.py');
      APythonEngine.ExecStrings(MainModule);
    finally
      MainModule.Free;
    end;
  end;

  // stop program loop
  Terminate;
end;

constructor pwaptget.Create(TheOwner: TComponent);
begin
  inherited Create(TheOwner);
  StopOnException:=True;
  InitializeCriticalSection(lock);

end;

destructor pwaptget.Destroy;
begin
  if Assigned(APythonEngine) then
    APythonEngine.Free;
  DeleteCriticalSection(lock);
  inherited Destroy;
end;

procedure pwaptget.WriteHelp;
begin
  { add your help code here }
  writeln(utf8decode(format(rsUsage, [ExeName])));
  writeln(rsInstallOn);
end;

procedure pwaptget.pollerEvent(message: TStringList);
var
  msg:ISuperobject;
  status:String;

  //check if task with id id is in tasks list
  function isInTasksList(id:integer):boolean;
  var
    t:ISuperObject;
  begin
    //writeln('check '+IntToStr(id)+' in '+tasks.AsJSon());
    result := False;
    for t in tasks do
      if t.I['id'] = id then
      begin
        result := True;
        break;
      end;
  end;

  //remove task with id id from tasks list
  procedure removeTask(id:integer);
  var
    i:integer;
  begin
    for i:=0 to tasks.AsArray.Length-1 do
      if tasks.AsArray[i].I['id'] = id then
      begin
        tasks.AsArray.Delete(i);
        break;
      end;
  end;

begin
  EnterCriticalSection(lock);
  try
    //writeln(message.Text);
    //display messages if event task is in my list

    lastMessageTime := Now;

    if message[0]='TASKS' then
    begin
      status := message[1];
      msg := SO(message[2]);
      //writeln(msg.asJson());
      if isInTasksList(msg.I['id']) then
      begin
        if (status = 'START') then
          writeln(msg.S['description']);
        if (status = 'PROGRESS') then
          write(utf8decode(format(rsCompletionProgress,[msg.S['runstatus'], msg.D['progress']])+#13));
        //catch finish of task
        if (status = 'FINISH') or (status = 'ERROR') or (status = 'CANCEL') then
        begin
          removeTask(msg.I['id']);
          WriteLn(msg.S['summary']);
          if (status = 'ERROR') or (status = 'CANCEL') then
            ExitCode:=3;
        end;
      end;
    end
  finally
    LeaveCriticalSection(lock);
  end;
end;

function pwaptget.remainingtasks: ISuperObject;
var
  res:ISuperObject;
begin
  res := WAPTLocalJsonGet('tasks.json');
  Result := res['pending'];
  if res['running'] <> Nil then
    Result.AsArray.Add(res['running']);
end;

{$R *.res}

begin
  Application:=pwaptget.Create(nil);
  Application.Title:='wapt-get';
  Application.Run;
  Application.Free;
end.

