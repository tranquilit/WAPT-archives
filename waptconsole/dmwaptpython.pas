unit dmwaptpython;

{$mode objfpc}{$H+}

interface

uses
  Classes, SysUtils, FileUtil,LazFileUtils, PythonEngine, PythonGUIInputOutput, VarPyth,
  vte_json, superobject, fpjson, jsonparser, DefaultTranslator,WrapDelphi;

type

  { TDMPython }

  TDMPython = class(TDataModule)
    PythonEng: TPythonEngine;
    PythonModuleDMWaptPython: TPythonModule;
    PythonOutput: TPythonGUIInputOutput;
    procedure DataModuleCreate(Sender: TObject);
    procedure DataModuleDestroy(Sender: TObject);
    procedure PythonModule1Events0Execute(Sender: TObject; PSelf,
      Args: PPyObject; var Result: PPyObject);
  private
    FLanguage: String;
    FCachedPrivateKeyPassword: Ansistring;
    jsondata:TJSONData;

    FWaptConfigFileName: Utf8String;
    function getprivateKeyPassword: Ansistring;
    procedure LoadJson(data: UTF8String);
    procedure setprivateKeyPassword(AValue: Ansistring);
    procedure SetWaptConfigFileName(AValue: Utf8String);
    procedure SetLanguage(AValue: String);

    { private declarations }
  public
    { public declarations }
    WAPT:Variant;
    PyWaptWrapper : TPyDelphiWrapper;

    property privateKeyPassword: Ansistring read getprivateKeyPassword write setprivateKeyPassword;

    property WaptConfigFileName:Utf8String read FWaptConfigFileName write SetWaptConfigFileName;
    function RunJSON(expr: UTF8String; jsonView: TVirtualJSONInspector=
      nil): ISuperObject;

    property Language:String read FLanguage write SetLanguage;
  end;


  function CreateSignedCert(keyfilename,
          crtbasename,
          wapt_base_dir,
          destdir,
          country,
          locality,
          organization,
          orgunit,
          commonname,
          email,
          keypassword:String;
          codesigning:Boolean;
          IsCACert:Boolean;
          CACertificateFilename:String='';
          CAKeyFilename:String=''
      ):String;


  function pyObjectToSuperObject(pvalue:PPyObject):ISuperObject;
  function PyVarToSuperObject(PyVar:Variant):ISuperObject;


  function SuperObjectToPyObject(aso:ISuperObject):PPyObject;
  function SuperObjectToPyVar(aso:ISuperObject):Variant;

var
  DMPython: TDMPython;

implementation
uses variants, waptcommon, uvisprivatekeyauth,inifiles,forms,controls,Dialogs;
{$R *.lfm}

function pyObjectToSuperObject(pvalue:PPyObject):ISuperObject;
var
  i,j,k: Integer;
  pyKeys,pyKey,pyValue: PPyObject;
begin
  if GetPythonEngine.PyUnicode_Check(pvalue) or GetPythonEngine.PyString_Check(pvalue) then
    Result := TSuperObject.Create(GetPythonEngine.PyString_AsDelphiString(pvalue))
  else if GetPythonEngine.PyInt_Check(pvalue) then
    Result := TSuperObject.Create(GetPythonEngine.PyInt_AsLong(pvalue))
  else if GetPythonEngine.PyFloat_Check(pvalue) then
    Result := TSuperObject.Create(GetPythonEngine.PyFloat_AsDouble(pvalue))
  else if GetPythonEngine.PyList_Check(pvalue) then
  begin
    Result := TSuperObject.Create(stArray);
    for k := 0 to GetPythonEngine.PyList_Size(pvalue) - 1 do
        Result.AsArray.Add(pyObjectToSuperObject(GetPythonEngine.PyList_GetItem(pvalue,k)));
  end
  else if GetPythonEngine.PyDict_Check(pvalue) then
  begin
    Result := TSuperObject.Create(stObject);
    pyKeys := GetPythonEngine.PyDict_Keys(pvalue);
    j := 0;
    pyKey := Nil;
    pyValue := Nil;
    while GetPythonEngine.PyDict_Next(pvalue,@j,@pyKey,@pyValue) <> 0 do
      Result[GetPythonEngine.PyObjectAsString(pyKey)] := pyObjectToSuperObject(pyvalue);
  end
  else if pvalue = GetPythonEngine.Py_None then
    Result := TSuperObject.Create(stNull)
  else
    Result := TSuperObject.Create(GetPythonEngine.PyObjectAsString(pvalue));
end;

function PyVarToSuperObject(PyVar:Variant):ISuperObject;
begin
  Result := pyObjectToSuperObject(ExtractPythonObjectFrom(PyVar));
end;

function SuperObjectToPyObject(aso: ISuperObject): PPyObject;
var
  i:integer;
  _list : PPyObject;
  item: ISuperObject;
  key: ISuperObject;

begin
  case aso.DataType of
    stBoolean: begin
        if aso.AsBoolean then
          Result := PPyObject(GetPythonEngine.Py_True)
        else
          Result := PPyObject(GetPythonEngine.Py_False);
        GetPythonEngine.Py_INCREF(result);
    end;
    stNull: begin
        Result := GetPythonEngine.ReturnNone;
      end;
    stInt: begin
        Result := GetPythonEngine.PyInt_FromLong(aso.AsInteger);
      end;
    stDouble: begin
      Result := GetPythonEngine.PyFloat_FromDouble(aso.AsDouble);
      end;
    stString: begin
      Result := GetPythonEngine.PyUnicode_FromWideString(aso.AsString);
      end;
    stArray: begin
      Result := GetPythonEngine.PyList_New(aso.AsArray.Length);
      for item in aso do
          GetPythonEngine.PyList_Append(Result,SuperObjectToPyObject(item));
      end;
    stObject: begin
      Result := GetPythonEngine.PyDict_New();
      for key in Aso.AsObject.GetNames do
        GetPythonEngine.PyDict_SetItem(Result, SuperObjectToPyObject(key),SuperObjectToPyObject(Aso[key.AsString]));
    end
    else
      Result := GetPythonEngine.VariantAsPyObject(aso);
  end;
end;

function SuperObjectToPyVar(aso: ISuperObject): Variant;
begin
  result := VarPyth.VarPythonCreate(SuperObjectToPyObject(aso));
end;

procedure TDMPython.SetWaptConfigFileName(AValue: Utf8String);
var
  St:TStringList;
  ini : TInifile;
  i: integer;
begin
  if FWaptConfigFileName=AValue then
    Exit;

  FWaptConfigFileName:=AValue;
  if AValue<>'' then
  try
    Screen.Cursor:=crHourGlass;
    if not DirectoryExists(ExtractFileDir(AValue)) then
      mkdir(ExtractFileDir(AValue));
    //Initialize waptconsole parameters with local workstation wapt-get parameters...
    if not FileExistsUTF8(AValue) then
      CopyFile(Utf8ToAnsi(WaptIniFilename),Utf8ToAnsi(AValue),True);
    st := TStringList.Create;
    try
      st.Append('import logging');
      st.Append('import requests');
      st.Append('import json');
      st.Append('import os');
      st.Append('import common');
      st.Append('import waptpackage');
      st.Append('import waptdevutils');
      st.Append('import waptcrypto');
      st.Append('import setuphelpers');
      st.Append('from waptutils import jsondump');
      st.Append('logger = logging.getLogger()');
      st.Append('logging.basicConfig(level=logging.WARNING)');
      st.Append(format('mywapt = common.Wapt(config_filename=r"%s".decode(''utf8''),disable_update_server_status=True)',[AValue]));
      st.Append('mywapt.dbpath=r":memory:"');
      st.Append('mywapt.use_hostpackages = False');
      st.Append('import dmwaptpython');

      //st.Append('mywapt.update(register=False)');
      PythonEng.ExecStrings(St);
      WAPT:=MainModule.mywapt;
    finally
      st.free;
    end;
    // override lang setting
    for i := 1 to Paramcount - 1 do
      if (ParamStrUTF8(i) = '--LANG') or (ParamStrUTF8(i) = '-l') or
        (ParamStrUTF8(i) = '--lang') then
        begin
          waptcommon.Language := ParamStrUTF8(i + 1);
          waptcommon.FallBackLanguage := copy(waptcommon.Language,1,2);
          Language:=FallBackLanguage;
        end;

    // get from ini
    if Language = '' then
    begin
      ini := TIniFile.Create(FWaptConfigFileName);
      try
        waptcommon.Language := ini.ReadString('global','language','');
        waptcommon.FallBackLanguage := copy(waptcommon.Language,1,2);
        Language := waptcommon.Language;
      finally
        ini.Free;
      end;
    end;
  finally
    Screen.Cursor:=crDefault;
  end;
end;

procedure TDMPython.SetLanguage(AValue: String);
begin
  if FLanguage=AValue then Exit;
  FLanguage:=AValue;
  SetDefaultLang(FLanguage);
  if FLanguage='fr' then
    GetLocaleFormatSettings($1252, DefaultFormatSettings)
  else
    GetLocaleFormatSettings($409, DefaultFormatSettings);

end;

procedure TDMPython.DataModuleCreate(Sender: TObject);

begin
  with PythonEng do
  begin
    DllName := 'python27.dll';
    RegVersion := '2.7';
    UseLastKnownVersion := False;
    LoadDLL;
    Py_SetProgramName(PAnsiChar(ParamStr(0)));
  end;

  PyWaptWrapper := TPyDelphiWrapper.Create(Self);  // no need to destroy
  PyWaptWrapper.Engine := PythonEng;
  PyWaptWrapper.Module := PythonModuleDMWaptPython;
  PyWaptWrapper.Initialize;  // Should only be called if PyDelphiWrapper is created at run time

end;

procedure TDMPython.DataModuleDestroy(Sender: TObject);
begin
  if Assigned(jsondata) then
    FreeAndNil(jsondata);

end;

procedure TDMPython.PythonModule1Events0Execute(Sender: TObject; PSelf,
  Args: PPyObject; var Result: PPyObject);
begin
  ShowMessage(VarPythonCreate(Args).GetItem(0));
  Result :=  PythonEng.ReturnNone;
end;

function TDMPython.RunJSON(expr: UTF8String; jsonView: TVirtualJSONInspector=Nil): ISuperObject;
var
  res:UTF8String;
begin
  if Assigned(jsonView) then
    jsonView.Clear;

  res := PythonEng.EvalStringAsStr(format('jsondump(%s)',[expr]));
  result := SO( UTF8Decode(res) );

  if Assigned(jsonView) then
  begin
    LoadJson(res);
    jsonView.RootData := jsondata;
  end;

end;

procedure TDMPython.LoadJson(data: UTF8String);
var
  P:TJSONParser;
begin
  P:=TJSONParser.Create(Data,True);
  try
    if jsondata<>Nil then
      FreeAndNil(jsondata);
    jsondata := P.Parse;
  finally
      FreeAndNil(P);
  end;
end;

function TDMPython.getprivateKeyPassword: Ansistring;
var
  PrivateKeyPath:String;
  Password:String;
  RetryCount:integer;
begin
  if not FileExists(GetWaptPersonalCertificatePath) then
    FCachedPrivateKeyPassword := ''
  else
  begin
    RetryCount:=3;
    Password:= '';
    // try without password
    PrivateKeyPath := MainModule.waptdevutils.get_private_key_encrypted(certificate_path:=GetWaptPersonalCertificatePath(),password:=Password);
    if (PrivateKeyPath ='') and (FCachedPrivateKeyPassword<>'') then
    begin
      Password := FCachedPrivateKeyPassword;
      PrivateKeyPath := MainModule.waptdevutils.get_private_key_encrypted(certificate_path:=GetWaptPersonalCertificatePath(),password:=Password);
      // not found any keys, reset pwd cache to empty.
      if PrivateKeyPath='' then
        FCachedPrivateKeyPassword := '';
    end;

    if PrivateKeyPath ='' then
      while RetryCount>0 do
      begin
        with TvisPrivateKeyAuth.Create(Application.MainForm) do
        try
          laKeyPath.Caption := GetWaptPersonalCertificatePath;
          if ShowModal = mrOk then
          begin
            Password := edPasswordKey.Text;
            PrivateKeyPath := MainModule.waptdevutils.get_private_key_encrypted(certificate_path:=GetWaptPersonalCertificatePath(),password:=Password);
            if PrivateKeyPath<>'' then
            begin
              FCachedPrivateKeyPassword:=edPasswordKey.Text;
              break;
            end;
          end
          else
          begin
            FCachedPrivateKeyPassword := '';
            break;
          end;
        finally
          Free;
        end;
        dec(RetryCount);
      end;

    if PrivateKeyPath='' then
      Raise Exception.CreateFmt('Unable to find and/or decrypt private key for personal certificate %s',[GetWaptPersonalCertificatePath]);
  end;
  Result := FCachedPrivateKeyPassword;
end;



procedure TDMPython.setprivateKeyPassword(AValue: Ansistring);
begin
  FCachedPrivateKeyPassword:=AValue;
end;


function CreateSignedCert(keyfilename,
        crtbasename,
        wapt_base_dir,
        destdir,
        country,
        locality,
        organization,
        orgunit,
        commonname,
        email,
        keypassword:String;
        codesigning:Boolean;
        IsCACert:Boolean;
        CACertificateFilename:String='';
        CAKeyFilename:String=''
    ):String;
var
  destpem,destcrt : Variant;
  params : ISuperObject;
  returnCode:integer;
  rsa,key,cert,cakey,cacert:Variant;
  cakey_pwd: String;

begin
  result := '';
  cacert := Null;
  cakey := Null;
  cakey_pwd := '';

  if (CACertificateFilename<>'') then
    if not FileExists(CACertificateFilename) then
      raise Exception.CreateFmt('CA Certificate %s does not exist',[CACertificateFilename])
    else
      cacert:= MainModule.waptcrypto.SSLCertificate(crt_filename := CACertificateFilename);

  if (CAKeyFilename<>'') then
    if not FileExists(CAKeyFilename) then
      raise Exception.CreateFmt('CA private key %s does not exist',[CAKeyFilename])
    else
    begin
      if InputQuery('CA Private key password','Password',True,cakey_pwd) then
      begin
        cakey:= MainModule.waptcrypto.SSLPrivateKey(filename := CAKeyFilename, password := cakey_pwd);
        rsa := cakey.as_pem;
      end
      else
        raise Exception.CreateFmt('No password for decryption of %s',[CAKeyFilename]);
    end;

  if FileExists(keyfilename) then
    destpem := keyfilename
  else
  begin
    if ExtractFileNameOnly(keyfilename) = keyfilename then
      destpem := AppendPathDelim(destdir)+ExtractFileNameOnly(keyfilename)+'.pem'
    else
      destpem := keyfilename;
  end;

  if crtbasename = '' then
    crtbasename := ExtractFileNameOnly(keyfilename);

  destcrt := AppendPathDelim(destdir)+crtbasename+'.crt';
  if not DirectoryExists(destdir) then
       CreateDir(destdir);

  key := MainModule.waptcrypto.SSLPrivateKey(filename := destpem,password := keypassword);

  // Create private key  if not already exist
  if not FileExists(destpem) then
  begin
    key.create(bits := 2048);
    key.save_as_pem(password := keypassword)
  end;

  // None can not be passed... not accepted : invalid Variant type
  // using default None on the python side to workaround this...
  // python call
  if  VarIsNull(cacert) or VarIsNull(cakey) or VarIsEmpty(cacert) or VarIsEmpty(cakey) then
    // self signed
    cert := key.build_sign_certificate(
      cn := commonname,
      organization := organization,
      locality := locality,
      country := country,
      organizational_unit := orgunit,
      email := email,
      is_ca := IsCACert,
      is_code_signing := codesigning)
  else
    cert := key.build_sign_certificate(
      ca_signing_key := cakey,
      ca_signing_cert := cacert,
      cn := commonname,
      organization := organization,
      locality := locality,
      country := country,
      organizational_unit := orgunit,
      email := email,
      is_ca := IsCACert,
      is_code_signing := codesigning);

  cert.save_as_pem(filename := destcrt);
  result := destcrt;
end;

end.

