program FMXWindowChecks;

uses
  System.StartUpCopy, System.SysUtils, System.Classes, System.Types, System.UITypes,
  System.Diagnostics, FMX.Forms, FMX.Types, FMX.Graphics, FMX.Platform, FMX.Platform.Linux,
  FMUX.Api, FMXWayland.Platform;

procedure Check(Value: Boolean; const Message: string);
begin if not Value then raise Exception.Create(Message); end;

procedure Pump;
var Watch: TStopwatch;
begin
  Watch := TStopwatch.StartNew;
  while Watch.ElapsedMilliseconds < 100 do Application.ProcessMessages;
end;

var
  Form: TForm;
  Service: IFMXWindowConstraintsService;
  W: TWlWindow;
  Style: TFmxFormBorderStyle;
  Bitmap: TBitmap;
  Stream: TMemoryStream;
begin
  try
    Application.Initialize;
    Check(TPlatformServices.Current.SupportsPlatformService(IFMXWindowConstraintsService, Service),
      'FMX constraints service registered');
    for Style := Low(TFmxFormBorderStyle) to High(TFmxFormBorderStyle) do
    begin
      Form := TForm.CreateNew(nil);
      try
        Form.BorderStyle := Style;
        Form.Caption := 'Настройки окна 你好';
        Form.SetBounds(40,40,400,300);
        Form.Constraints.MinWidth := 200;
        Form.Constraints.MinHeight := 150;
        Form.Constraints.MaxWidth := 600;
        Form.Constraints.MaxHeight := 500;
        Form.Show;
        Pump;
        W := TWlWindow(TLinuxWindowHandle(Form.Handle).Window);
        Check(W.Mapped, 'FMX form mapped');
        Check((Abs(Form.Width - 400) < 1) and (Abs(Form.Height - 300) < 1), 'Requested outer bounds preserved');
        Check((Abs(W.Width + W.DecorationInsets.Left + W.DecorationInsets.Right - Form.Width) < 1) and
          (Abs(W.Height + W.DecorationInsets.Top + W.DecorationInsets.Bottom - Form.Height) < 1),
          'Decoration negotiation preserves outer FMX bounds');
        Check(W.Title = Form.Caption, 'Unicode caption');
        Check(W.Borderless = (Style = TFmxFormBorderStyle.None), 'FMX border style forwarded');
        Form.Caption := 'Новый заголовок';
        Check(W.Title = Form.Caption, 'Runtime caption');
        Form.Constraints.MaxWidth := 550;
        Form.BorderIcons := [TBorderIcon.biSystemMenu];
        Pump;
        W := TWlWindow(TLinuxWindowHandle(Form.Handle).Window);
        Check(W.Mapped, 'Form recreated after BorderIcons change');
        Bitmap := TBitmap.Create(20,12);
        Stream := TMemoryStream.Create;
        try
          Bitmap.Clear($FF4488CC);
          Bitmap.SaveToStream(Stream);
          FmuxSetWindowIcon(TLinuxWindowHandle(Form.Handle).Window, Stream.Memory, Stream.Size);
          Pump;
          FmuxSetWindowIcon(TLinuxWindowHandle(Form.Handle).Window, nil, 0);
        finally Stream.Free; Bitmap.Free; end;
        Form.Hide;
        Form.Show;
        Pump;
        Check(W.Mapped, 'FMX form remapped');
      finally Form.Free; end;
    end;
    Writeln('FMX window settings checks passed');
  except on E: Exception do begin Writeln(E.ClassName, ': ', E.Message); Halt(1); end; end;
end.
