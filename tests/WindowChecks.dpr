program WindowChecks;

uses
  System.SysUtils, System.Types, System.Diagnostics, FireLinux.Wayland.Platform, FireLinux.RasterFrame;

type
  TWindow = class(TWlWindow)
  public
    function HasButton(const Part: TWlDecoPart): Boolean;
    function Hit(const X, Y: Single): TWlDecoPart;
  protected
    procedure DoPaint(const Frame: PRasterFrame; const Dirty: TRectF); override;
  end;

function TWindow.HasButton(const Part: TWlDecoPart): Boolean;
begin Result := ButtonVisible(Part); end;

function TWindow.Hit(const X, Y: Single): TWlDecoPart;
begin Result := DecoPartAt(X, Y); end;

procedure TWindow.DoPaint(const Frame: PRasterFrame; const Dirty: TRectF);
begin
  FillChar(Frame.Bits^, Frame.Stride * Frame.Height, $FF);
  Frame.Drawn := True;
end;

procedure Check(Value: Boolean; const Message: string);
begin
  if not Value then raise Exception.Create(Message);
end;

var
  Display: TWlDisplay;
  W: TWindow;
  Watch: TStopwatch;
  Style, Buttons: Integer;
  Icon: TArray<Cardinal>;

procedure Pump;
begin
  Watch := TStopwatch.StartNew;
  while Watch.ElapsedMilliseconds < 50 do Display.ProcessEvents(5);
end;

begin
  try
    Display := TWlDisplay.Create;
    try
      Display.Connect;
      Icon := [$FFFF0000, $FF00FF00, $FF0000FF, $FFFFFFFF];
      for Style := 0 to 4 do
        for Buttons := 0 to 3 do
        begin
          W := TWindow.Create(Display, TWlWindowKind.Toplevel, False);
          try
            W.ConfigureFrame(Style = 0, Style in [2,4], Style in [3,4],
              Buttons <> 0, Buttons in [1,3], Buttons in [2,3]);
            W.SetBounds(10,20,320,200);
            W.SetTitle(Format('style=%d buttons=%d Заголовок', [Style, Buttons]));
            W.SetAppId('org.firelinux.WindowChecks');
            W.SetSizeConstraints(100,80,500,400);
            W.SetIcon(Icon,2);
            W.Show;
            Pump;
            Check(W.Mapped, 'Window was mapped');
            Check((W.Width = 320) and (W.Height = 240), 'Independent zero configure dimension');
            if Style = 0 then Check(W.DecorationInsets.Top = 0, 'Borderless insets');
            Check(W.HasButton(TWlDecoPart.Close) = (Buttons <> 0), 'System menu controls close');
            Check(W.HasButton(TWlDecoPart.Maximize) = ((Style = 2) and (Buttons in [2,3])),
              'Maximize requires sizeable regular frame');
            Check(W.HasButton(TWlDecoPart.Minimize) = ((Style in [0,1,2]) and
              (Buttons in [1,3]) and (GetEnvironmentVariable('FMX_TEST_WM_MODE') = 'old')),
              'Unavailable minimize is hidden');
            if W.Csd then
            begin
              if Buttons <> 0 then
                Check(W.Hit(W.Width + W.DecorationInsets.Left - 2, 10) = TWlDecoPart.Close, 'Close hit area')
              else
                Check(W.Hit(W.Width + W.DecorationInsets.Left - 2, 10) = TWlDecoPart.Title, 'Hidden close hit area');
              if Style in [1,3] then
                Check(W.Hit(1,100) = TWlDecoPart.None, 'Fixed border cannot resize');
              if Style in [2,4] then
                Check(W.Hit(1,100) = TWlDecoPart.Left, 'Sizeable border can resize');
            end;
            W.SetTitle(Format('updated=%d,%d 你好', [Style, Buttons]));
            W.SetSize(340,220);
            W.SetSizeConstraints(0,0,0,0);
            W.SetIcon(nil,0);
            W.InvalidateAll;
            Pump;
            W.Hide;
            W.Show;
            Pump;
            Check(W.Mapped, 'Window remapped');
          finally W.Free; end;
        end;
      Display.Flush;
    finally Display.Free; end;
    Writeln('Window settings checks passed');
  except
    on E: Exception do begin Writeln(E.ClassName, ': ', E.Message); Halt(1); end;
  end;
end.
