program DragDropChecks;

uses
  System.StartUpCopy, System.SysUtils, System.Types, System.Classes, System.UITypes,
  System.Diagnostics, FMX.Forms, FMX.Types, FMX.Platform, FMX.Graphics, FMUX.Api,
  FMXWayland.DragDrop,
  HelloMain in '..\samples\Hello\HelloMain.pas', HelloWindow in '..\samples\Hello\HelloWindow.pas';

type
  TChecks = class
    Form: THelloForm;
    Mode: string;
    Ends, Drops, Leaves: Integer;
    procedure SourceDown(Sender: TObject; Button: TMouseButton; Shift: TShiftState; X,Y: Single);
    procedure SourceEnd(Sender: TObject);
    procedure Dropped(Sender: TObject; const Data: TDragObject; const Point: TPointF);
    procedure Left(Sender: TObject);
    procedure MoveOver(Sender: TObject; const Data: TDragObject; const Point: TPointF; var Operation: TDragOperation);
  end;

procedure Check(Value: Boolean; const Message: string);
begin if not Value then raise Exception.Create(Message); end;

procedure TChecks.SourceDown(Sender: TObject; Button: TMouseButton; Shift: TShiftState; X,Y: Single);
var Service: IFMXDragDropService; Data: TDragObject; Bitmap: TBitmap;
begin
  Data := Default(TDragObject); Data.Source := Sender;
  Data.Data := 'Привет 你好 😀' + StringOfChar('x', 1024 * 1024);
  Data.Files := ['/tmp/漢 字😀.txt', '/tmp/a#b%.png'];
  Check(TPlatformServices.Current.SupportsPlatformService(IFMXDragDropService, Service), 'Drag service registered');
  Bitmap := TBitmap.Create(8,8);
  try Bitmap.Clear($FF123456); Service.BeginDragDrop(Form, Data, Bitmap); finally Bitmap.Free; end;
end;

procedure TChecks.SourceEnd(Sender: TObject);
begin Inc(Ends); end;

procedure TChecks.Dropped(Sender: TObject; const Data: TDragObject; const Point: TPointF);
begin
  Inc(Drops);
  if Mode = 'files' then
    Check((Length(Data.Files) = 2) and (Data.Files[0] = '/tmp/漢 字😀.txt') and
      (Data.Files[1] = '/tmp/a#b%.png'), 'Incoming local URI files')
  else
  begin
    Check(Data.Data.IsType<string> and (Data.Data.AsString = 'Привет 你好 😀' + StringOfChar('x',1024*1024)), 'Incoming Unicode text');
    if Mode = 'internal' then Check(Data.Source = Form.DragTextButton, 'Internal Source identity and TValue preserved');
  end;
end;

procedure TChecks.Left(Sender: TObject);
begin Inc(Leaves); Form.DropAreaLeave(Sender); end;

procedure TChecks.MoveOver(Sender: TObject; const Data: TDragObject; const Point: TPointF; var Operation: TDragOperation);
begin Operation := TDragOperation.Move; end;

var Test: TChecks; Watch: TStopwatch; Uris: UTF8String; Files: TArray<string>;
begin
  try
    Uris := DragFilesToUriList(['/tmp/漢 字😀.txt', '/tmp/a#b%.png']);
    Files := DragUriListToFiles(string(Uris));
    Check((Length(Files) = 2) and (Files[0] = '/tmp/漢 字😀.txt') and (Files[1] = '/tmp/a#b%.png'), 'URI encode/decode roundtrip');
    Check(Length(DragUriListToFiles('file://remote/tmp/a'#13#10'file:///tmp/%00a'#13#10'file:///tmp/%FF'#13#10'file:///tmp/%XX')) = 0, 'Reject remote, NUL and malformed URI paths');
    Files := DragUriListToFiles('file:///tmp/😀.txt');
    Check((Length(Files) = 1) and (Files[0] = '/tmp/😀.txt'), 'Raw UTF-8 URI');
    Application.Initialize;
    Test := TChecks.Create;
    try
      Test.Mode := GetEnvironmentVariable('FMX_TEST_DRAG_MODE');
      Test.Form := THelloForm.Create(nil);
      try
        Test.Form.DemoTabs.ActiveTab := Test.Form.DragTab;
        Test.Form.DragTextButton.OnMouseDown := Test.SourceDown;
        Test.Form.DragTextButton.OnDragEnd := Test.SourceEnd;
        if Test.Mode = 'automatic' then
        begin
          // A label's Data is its text; a button's Data is its OnClick method TValue.
          Test.Form.DragFileLabel.DragMode := TDragMode.dmAutomatic;
          Test.Form.DragFileLabel.HitTest := True;
          Test.Form.DragFileLabel.Text := 'Привет 你好 😀';
          Test.Form.DragFileLabel.OnDragEnd := Test.SourceEnd;
        end;
        Test.Form.DropArea.OnDragDrop := Test.Dropped;
        Test.Form.DropArea.OnDragLeave := Test.Left;
        if Test.Mode = 'move' then Test.Form.DropArea.OnDragOver := Test.MoveOver;
        Test.Form.Show;
        if Test.Mode = 'no-grab' then Test.SourceDown(Test.Form.DragTextButton, TMouseButton.mbLeft, [], 0, 0);
        Watch := TStopwatch.StartNew;
        while Watch.ElapsedMilliseconds < 1800 do
        begin
          Application.ProcessMessages; TThread.Sleep(2);
          if (Test.Mode = 'sourcegone') and (Watch.ElapsedMilliseconds > 300) and
            (Test.Form.DragTextButton <> nil) then FreeAndNil(Test.Form.DragTextButton);
        end;
        if (Test.Mode = 'text') or (Test.Mode = 'files') or (Test.Mode = 'legacy') or (Test.Mode = 'move') then
          Check((Test.Drops = 1) and (Test.Leaves > 0), 'Incoming drop and leave lifecycle')
        else if Test.Mode = 'internal' then Check((Test.Drops = 1) and (Test.Ends = 1), 'Internal drop/end once')
        else if Test.Mode = 'internal-cancel' then Check((Test.Drops = 0) and (Test.Ends = 1) and (Test.Leaves > 0), 'Internal cancellation leaves the target')
        else if (Test.Mode = 'outgoing') or (Test.Mode = 'cancel') or (Test.Mode = 'no-grab') or (Test.Mode = 'automatic') then
          Check((Test.Drops = 0) and (Test.Ends = 1) and not Test.Form.DragTextButton.IsPressed, 'Outgoing finish/cancel and button state')
        else if Test.Mode = 'sourcegone' then Check(Test.Ends = 0, 'Destroyed Source never called')
        else Check(Test.Drops = 0, 'Rejected/left drag never drops');
        Writeln('FMX drag/drop ', Test.Mode, ' checks passed');
      finally Test.Form.Free; end;
    finally Test.Free; end;
  except on E: Exception do begin Writeln(ErrOutput,E.ClassName + ': ' + E.Message); Halt(1); end; end;
end.
