program DialogChecks;

uses
  System.StartUpCopy, System.SysUtils, System.Classes, System.UITypes, System.Diagnostics,
  FMX.Forms, FMX.Dialogs, FMX.Platform, FMX.Types, FMX.Edit, FMUX.Api,
  FMXWayland.DialogTypes, FMXWayland.Dialogs, FMXWayland.Portal, FMXWayland.DBus;

type
  TTestBackend = class(TFMXWaylandDialogBackend)
  public
    Accept: Boolean;
    FilesCalled, MessagesCalled, InputsCalled: Integer;
    function FileDialog(const Request: TWaylandFileDialogRequest; out Files: TArray<string>;
      var FilterIndex: Integer): Boolean; override;
    function MessageDialog(const Message: string; DialogType: TMsgDlgType; Buttons: TMsgDlgButtons;
      DefaultButton: TMsgDlgBtn): TModalResult; override;
    function InputQuery(const Caption: string; const Prompts: TArray<string>;
      var Values: TArray<string>): Boolean; override;
  end;
  TAutoClose = class
    ResultToReturn: TModalResult;
    StopApplication: Boolean;
    procedure Tick(Sender: TObject);
  end;

procedure Check(Condition: Boolean; const Message: string);
begin
  if not Condition then raise Exception.Create(Message);
end;

function TTestBackend.FileDialog(const Request: TWaylandFileDialogRequest; out Files: TArray<string>;
  var FilterIndex: Integer): Boolean;
begin
  Inc(FilesCalled);
  Check(Request.Filters[0].Patterns[0] = '*.txt', 'Custom filter');
  Files := ['/tmp/свой диалог.txt'];
  FilterIndex := 2;
  Result := Accept;
end;

function TTestBackend.MessageDialog(const Message: string; DialogType: TMsgDlgType;
  Buttons: TMsgDlgButtons; DefaultButton: TMsgDlgBtn): TModalResult;
begin
  Inc(MessagesCalled);
  Check(DefaultButton = TMsgDlgBtn.mbNo, 'Default button lost');
  Result := mrNo;
end;

function TTestBackend.InputQuery(const Caption: string; const Prompts: TArray<string>;
  var Values: TArray<string>): Boolean;
begin
  Inc(InputsCalled);
  Check(Length(Prompts) = Length(Values), 'Input count');
  Values[0] := 'ответ';
  Result := Accept;
end;

procedure CustomChecks;
var
  Obj: TTestBackend; Backend: IFMXWaylandDialogBackend;
  Open: TOpenDialog; Sync: IFMXDialogServiceSync; Async: IFMXDialogServiceAsync;
  Values: TArray<string>; Done: Boolean;
begin
  Obj := TTestBackend.Create; Backend := Obj; Obj.Accept := True;
  SetWaylandDialogBackend(Backend);
  Open := TOpenDialog.Create(nil);
  try
    Open.Filter := 'Text|*.txt|All|*.*';
    Check(Open.Execute, 'Custom open');
    Check((Open.FileName = '/tmp/свой диалог.txt') and (Open.FilterIndex = 2), 'Custom filename');
    Obj.Accept := False;
    Check(not Open.Execute, 'Custom cancel');
  finally Open.Free; end;
  Check(TPlatformServices.Current.SupportsPlatformService(IFMXDialogServiceSync, Sync), 'Sync service');
  Check(TPlatformServices.Current.SupportsPlatformService(IFMXDialogServiceAsync, Async), 'Async service');
  Check(Sync.MessageDialogSync('test', TMsgDlgType.mtConfirmation, [TMsgDlgBtn.mbYes, TMsgDlgBtn.mbNo],
    TMsgDlgBtn.mbNo, 0) = mrNo, 'Custom message');
  Values := ['original'];
  Check(not Sync.InputQuerySync('test', ['prompt'], Values) and (Values[0] = 'original'), 'Input cancel preserves value');
  Obj.Accept := True;
  Check(Sync.InputQuerySync('test', ['prompt'], Values) and (Values[0] = 'ответ'), 'Custom input');
  Done := False;
  Async.MessageDialogAsync('test', TMsgDlgType.mtConfirmation, [TMsgDlgBtn.mbYes, TMsgDlgBtn.mbNo],
    TMsgDlgBtn.mbNo, 0, procedure(const R: TModalResult)
    begin Check(R = mrNo, 'Async message result'); Done := True; end);
  Check(not Done, 'Async callback must be deferred');
  // Replacing the backend must keep an already queued request alive and on its original backend.
  SetWaylandDialogBackend(nil);
  CheckSynchronize(0);
  Check(Done, 'Async message callback');
  SetWaylandDialogBackend(Backend);
  Done := False;
  Async.InputQueryAsync('test', ['prompt'], ['original'],
    procedure(const R: TModalResult; const AValues: array of string)
    begin Check((R = mrOK) and (AValues[0] = 'ответ'), 'Async input result'); Done := True; end);
  CheckSynchronize(0);
  Check(Done and (Obj.FilesCalled = 2) and (Obj.MessagesCalled = 2) and (Obj.InputsCalled = 3), 'Custom call counts');
  Obj.Accept := False;
  Done := False;
  Async.InputQueryAsync('test', ['prompt'], ['original'],
    procedure(const R: TModalResult; const AValues: array of string)
    begin Check((R = mrCancel) and (AValues[0] = 'original'), 'Async cancel preserves values'); Done := True; end);
  CheckSynchronize(0);
  Check(Done, 'Async cancel callback');
  SetWaylandDialogBackend(nil);
  Writeln('Custom backend and FMX service checks passed');
end;

procedure PortalChecks;
var
  Open: TOpenDialog; Save: TSaveDialog;
  Request: TWaylandFileDialogRequest; Files: TArray<string>; Index: Integer;
  Buffer: array[0..15] of Char; Raised: Boolean; Watch: TStopwatch;
begin
  Open := TOpenDialog.Create(nil);
  Save := TSaveDialog.Create(nil);
  try
    Open.Filter := 'Text|*.txt|All|*.*'; Open.FilterIndex := 1;
    Open.InitialDir := '/tmp/каталог'; Open.Title := 'single';
    Check(Open.Execute and (Open.FileName = '/tmp/тест файл.txt') and (Open.FilterIndex = 2), 'Portal unicode/filter');
    Open.Title := 'multi'; Open.Options := Open.Options + [TOpenOption.ofAllowMultiSelect];
    Check(Open.Execute and (Open.Files.Count = 2) and (Open.Files[1] = '/tmp/a%b.txt'), 'Portal multiselect');
    Open.Title := 'cancel';
    Check(not Open.Execute, 'Portal cancel');
    Save.Title := 'save'; Save.InitialDir := '/tmp/каталог'; Save.FileName := 'новый.txt'; Save.Filter := Open.Filter;
    Check(Save.Execute and (Save.FileName = '/tmp/новый.txt'), 'Portal save');
    Open.Title := 'fast'; Open.Options := Open.Options - [TOpenOption.ofAllowMultiSelect];
    Check(Open.Execute, 'Response before method reply');
    Open.Title := 'error';
    Check(not Open.Execute, 'Portal response 2 cancels the request');
    Open.Title := 'invalid';
    Check(not Open.Execute, 'Remote URI rejected');
    Index := 1; Buffer[0] := #0; Raised := False;
    try FmuxFilesDialog('single', 'Text|*.txt|All|*.*', '', '/tmp/каталог', @Buffer[0],
      Length(Buffer), Index, 1); except on E: EArgumentException do Raised := True; end;
    Check(Raised and (Buffer[0] = #0) and (Index = 1), 'No filename truncation');
    Request := Default(TWaylandFileDialogRequest); Request.Kind := TWaylandFileDialogKind.SelectFolder;
    Request.Title := 'folder'; Index := 1;
    Check(PortalFileDialog(Request, '', Files, Index, nil) and (Files[0] = '/tmp/каталог'), 'Portal folder');
    Request.Kind := TWaylandFileDialogKind.OpenFile; Request.Title := 'abandon';
    Watch := TStopwatch.StartNew; Raised := False;
    try PortalFileDialog(Request, '', Files, Index, function(const Fd, TimeoutMs: Integer): Boolean
      begin Result := Watch.ElapsedMilliseconds < 500; end);
    except on E: EDBusCancelled do Raised := True; end;
    Check(Raised, 'Pending request cancellation');
  finally Open.Free; Save.Free; end;
  Writeln('Portal file dialog checks passed');
end;

procedure TAutoClose.Tick(Sender: TObject);
var I: Integer; Form: TCommonCustomForm;
begin
  if StopApplication then
  begin Application.Terminate; Exit; end;
  for I := 0 to Screen.FormCount - 1 do
  begin
    Form := Screen.Forms[I];
    if Form.Visible then Form.ModalResult := ResultToReturn;
  end;
end;

procedure PortalPumpCheck;
var Timer: TTimer; Closer: TAutoClose; Open: TOpenDialog;
begin
  Timer := TTimer.Create(nil); Closer := TAutoClose.Create; Open := TOpenDialog.Create(nil);
  try
    Closer.StopApplication := True;
    Timer.Interval := 500; Timer.OnTimer := Closer.Tick; Timer.Enabled := True;
    Open.Title := 'abandon';
    Check(not Open.Execute, 'App shutdown cancels the default backend request');
  finally Timer.Free; Closer.Free; Open.Free; end;
  Writeln('Portal event pump and application shutdown checks passed');
end;

procedure OwnFMXChecks;
var Timer: TTimer; Closer: TAutoClose; Sync: IFMXDialogServiceSync; Values: TArray<string>;
begin
  Timer := TTimer.Create(nil); Closer := TAutoClose.Create;
  try
    Closer.ResultToReturn := mrOK;
    Timer.Interval := 250; Timer.OnTimer := Closer.Tick; Timer.Enabled := True;
    TPlatformServices.Current.SupportsPlatformService(IFMXDialogServiceSync, Sync);
    Check(Sync.MessageDialogSync('FMX message', TMsgDlgType.mtInformation, [TMsgDlgBtn.mbOK],
      TMsgDlgBtn.mbOK, 0) = mrOK, 'FMX modal message');
    Values := ['Unicode: Юникод'];
    Check(Sync.InputQuerySync('FMX input', ['Value'], Values) and (Values[0] = 'Unicode: Юникод'), 'FMX modal input');
    Closer.ResultToReturn := mrCancel;
    Check(not Sync.InputQuerySync('FMX cancel', ['Value'], Values) and
      (Values[0] = 'Unicode: Юникод'), 'FMX input cancellation');
  finally Timer.Free; Closer.Free; end;
  Writeln('FMX message/input checks passed');
end;

var Started: TStopwatch; Request: TWaylandFileDialogRequest; Files: TArray<string>; Index: Integer;
begin
  try
    Application.Initialize;
    if ParamStr(1) = '--real-portal' then
    begin
      Request := Default(TWaylandFileDialogRequest); Request.Title := 'FMXWayland portal smoke test'; Index := 1;
      Started := TStopwatch.StartNew;
      try
        PortalFileDialog(Request, '', Files, Index, function(const Fd, TimeoutMs: Integer): Boolean
          begin Application.ProcessMessages; Result := Started.ElapsedMilliseconds < 1500; end);
      except on E: EDBusCancelled do Writeln('Real portal opened and cancelled cleanly'); end;
    end
    else
    begin CustomChecks; PortalChecks; OwnFMXChecks; PortalPumpCheck; end;
  except on E: Exception do begin Writeln(ErrOutput, E.ClassName + ': ' + E.Message); Halt(1); end; end;
end.
