program FMXImeChecks;

uses
  System.StartUpCopy, System.SysUtils, System.Classes, System.Diagnostics, FMX.Forms, FMUX.Api,
  HelloMain in '..\samples\Hello\HelloMain.pas', HelloWindow in '..\samples\Hello\HelloWindow.pas';

var Form: THelloForm; Watch: TStopwatch; Mode, Expected, Actual: string;

function EditorText: string;
begin
  if Mode = 'memo' then Result := Form.NotesMemo.Lines.Text.TrimRight
  else Result := Form.EditBox.Text;
end;
begin
  try
    Application.Initialize;
    Form := THelloForm.Create(nil);
    try
      Form.Show;
      Application.ProcessMessages;
      Mode := GetEnvironmentVariable('FMX_TEST_IME_MODE');
      Expected := 'A你好界';
      if Mode = 'memo' then
      begin
        Form.NotesMemo.Lines.Text := '甲乙' + sLineBreak + 'AB';
        Form.NotesMemo.SelStart := Length('甲乙' + sLineBreak) + 1;
        Form.NotesMemo.SelLength := 0;
        Form.NotesMemo.SetFocus;
        Expected := '甲乙' + sLineBreak + Expected;
      end
      else
      begin
        Form.EditBox.Password := Mode = 'password';
        Form.EditBox.ReadOnly := Mode = 'readonly';
        Form.EditBox.Text := 'AB';
        if Mode = 'password' then begin Form.EditBox.SelStart := 2; Expected := 'AB'; end
        else Form.EditBox.SelStart := 1;
        Form.EditBox.SelLength := 0;
        Form.EditBox.SetFocus;
      end;
      Watch := TStopwatch.StartNew;
      while (EditorText <> Expected) and (Mode <> 'readonly') and (Watch.ElapsedMilliseconds < 5000) do
        Application.ProcessMessages;
      for var I := 1 to 20 do begin Application.ProcessMessages; TThread.Sleep(10); end;
      Actual := EditorText;
      if Mode = 'readonly' then Expected := 'AB';
      if Actual <> Expected then raise Exception.Create('FMX IME text: ' + Actual);
      Writeln('FMX IME ' + Mode + ' checks passed');
    finally Form.Free; end;
  except on E: Exception do begin Writeln(ErrOutput,E.ClassName + ': ' + E.Message); Halt(1); end; end;
end.
