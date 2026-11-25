{ FireLinux: native Wayland platform for Delphi FireMonkey on Linux.
  Copyright (c) 2026 Fasday. MIT license, see LICENSE. }

/// <summary>The FMUX API (the function pointers of FMUX.Api that FMX for Linux calls) implemented over
/// FireLinux.Wayland.Platform.</summary>
/// <remarks>
/// <para>Windows: FMX's window handle (TLinuxWindowHandle.Window) is a TFmuxWindow, a TWlWindow that forwards the
/// Wayland events to the callbacks of TFmuxCreateStruct.</para>
/// <para>Coordinates: Wayland has no global coordinates. Every window keeps a virtual origin (what FMX set with
/// SetWindowRect); ClientToScreen/ScreenToClient and the screen positions of mouse events use it, so FMX's own
/// conversions stay consistent; popups are placed relative to their parent and take the origin the compositor gives
/// them.</para>
/// <para>Painting: the paint context handed to FMX (the Ctx of TFmuxPaintCallback, the context handle of the canvas)
/// depends on FMX's canvas. FMX's default Linux canvas (FMX.Canvas.Linux: cairo and Pango, FireLinux.Cairo) gets a
/// cairo context over the window's retained frame; what changed is then copied into the wl_shm buffer that is
/// attached to the surface. The Skia raster canvas (GlobalUseSkia) gets the PRasterFrame, renders into an FMUX bitmap
/// (plain memory) and copies it with FmuxCanvasDrawBitmap into the frame.</para>
/// <para>Dialogs: file dialogs (FmuxFilesDialog: TOpenDialog, TSaveDialog, SelectDirectory) and message dialogs go
/// to the backend of FireLinux.Dialogs (by default the xdg-desktop-portal FileChooser, FMX's own forms without a
/// portal). While a portal dialog is open the loop keeps running (DialogPump) and the program's windows are blocked
/// as under a modal form (a nil entry on the modal stack); the dialog's parent is the window exported with
/// xdg-foreign.</para>
/// </remarks>
unit FireLinux.Wayland.Fmux;

interface

uses
  System.SysUtils;

type
  EWaylandConnectionError = class(Exception);

/// <summary>Installs the Wayland callbacks into FMUX.Api.</summary>
procedure AssignWaylandApi;

implementation

uses
  System.Types, System.Classes, System.UITypes, System.Math,
  System.Messaging, System.Generics.Collections, FMX.Types, FMX.Graphics,
  FMX.Forms, FMX.Controls, FMX.Platform,
  FMX.Platform.Linux, FMUX.Api, FireLinux.Log, FireLinux.Posix,
  FireLinux.Wayland.Platform, FireLinux.Wayland.Native, FireLinux.Frame,
  FireLinux.SystemFont, FireLinux.Cairo, FireLinux.RasterFrame, FireLinux.Dialogs,
  FireLinux.OpenGL, FireLinux.Wayland.TextInput,
  FireLinux.Wayland.Protocol.TextInputUnstableV3, FMX.Text, FMX.Edit, FMX.Memo,
  FMX.Presentation.Style, FireLinux.Wayland.DragDrop, System.Rtti, FireLinux.Menus;

type
  /// <summary>An FMX window.</summary>
  TFmuxWindow = class(TWlWindow)
  private
    FCreate: TFmuxCreateStruct;
    FLastDump: Int64;
    FDumpIndex: Integer;
    FTitleKey: string;
    FTitlePixels: TArray<Cardinal>;
    FTitleWidth: Integer;
    FTitleHeight: Integer;
    // FMX's cairo canvas paints into FRetained, the window's latest frame (buffer pixels, no row padding); the
    // wl_shm buffers rotate and hold older frames, so each gets what changed since the frame it holds.
    FRetained: TArray<Cardinal>;
    FRetainedWidth: Integer;
    FRetainedHeight: Integer;
    FRetainedSerial: Int64;
    FDamage: array[0..7] of TRect;
    FBufferSerials: TArray<TPair<Pointer, Int64>>;
    // IFireLinuxWindowFrame.SetFrameListener (released with the window).
    FFrameListener: IFireLinuxWindowFrameListener;
    // The client size FMX was last told about (ReportBounds).
    FReportedWidth: Integer;
    FReportedHeight: Integer;
    function Form: TCommonCustomForm;
    function WindowRect: TRectF;
    procedure SetWindowRect(const ARect: TRectF);
    procedure ReportBounds;
    procedure DumpFrame(const AFrame: PRasterFrame);
    procedure PaintCairo(const AFrame: PRasterFrame; const ADirty: TRectF);
    procedure CopyRetained(const AFrame: PRasterFrame; const ARect: TRect);
    procedure RenderTitle(const AWidth, AHeight: Integer; const ATitle: string; const AActive: Boolean; const AScale: Single);
  protected
    procedure DoDecorationChanged(const OldInsets: TRect); override;
    procedure DoDrawTitle(const AFrame: PRasterFrame; const ARect: TRect; const ATitle: string; const AActive: Boolean); override;
    procedure DoPaint(const AFrame: PRasterFrame; const ADirty: TRectF); override;
    procedure DoResized; override;
    procedure DoMoved; override;
    procedure DoStateChanged(const AState: TWlWindowState); override;
    procedure DoActivate(const AActive: Boolean); override;
    procedure DoCloseRequest; override;
    procedure DoPopupDone; override;
    procedure DoPointer(const AEvent: TWlPointerEvent; const AX, AY: Single; const AState, AWheelDelta: Integer); override;
    procedure DoKey(const AEvent: TWlKeyEvent; const AKey: Word; const AChar: Char; const AState: Integer); override;
    procedure DoScaleChanged; override;
    procedure DoFrameChanged; override;
    function DoDrag(const Data: TWlDragData; const Event: TWlDragEvent; const Point: TPointF; const Suggested: TWlDragOperation): TWlDragOperation; override;
  end;

  TWaylandDragService = class(TInterfacedObject, IFMXDragDropService)
    procedure BeginDragDrop(AForm: TCommonCustomForm; const Data: TDragObject; ABitmap: TBitmap);
  end;

  TDragSourceWatch = class(TComponent)
    Watched: TComponent;
    procedure Notification(AComponent: TComponent; Operation: TOperation); override;
  end;

  TDragFormAccess = class(TCommonCustomForm);

  /// <summary>IFireLinuxNativeWindow, registered as a platform service.</summary>
  TNativeWindowService = class(TInterfacedObject, IFireLinuxNativeWindow, IFMXWindowConstraintsService)
  private
    function WindowOf(const AHandle: TWindowHandle): TFmuxWindow;
  public
    procedure SetConstraints(const AForm: TCommonCustomForm; const AMinWidth, AMinHeight, AMaxWidth, AMaxHeight: Single);
    function GetWaylandDisplay: Pointer;
    function GetWaylandSurface(const AHandle: TWindowHandle): Pointer;
    function GetBufferSize(const AHandle: TWindowHandle): TSize;
    function GetScale(const AHandle: TWindowHandle): Single;
    procedure SetExternalPresentation(const AHandle: TWindowHandle; const AValue: Boolean);
  end;

  /// <summary>IFireLinuxWindowFrame, registered as a platform service: the window frame of toplevels for programs
  /// that draw their own title bar.</summary>
  TWindowFrameService = class(TInterfacedObject, IFireLinuxWindowFrame)
  private
    function ToplevelOf(const AHandle: TWindowHandle): TFmuxWindow;
  public
    procedure SetDecorated(const AHandle: TWindowHandle; const AValue: Boolean);
    function GetDecorated(const AHandle: TWindowHandle): Boolean;
    function BeginMove(const AHandle: TWindowHandle): Boolean;
    function BeginResize(const AHandle: TWindowHandle; const AEdges: Cardinal): Boolean;
    function ShowWindowMenu(const AHandle: TWindowHandle; const AClientPoint: TPointF): Boolean;
    procedure Minimize(const AHandle: TWindowHandle);
    procedure SetMaximized(const AHandle: TWindowHandle; const AValue: Boolean);
    function GetStates(const AHandle: TWindowHandle): Cardinal;
    function GetCapabilities(const AHandle: TWindowHandle): Cardinal;
    procedure SetFrameListener(const AHandle: TWindowHandle; const AListener: IFireLinuxWindowFrameListener);
  end;

{$SCOPEDENUMS ON}
  /// <summary>FMX's default canvas: its cairo canvas (FMX.Canvas.Linux) or another (Skia, a GPU canvas).</summary>
  TFmuxCanvasKind = (Unknown, Cairo, Other);
{$SCOPEDENUMS OFF}

var
  GWakeProc: TFmuxWakeMainThreadProc = nil;
  GMainWindow: TFmuxWindow = nil;
  // The windows of the modal loops, innermost last; nil for a dialog of another client (a portal's).
  GModalStack: TList<TFmuxWindow> = nil;
  // For each open portal dialog: the window exported as its parent (nil: none).
  GDialogParents: TList<TFmuxWindow> = nil;
  GClipboardText: string;
  GDumpDir: string;
  GNativeServiceRegistered: Boolean = False;
  GCanvasKind: TFmuxCanvasKind = TFmuxCanvasKind.Unknown;
  GImeWindow: TFmuxWindow;
  GImeData: Pointer;
  GImeStart, GImeChanged, GImeCommit: TFmuxImeCommitProc;
  GImeComposing: Boolean;
  GDragObject: TDragObject;
  GDragWatch: TDragSourceWatch;
  GDragService: IFMXDragDropService;
  GDragServiceRegistered: Boolean;
  GDragImage: TWlDragImage;

{$REGION 'Helpers'}

/// The connection; connects on first use (FMX skips FmuxInit when FMUX.Config.DoNotCallFmuxInit is set).
function Disp: TWlDisplay;
begin
  Result := WlDisplay;
  if Result = nil then
  begin
    try
      Result := WlConnect;
    except
      on E: Exception do
      begin
        WlLog(TWlLogLevel.Error, E.Message);
        Halt(1);
      end;
    end;
  end;
end;

/// The window of an FMUX window pointer, if it is still alive.
function Win(const AWnd: Pointer): TFmuxWindow; inline;
begin
  Result := TFmuxWindow(AWnd);
end;

/// Input goes to the top modal window and to popups only while a modal loop runs (none of the program's windows
/// while another client's dialog is on top).
function InputAllowed(const AWindow: TWlWindow): Boolean;
begin
  Result := (GModalStack = nil) or (GModalStack.Count = 0) or
    ((GModalStack.Last <> nil) and ((AWindow = GModalStack.Last) or (AWindow.Kind = TWlWindowKind.Popup)));
end;

/// The window of the innermost modal form (other clients' dialogs skipped), or nil.
function TopModalWindow: TFmuxWindow;
var
  I: Integer;
begin
  Result := nil;
  if GModalStack <> nil then
    for I := GModalStack.Count - 1 downto 0 do
      if GModalStack[I] <> nil then
        Exit(GModalStack[I]);
end;

{$ENDREGION}

{$REGION 'TFmuxWindow'}

function TFmuxWindow.Form: TCommonCustomForm;
begin
  Result := TCommonCustomForm(FCreate.Data);
end;

function TFmuxWindow.WindowRect: TRectF;
var
  Ins: TRect;
begin
  // FMX's window rectangle includes the frame (client-side decorations); the origin is the client area's.
  Ins := DecorationInsets;
  Result := RectF(Origin.X - Ins.Left, Origin.Y - Ins.Top, Origin.X + Width + Ins.Right,
    Origin.Y + Height + Ins.Bottom);
end;

procedure TFmuxWindow.SetWindowRect(const ARect: TRectF);
var
  Ins: TRect;
begin
  Ins := DecorationInsets;
  SetBounds(ARect.Left + Ins.Left, ARect.Top + Ins.Top, Round(ARect.Width) - Ins.Left - Ins.Right,
    Round(ARect.Height) - Ins.Top - Ins.Bottom);
end;

type
  /// <summary>Access to the protected steps of TCommonCustomForm.SetBounds.</summary>
  TFormAccess = class(TCommonCustomForm);

procedure TFmuxWindow.ReportBounds;
var
  R: TRectF;
  F: TCommonCustomForm;
  SameSize, ClientChanged: Boolean;
begin
  if not Assigned(FCreate.BoundsChanged) then
    Exit;
  R := WindowRect;
  F := Form;
  SameSize := (F <> nil) and (R.Truncate.Width = F.Width) and (R.Truncate.Height = F.Height);
  ClientChanged := (Width <> FReportedWidth) or (Height <> FReportedHeight);
  FReportedWidth := Width;
  FReportedHeight := Height;
  FCreate.BoundsChanged(FCreate.Data, R);
  if SameSize and ClientChanged and (F.Handle <> nil) then
  try
      // FMX resizes its canvas and realigns only when its window rectangle changes size. Here the client area
      // changed in a window of the same size (the decorations came or went): the steps of SetBounds for a new size.
    TFormAccess(F).ResizeHandle;
    TFormAccess(F).Resize;
    TMessageManager.DefaultManager.SendMessage(F, TSizeChangedMessage.Create(TSize.Create(F.Width, F.Height)));
  except
    Application.HandleException(F);
  end;
end;

procedure TFmuxWindow.DoDecorationChanged(const OldInsets: TRect);
var
  Service: IFMXWindowConstraintsService;
begin
  if not Visible then
    Exit;
  // Decoration negotiation must preserve FMX's outer rectangle.
  SetWindowRect(RectF(Origin.X - OldInsets.Left, Origin.Y - OldInsets.Top,
      Origin.X + Width + OldInsets.Right, Origin.Y + Height + OldInsets.Bottom));
  if (Form <> nil) and Form.IsHandleAllocated and
    TPlatformServices.Current.SupportsPlatformService(IFMXWindowConstraintsService, Service) then
    with Form.Constraints do
      Service.SetConstraints(Form, MinWidth, MinHeight, MaxWidth, MaxHeight);
end;

procedure TFmuxWindow.RenderTitle(const AWidth, AHeight: Integer; const ATitle: string; const AActive: Boolean; const AScale: Single);
var
  B: TBitmap;
  Data: TBitmapData;
  Y: Integer;
begin
  FTitleWidth := 0;
  FTitleHeight := 0;
  FTitlePixels := nil;
  B := TBitmap.Create(AWidth, AHeight);
  try
    B.Clear(0);
    if B.Canvas.BeginScene then
    try
      if AActive then
        B.Canvas.Fill.Color := $FF2E3436
      else
        B.Canvas.Fill.Color := $FF8A8F8F;
      B.Canvas.Font.Size := 13 * AScale;
      B.Canvas.Font.Style := [TFontStyle.fsBold];
      B.Canvas.FillText(RectF(0, 0, AWidth, AHeight), ATitle, False, 1, [], TTextAlign.Center,
        TTextAlign.Center);
    finally
      B.Canvas.EndScene;
    end;
    if B.Map(TMapAccess.Read, Data) then
    try
      if Data.PixelFormat <> TPixelFormat.BGRA then
        Exit;
      SetLength(FTitlePixels, AWidth * AHeight);
      for Y := 0 to AHeight - 1 do
        Move(Data.GetScanline(Y)^, FTitlePixels[Y * AWidth], AWidth * 4);
      FTitleWidth := AWidth;
      FTitleHeight := AHeight;
    finally
      B.Unmap(Data);
    end;
  finally
    B.Free;
  end;
end;

procedure TFmuxWindow.DoDrawTitle(const AFrame: PRasterFrame; const ARect: TRect; const ATitle: string; const AActive: Boolean);
var
  Key: string;
  X, Y: Integer;
  Src, Dst: PCardinal;
  A: Cardinal;
begin
  if (ARect.Width <= 0) or (ARect.Height <= 0) or (ATitle = '') then
    Exit;
  Key := Format('%s|%d|%d|%d|%.2f', [ATitle, ARect.Width, ARect.Height, Ord(AActive), AFrame.Scale]);
  if Key <> FTitleKey then
  begin
    FTitleKey := Key;
    try
      RenderTitle(ARect.Width, ARect.Height, ATitle, AActive, AFrame.Scale);
    except
      on E: Exception do
      begin
        FTitlePixels := nil;
        WlLogOnce('title', 'cannot draw window titles: ' + E.Message);
      end;
    end;
  end;
  if FTitlePixels = nil then
    Exit;
  // Source-over of the premultiplied title onto the (opaque) title bar.
  for Y := 0 to FTitleHeight - 1 do
  begin
    if (ARect.Top + Y < 0) or (ARect.Top + Y >= AFrame.Height) then
      Continue;
    Src := @FTitlePixels[Y * FTitleWidth];
    Dst := PCardinal(PByte(AFrame.Bits) + NativeInt(ARect.Top + Y) * AFrame.Stride + ARect.Left * 4);
    for X := 0 to FTitleWidth - 1 do
    begin
      A := Src^ shr 24;
      if A = 255 then
        Dst^ := Src^
      else if A > 0 then
        Dst^ := Src^ + (((((Dst^ and $00FF00FF) * (255 - A)) shr 8) and $00FF00FF) or
          ((((Dst^ shr 8) and $00FF00FF) * (255 - A)) and $FF00FF00));
      Inc(Src);
      Inc(Dst);
    end;
  end;
end;

/// True when FMX draws with its cairo canvas (FMX.Canvas.Linux: GlobalUseSkia is False).
function DefaultCanvasIsCairo: Boolean;
var
  C: TClass;
begin
  if GCanvasKind = TFmuxCanvasKind.Unknown then
  begin
    C := TCanvasManager.DefaultCanvas;
    if C = nil then
      Exit(False);
    GCanvasKind := TFmuxCanvasKind.Other;
    while C <> nil do
    begin
      if C.ClassName = 'TLinuxCanvas' then
        GCanvasKind := TFmuxCanvasKind.Cairo;
      C := C.ClassParent;
    end;
  end;
  Result := GCanvasKind = TFmuxCanvasKind.Cairo;
end;

procedure TFmuxWindow.DoPaint(const AFrame: PRasterFrame; const ADirty: TRectF);
var
  R: TRectF;
begin
  if not Assigned(FCreate.PaintCallback) then
    Exit;
  if DefaultCanvasIsCairo then
    PaintCairo(AFrame, ADirty)
  else
  begin
    // The Skia raster canvas renders the whole window and copies it into the frame (FmuxCanvasDrawBitmap).
    R := ADirty;
    FCreate.PaintCallback(FCreate.Data, AFrame, PRectFArray(@R), 1);
  end;
  if (GDumpDir <> '') and AFrame.Drawn then
    DumpFrame(AFrame);
end;

procedure TFmuxWindow.PaintCairo(const AFrame: PRasterFrame; const ADirty: TRectF);
var
  D: TRect;
  R: TRectF;
  Context: Pointer;
  Held, Serial: Int64;
  I: Integer;
begin
  if AFrame.Bits = nil then
    Exit;
  if (FRetainedWidth <> AFrame.Width) or (FRetainedHeight <> AFrame.Height) then
  begin
    FRetained := nil;
    SetLength(FRetained, NativeInt(AFrame.Width) * AFrame.Height);
    FRetainedWidth := AFrame.Width;
    FRetainedHeight := AFrame.Height;
    FBufferSerials := nil;
    // A new frame holds nothing yet: FMX paints all of it.
    D := Rect(0, 0, AFrame.Width, AFrame.Height);
  end
  else
  begin
    // Whole buffer pixels, the ones Wayland is told are damaged: FMX also repaints the controls that touch a
    // partly covered pixel.
    D := Rect(Floor(ADirty.Left * AFrame.Scale), Floor(ADirty.Top * AFrame.Scale), Ceil(ADirty.Right * AFrame.Scale),
      Ceil(ADirty.Bottom * AFrame.Scale));
    D.Intersect(Rect(0, 0, AFrame.Width, AFrame.Height));
  end;
  R := RectF(D.Left / AFrame.Scale, D.Top / AFrame.Scale, D.Right / AFrame.Scale, D.Bottom / AFrame.Scale);
  try
    Context := CreateCairoFrame(@FRetained[0], AFrame.Width, AFrame.Height, AFrame.Width * 4, AFrame.Scale);
  except
    on E: Exception do
    begin
      WlLogOnce('cairo', E.Message);
      Exit;
    end;
  end;
  try
    FCreate.PaintCallback(FCreate.Data, Context, PRectFArray(@R), 1);
  finally
    DestroyCairoFrame(Context);
  end;
  Inc(FRetainedSerial);
  FDamage[FRetainedSerial mod Length(FDamage)] := D;
  // The buffer holds the frame it was last given (Held), or nothing known: copy what changed since then.
  Held := 0;
  for I := 0 to High(FBufferSerials) do
    if FBufferSerials[I].Key = AFrame.Bits then
      Held := FBufferSerials[I].Value;
  if (Held <= 0) or (FRetainedSerial - Held > Length(FDamage)) then
    CopyRetained(AFrame, Rect(0, 0, AFrame.Width, AFrame.Height))
  else
    for Serial := Held + 1 to FRetainedSerial do
      CopyRetained(AFrame, FDamage[Serial mod Length(FDamage)]);
  I := High(FBufferSerials);
  while (I >= 0) and (FBufferSerials[I].Key <> AFrame.Bits) do
    Dec(I);
  if I < 0 then
  begin
    // Buffers are freed only when the size changes (FBufferSerials starts again then); a few are alive at a time.
    if Length(FBufferSerials) >= 8 then
      Delete(FBufferSerials, 0, 1);
    FBufferSerials := FBufferSerials + [TPair<Pointer, Int64>.Create(AFrame.Bits, FRetainedSerial)];
  end
  else
    FBufferSerials[I].Value := FRetainedSerial;
  AFrame.Drawn := True;
end;

procedure TFmuxWindow.CopyRetained(const AFrame: PRasterFrame; const ARect: TRect);
var
  R: TRect;
  Y: Integer;
begin
  R := ARect;
  R.Intersect(Rect(0, 0, Min(AFrame.Width, FRetainedWidth), Min(AFrame.Height, FRetainedHeight)));
  if R.IsEmpty then
    Exit;
  for Y := R.Top to R.Bottom - 1 do
    Move(FRetained[NativeInt(Y) * FRetainedWidth + R.Left],
      (PByte(AFrame.Bits) + NativeInt(Y) * AFrame.Stride + R.Left * 4)^, R.Width * 4);
end;

procedure TFmuxWindow.DumpFrame(const AFrame: PRasterFrame);
var
  Now: Int64;
  Name: string;
  C: Char;
  S: TFileStream;
  Header: packed record
    Magic: Word;
    FileSize: Cardinal;
    Reserved: Cardinal;
    Offset: Cardinal;
    Size: Cardinal;
    Width: Integer;
    Height: Integer;
    Planes: Word;
    BitCount: Word;
    Compression: Cardinal;
    ImageSize: Cardinal;
    XPels: Integer;
    YPels: Integer;
    ClrUsed: Cardinal;
    ClrImportant: Cardinal;
  end;
  Y: Integer;
begin
  // Debug aid (FIRELINUX_DUMP_DIR): the latest frame of each window as a BMP, at most every 300 ms.
  Now := TThread.GetTickCount64;
  if (FLastDump <> 0) and (Now - FLastDump < 300) then
    Exit;
  FLastDump := Now;
  Inc(FDumpIndex);
  Name := '';
  for C in Title do
    if CharInSet(C, ['A'..'Z', 'a'..'z', '0'..'9', '-', '_']) then
      Name := Name + C;
  if Kind = TWlWindowKind.Popup then
    Name := 'popup';
  if Name = '' then
    Name := 'window';
  Name := Format('%s-%p.bmp', [Name, Pointer(Self)]);
  FillChar(Header, SizeOf(Header), 0);
  Header.Magic := $4D42;
  Header.Offset := SizeOf(Header);
  Header.FileSize := SizeOf(Header) + Cardinal(AFrame.Width * AFrame.Height * 4);
  Header.Size := 40;
  Header.Width := AFrame.Width;
  Header.Height := -AFrame.Height;
  Header.Planes := 1;
  Header.BitCount := 32;
  Header.ImageSize := AFrame.Width * AFrame.Height * 4;
  try
    S := TFileStream.Create(IncludeTrailingPathDelimiter(GDumpDir) + Name, fmCreate);
    try
      S.WriteBuffer(Header, SizeOf(Header));
      for Y := 0 to AFrame.Height - 1 do
        S.WriteBuffer((PByte(AFrame.Bits) + Y * AFrame.Stride)^, AFrame.Width * 4);
    finally
      S.Free;
    end;
  except
    on E: Exception do
      WlLogOnce('dump', 'cannot write frame dumps to ' + GDumpDir + ': ' + E.Message);
  end;
end;

procedure TFmuxWindow.DoResized;
begin
  ReportBounds;
end;

procedure TFmuxWindow.DoMoved;
begin
  ReportBounds;
end;

procedure TFmuxWindow.DoStateChanged(const AState: TWlWindowState);
begin
  if Assigned(FCreate.StateChanged) then
    FCreate.StateChanged(FCreate.Data, TFmuxWindowState(Ord(AState)));
end;

procedure TFmuxWindow.DoActivate(const AActive: Boolean);
begin
  // A window below a modal one that the compositor activates (the user clicked it) stays inactive for FMX; the modal
  // window asks to be activated instead, as on other platforms (a portal's dialog is the compositor's business).
  if AActive and not InputAllowed(Self) then
  begin
    if GModalStack.Last <> nil then
      GModalStack.Last.Activate;
    Exit;
  end;
  if Assigned(FCreate.Activate) then
    FCreate.Activate(FCreate.Data, AActive);
end;

procedure TFmuxWindow.DoCloseRequest;
begin
  if Assigned(FCreate.Close) and InputAllowed(Self) then
    FCreate.Close(FCreate.Data);
end;

procedure TFmuxWindow.DoPopupDone;
begin
  if Assigned(FCreate.Close) then
    FCreate.Close(FCreate.Data);
end;

procedure TFmuxWindow.DoPointer(const AEvent: TWlPointerEvent; const AX, AY: Single; const AState, AWheelDelta: Integer);
var
  P: TPointF;
  F: TCommonCustomForm;
begin
  if not InputAllowed(Self) or not Assigned(FCreate.Motion) then
    Exit;
  // FMX takes screen coordinates (virtual: origin + position in the window).
  P := ClientToScreen(PointF(AX, AY));
  case AEvent of
    TWlPointerEvent.Move:
      FCreate.Motion(FCreate.Data, TFmuxMotionKind.Move, P.X, P.Y, AState);
    TWlPointerEvent.Down:
      FCreate.Motion(FCreate.Data, TFmuxMotionKind.Down, P.X, P.Y, AState);
    TWlPointerEvent.Up:
      FCreate.Motion(FCreate.Data, TFmuxMotionKind.Up, P.X, P.Y, AState);
    TWlPointerEvent.Wheel:
      // FMX reads the wheel delta from Y (WHEEL_DELTA = 120 per notch, positive = up).
      FCreate.Motion(FCreate.Data, TFmuxMotionKind.Scroll, 0, AWheelDelta, AState);
    TWlPointerEvent.Leave:
      begin
        F := Form;
        try
          if F <> nil then
            F.MouseLeave;
        except
          Application.HandleException(F);
        end;
      end;
  end;
end;

procedure TFmuxWindow.DoKey(const AEvent: TWlKeyEvent; const AKey: Word; const AChar: Char; const AState: Integer);
begin
  if not InputAllowed(Self) or not Assigned(FCreate.Key) then
    Exit;
  if (AEvent = TWlKeyEvent.Down) and HandleWaylandMenuKey(Form, AKey, AChar, FmuxStateToShiftState(AState)) then
    Exit;
  FCreate.Key(FCreate.Data, TFmuxKeyKind(Ord(AEvent)), AKey, AChar, AState);
end;

procedure TFmuxWindow.DoScaleChanged;
var
  F: TCommonCustomForm;
begin
  F := Form;
  if (F = nil) or (F.Handle = nil) then
    Exit;
  try
    // As FMX's Windows platform does for WM_DPICHANGED: the form's canvas (and a TForm3D's context) is made again,
    // since a canvas takes the window's scale when it is made. A new window often starts at the output's integer
    // scale and gets the fractional one a moment later: FastCanvas, which sizes its frames by the buffer, drew them
    // at the scale before (a form at 2 in a buffer of 1.5).
    F.RecreateResources;
    TMessageManager.DefaultManager.SendMessage(nil, TScaleChangedMessage.Create(F));
  except
    Application.HandleException(F);
  end;
end;

procedure TFmuxWindow.DoFrameChanged;
var
  F: TCommonCustomForm;
  L: IFireLinuxWindowFrameListener;
begin
  WlLog(TWlLogLevel.Debug, 'frame of "%s": states $%x capabilities $%x', [Title, StateBits, CapabilityBits]);
  L := FFrameListener;
  F := Form;
  if (L = nil) or (F = nil) or (F.Handle = nil) then
    Exit;
  try
    L.WindowFrameChanged(F.Handle, StateBits, CapabilityBits);
  except
    Application.HandleException(F);
  end;
end;

{$ENDREGION}

{$REGION 'Drag and drop'}

procedure TDragSourceWatch.Notification(AComponent: TComponent; Operation: TOperation);
begin
  inherited;
  if (Operation = opRemove) and (Watched = AComponent) then
    Watched := nil;
  if (Operation = opRemove) and (GDragObject.Source = AComponent) then
    GDragObject.Source := nil;
end;

procedure EndFmDrag(Operation: TWlDragOperation);
var
  Source: TObject;
  Control: IControl;
  Watch: TDragSourceWatch;
  ComponentSource: Boolean;
begin
  Source := GDragObject.Source;
  if Source is TComponent then
    TComponent(Source).RemoveFreeNotification(GDragWatch);
  if (Source is TComponent) and ((csDestroying in TComponent(Source).ComponentState) or
    ((TComponent(Source).Owner <> nil) and (csDestroying in TComponent(Source).Owner.ComponentState))) then
    Source := nil;
  ComponentSource := Source is TComponent;
  GDragObject := Default(TDragObject);
  GDragImage := Default(TWlDragImage);
  Watch := TDragSourceWatch.Create(nil);
  try
    if Source is TComponent then
    begin
      Watch.Watched := TComponent(Source);
      Watch.Watched.FreeNotification(Watch);
    end;
    try
      if Supports(Source, IControl, Control) then
      begin
        if Control.GetDragMode <> TDragMode.dmAutomatic then
          Control.MouseUp(TMouseButton.mbLeft, [], $FFFF, $FFFF);
        if not ComponentSource or (Watch.Watched <> nil) then
          Control.DragEnd;
      end;
    except
      Application.HandleException(nil);
    end;
  finally
    Watch.Free;
  end;
end;

function TFmuxWindow.DoDrag(const Data: TWlDragData; const Event: TWlDragEvent; const Point: TPointF; const Suggested: TWlDragOperation): TWlDragOperation;
var
  Drag: TDragObject;
  Op: TDragOperation;
  F: TCommonCustomForm;
begin
  Result := TWlDragOperation.None;
  F := Form;
  if F = nil then
    Exit;
  try
    if Event = TWlDragEvent.Leave then
    begin
      F.DragLeave;
      Exit;
    end;
    if not InputAllowed(Self) then
      Exit;
    if Data.Internal then
      Drag := GDragObject
    else
    begin
      Drag := Default(TDragObject);
      Drag.Files := Copy(Data.Files);
      if Data.Text <> '' then
        Drag.Data := Data.Text;
    end;
    Op := TDragOperation.None;
    // DragOver leaves Op untouched when FindTarget finds nothing. Begin at None to reject that case.
    F.DragOver(Drag, F.ClientToScreen(Point), Op);
    if (WlDisplay = nil) or not WlDisplay.Windows.Contains(Self) then
      Exit;
    if Event = TWlDragEvent.Drop then
    begin
      if TWlDragOperation(Ord(Op)) <> Suggested then
        Exit;
      F.DragDrop(Drag, F.ClientToScreen(Point));
    end;
    Result := TWlDragOperation(Ord(Op));
  except
    Application.HandleException(F);
  end;
end;

procedure WlBeginDragDrop(Wnd: Pointer; Data, Bitmap: Pointer); cdecl;
var
  Payload: TWlDragData;
begin
  Payload := Default(TWlDragData);
  Payload.Internal := True;
  Payload.Files := Copy(GDragObject.Files);
  if GDragObject.Data.IsType<string>then
    Payload.Text := GDragObject.Data.AsString;
  try
    if (Win(Wnd) = nil) or not InputAllowed(Win(Wnd)) or
      not Disp.BeginDrag(Win(Wnd), Payload, EndFmDrag, GDragImage) then
      EndFmDrag(TWlDragOperation.None);
  except
    EndFmDrag(TWlDragOperation.None);
    Application.HandleException(nil);
  end;
end;

procedure TWaylandDragService.BeginDragDrop(AForm: TCommonCustomForm; const Data: TDragObject; ABitmap: TBitmap);
var
  W: Pointer;
  Map: TBitmapData;
  X, Y: Integer;
begin
  if (AForm = nil) or not (AForm.Handle is TLinuxWindowHandle) then
    Exit;
  Disp.CancelDrag;
  TDragFormAccess(AForm).SetCaptured(nil);
  GDragObject := Data;
  // Automatic FMX drags pass Source only; expose its normal Data property as well.
  if GDragObject.Data.IsEmpty and (Data.Source is TFmxObject) then
    GDragObject.Data := TFmxObject(Data.Source).Data;
  if GDragWatch = nil then
    GDragWatch := TDragSourceWatch.Create(nil);
  if Data.Source is TComponent then
    TComponent(Data.Source).FreeNotification(GDragWatch);
  GDragImage := Default(TWlDragImage);
  if (ABitmap <> nil) and not ABitmap.IsEmpty and (ABitmap.Width <= 512) and (ABitmap.Height <= 512) and
    ABitmap.Map(TMapAccess.Read, Map) then
  try
    GDragImage.Width := ABitmap.Width;
    GDragImage.Height := ABitmap.Height;
    SetLength(GDragImage.Pixels, ABitmap.Width * ABitmap.Height);
    for Y := 0 to ABitmap.Height - 1 do
      for X := 0 to ABitmap.Width - 1 do
        GDragImage.Pixels[Y * ABitmap.Width + X] := Map.GetPixel(X, Y);
  finally
    ABitmap.Unmap(Map);
  end;
  W := TLinuxWindowHandle(AForm.Handle).Window;
  WlBeginDragDrop(W, nil, nil);
end;

procedure RegisterDragService;
begin
  if GDragServiceRegistered then
    Exit;
  if GDragService = nil then
    GDragService := TWaylandDragService.Create;
  TPlatformServices.Current.RemovePlatformService(IFMXDragDropService);
  TPlatformServices.Current.AddPlatformService(IFMXDragDropService, GDragService);
  GDragServiceRegistered := True;
end;

{$ENDREGION}

{$REGION 'TNativeWindowService'}

function TNativeWindowService.WindowOf(const AHandle: TWindowHandle): TFmuxWindow;
var
  P: Pointer;
begin
  Result := nil;
  if (AHandle is TLinuxWindowHandle) and (WlDisplay <> nil) then
  begin
    P := TLinuxWindowHandle(AHandle).Window;
    if (P <> nil) and WlDisplay.Windows.Contains(TWlWindow(P)) then
      Result := TFmuxWindow(P);
  end;
end;

procedure TNativeWindowService.SetConstraints(const AForm: TCommonCustomForm; const AMinWidth, AMinHeight, AMaxWidth, AMaxHeight: Single);
var
  W: TFmuxWindow;
  Ins: TRect;

  function ClientLimit(const Value: Single; const Insets: Integer): Integer;
  begin
    if Value <= 0 then
      Result := 0
    else
      Result := Max(1, Ceil(Value) - Insets);
  end;

begin
  if (AForm = nil) or not AForm.IsHandleAllocated then
    Exit;
  W := WindowOf(AForm.Handle);
  if W = nil then
    Exit;
  Ins := W.NormalDecorationInsets;
  W.SetSizeConstraints(ClientLimit(AMinWidth, Ins.Left + Ins.Right),
    ClientLimit(AMinHeight, Ins.Top + Ins.Bottom), ClientLimit(AMaxWidth, Ins.Left + Ins.Right),
    ClientLimit(AMaxHeight, Ins.Top + Ins.Bottom));
end;

function TNativeWindowService.GetWaylandDisplay: Pointer;
begin
  if WlDisplay <> nil then
    Result := WlDisplay.Display
  else
    Result := nil;
end;

function TNativeWindowService.GetWaylandSurface(const AHandle: TWindowHandle): Pointer;
var
  W: TFmuxWindow;
begin
  W := WindowOf(AHandle);
  if W <> nil then
    Result := W.Surface
  else
    Result := nil;
end;

function TNativeWindowService.GetBufferSize(const AHandle: TWindowHandle): TSize;
var
  W: TFmuxWindow;
begin
  W := WindowOf(AHandle);
  if W <> nil then
    Result := TSize.Create(W.BufferWidth, W.BufferHeight)
  else
    Result := TSize.Create(0, 0);
end;

function TNativeWindowService.GetScale(const AHandle: TWindowHandle): Single;
var
  W: TFmuxWindow;
begin
  W := WindowOf(AHandle);
  if W <> nil then
    Result := W.Scale
  else
    Result := 1;
end;

procedure TNativeWindowService.SetExternalPresentation(const AHandle: TWindowHandle; const AValue: Boolean);
var
  W: TFmuxWindow;
begin
  W := WindowOf(AHandle);
  if W <> nil then
    W.ExternalPresentation := AValue;
end;

{$ENDREGION}

{$REGION 'TWindowFrameService'}

function TWindowFrameService.ToplevelOf(const AHandle: TWindowHandle): TFmuxWindow;
var
  P: Pointer;
begin
  Result := nil;
  if (AHandle is TLinuxWindowHandle) and (WlDisplay <> nil) then
  begin
    P := TLinuxWindowHandle(AHandle).Window;
    if (P <> nil) and WlDisplay.Windows.Contains(TWlWindow(P)) and
      (TWlWindow(P).Kind = TWlWindowKind.Toplevel) then
      Result := TFmuxWindow(P);
  end;
end;

procedure TWindowFrameService.SetDecorated(const AHandle: TWindowHandle; const AValue: Boolean);
var
  W: TFmuxWindow;
begin
  W := ToplevelOf(AHandle);
  if W <> nil then
    W.SetDecorated(AValue);
end;

function TWindowFrameService.GetDecorated(const AHandle: TWindowHandle): Boolean;
var
  W: TFmuxWindow;
begin
  W := ToplevelOf(AHandle);
  Result := (W <> nil) and W.HasDecorations;
end;

function TWindowFrameService.BeginMove(const AHandle: TWindowHandle): Boolean;
var
  W: TFmuxWindow;
begin
  W := ToplevelOf(AHandle);
  Result := (W <> nil) and W.BeginMove;
end;

function TWindowFrameService.BeginResize(const AHandle: TWindowHandle; const AEdges: Cardinal): Boolean;
var
  W: TFmuxWindow;
begin
  W := ToplevelOf(AHandle);
  Result := (W <> nil) and W.BeginResize(AEdges);
end;

function TWindowFrameService.ShowWindowMenu(const AHandle: TWindowHandle; const AClientPoint: TPointF): Boolean;
var
  W: TFmuxWindow;
begin
  W := ToplevelOf(AHandle);
  // Client coordinates are the surface's (the client-side decorations are a subsurface around it).
  Result := (W <> nil) and W.ShowWindowMenu(Round(AClientPoint.X), Round(AClientPoint.Y));
end;

procedure TWindowFrameService.Minimize(const AHandle: TWindowHandle);
var
  W: TFmuxWindow;
begin
  W := ToplevelOf(AHandle);
  if W <> nil then
    W.Minimize;
end;

procedure TWindowFrameService.SetMaximized(const AHandle: TWindowHandle; const AValue: Boolean);
var
  W: TFmuxWindow;
begin
  W := ToplevelOf(AHandle);
  if W <> nil then
    W.SetMaximized(AValue);
end;

function TWindowFrameService.GetStates(const AHandle: TWindowHandle): Cardinal;
var
  W: TFmuxWindow;
begin
  W := ToplevelOf(AHandle);
  if W <> nil then
    Result := W.StateBits
  else
    Result := 0;
end;

function TWindowFrameService.GetCapabilities(const AHandle: TWindowHandle): Cardinal;
var
  W: TFmuxWindow;
begin
  W := ToplevelOf(AHandle);
  if W <> nil then
    Result := W.CapabilityBits
  else
    Result := 0;
end;

procedure TWindowFrameService.SetFrameListener(const AHandle: TWindowHandle; const AListener: IFireLinuxWindowFrameListener);
var
  W: TFmuxWindow;
begin
  W := ToplevelOf(AHandle);
  if W = nil then
    Exit;
  W.FFrameListener := AListener;
  if AListener <> nil then
    AListener.WindowFrameChanged(AHandle, W.StateBits, W.CapabilityBits);
end;

{$ENDREGION}

{$REGION 'Application'}

procedure WlInit(Flags: Integer); cdecl;
var
  Services: TPlatformServices;
begin
  try
    WlConnect;
  except
    on E: Exception do
      raise EWaylandConnectionError.Create(E.Message);
  end;
  Disp.WakeProc :=
    procedure
    begin
      if Assigned(GWakeProc) then
        GWakeProc();
    end;
  if not GNativeServiceRegistered then
  begin
    GNativeServiceRegistered := True;
    TPlatformServices.Current.AddPlatformService(IFireLinuxNativeWindow, TNativeWindowService.Create);
    TPlatformServices.Current.AddPlatformService(IFMXWindowConstraintsService, TNativeWindowService.Create);
    TPlatformServices.Current.AddPlatformService(IFireLinuxWindowFrame, TWindowFrameService.Create);
    // TFont's default family and size (FMX falls back to Tahoma without it), unless someone registered one.
    Services := TPlatformServices.Current;
    if not Services.SupportsPlatformService(IFMXSystemFontService) then
      Services.AddPlatformService(IFMXSystemFontService, TSystemFontService.Create);
  end;
end;

procedure WlRun(IdleProc: TFmuxIdleProc); cdecl;
begin
  Disp.IdleProc :=
    procedure
    begin
      if Assigned(IdleProc) then
        IdleProc();
    end;
  Disp.RunLoop(nil);
end;

procedure WlTerminate; cdecl;
begin
  if WlDisplay <> nil then
    WlDisplay.Terminate;
end;

function WlHandleMessage: Boolean; cdecl;
begin
  Result := Disp.ProcessEvents(0);
end;

procedure WlWakeMainThread(Proc: TFmuxWakeMainThreadProc); cdecl;
var
  D: TWlDisplay;
begin
  // Any thread (TThread.Synchronize/Queue): the procedure runs on the main thread when the loop wakes.
  GWakeProc := Proc;
  D := WlDisplay;
  if D <> nil then
    D.Wake;
end;

function WlCreateTimer(Interval: Integer; TimerFunc: TFmuxTimerProc; Data, Code: Pointer): NativeInt; cdecl;
begin
  Result := Disp.CreateTimer(Interval,
    procedure
    begin
      TimerFunc(Data, Code);
    end);
end;

function WlDestroyTimer(Timer: NativeInt): Boolean; cdecl;
begin
  Result := (WlDisplay <> nil) and WlDisplay.DestroyTimer(Timer);
end;

function WlGetKeyState: Integer; cdecl;
begin
  Result := Disp.ModState;
end;

function WlIsWayland: Boolean; cdecl;
begin
  Result := True;
end;

{$ENDREGION}

{$REGION 'Windows'}

function WlCreateWindow(var CreateStruct: TFmuxCreateStruct): Pointer; cdecl;
var
  W: TFmuxWindow;
  Kind: TWlWindowKind;
begin
  RegisterDragService;
  if CreateStruct.Popup then
    Kind := TWlWindowKind.Popup
  else
    Kind := TWlWindowKind.Toplevel;
  W := TFmuxWindow.Create(Disp, Kind, CreateStruct.Transparent or CreateStruct.Popup);
  W.FCreate := CreateStruct;
  W.FCreate.Title := nil;
  W.ConfigureFrame(CreateStruct.BorderStyle = TFmuxBorderStyle.None,
    CreateStruct.BorderStyle in [TFmuxBorderStyle.Sizeable, TFmuxBorderStyle.SizeToolWin],
    CreateStruct.BorderStyle in [TFmuxBorderStyle.ToolWindow, TFmuxBorderStyle.SizeToolWin],
    CreateStruct.SystemMenuIcon, CreateStruct.MinimizeIcon, CreateStruct.MaximizeIcon);
  if CreateStruct.Title <> nil then
    W.SetTitle(CreateStruct.Title);
  W.SetWindowRect(RectF(CreateStruct.X, CreateStruct.Y, CreateStruct.X + CreateStruct.Width,
      CreateStruct.Y + CreateStruct.Height));
  W.FReportedWidth := W.Width;
  W.FReportedHeight := W.Height;
  WlLog(TWlLogLevel.Debug, 'CreateWindow %p "%s" popup %s %.0f,%.0f %.0fx%.0f', [Pointer(W), W.Title,
      BoolToStr(CreateStruct.Popup, True), CreateStruct.X, CreateStruct.Y, CreateStruct.Width, CreateStruct.Height]);
  Result := W;
end;

procedure WlDestroyWindow(Wnd: Pointer); cdecl;
var
  W: TFmuxWindow;
  I: Integer;
begin
  W := Win(Wnd);
  if W = nil then
    Exit;
  if GMainWindow = W then
    GMainWindow := nil;
  if GModalStack <> nil then
    GModalStack.Remove(W);
  if GImeWindow = W then
  begin
    Disp.EndTextInput(W, False);
    GImeWindow := nil;
    GImeData := nil;
    GImeComposing := False;
  end;
  // Its export for a portal dialog ends with it.
  if GDialogParents <> nil then
    for I := 0 to GDialogParents.Count - 1 do
      if GDialogParents[I] = W then
        GDialogParents[I] := nil;
  W.Free;
end;

procedure WlSetMainWindow(Wnd: Pointer); cdecl;
begin
  GMainWindow := Win(Wnd);
end;

/// The window a popup belongs to: the form of its placement target, else where the user just was.
function PopupParent(const AWindow: TFmuxWindow): TWlWindow;

  function Usable(const W: TWlWindow): Boolean;
  begin
    Result := (W <> nil) and (W <> AWindow) and W.Visible and (W.XdgSurface <> nil) and
      Disp.Windows.Contains(W);
  end;

var
  F: TCommonCustomForm;
  Target: TControl;
  Root: TFmxObject;
  P: Pointer;
begin
  Result := nil;
  F := AWindow.Form;
  if F is TCustomPopupForm then
  begin
    Target := TCustomPopupForm(F).PlacementTarget;
    if (Target <> nil) and (Target.Root <> nil) then
    begin
      Root := Target.Root.GetObject;
      if (Root is TCommonCustomForm) and (TCommonCustomForm(Root).Handle <> nil) then
      begin
        P := FormToWnd(TCommonCustomForm(Root));
        if Usable(TWlWindow(P)) then
          Exit(TWlWindow(P));
        // Its form is not on the screen yet (a popup opened in FormCreate or OnShow): the popup waits for it
        // (TWlWindow.Show).
        if (P <> nil) and (P <> Pointer(AWindow)) and Disp.Windows.Contains(TWlWindow(P)) then
          Exit(TWlWindow(P));
      end;
    end;
  end;
  if Usable(Disp.PointerWindow) then
    Exit(Disp.PointerWindow);
  if Usable(Disp.LastInputWindow) then
    Exit(Disp.LastInputWindow);
  if Usable(Disp.KeyboardWindow) then
    Exit(Disp.KeyboardWindow);
  if Usable(GMainWindow) then
    Exit(GMainWindow);
end;

procedure WlShowWindow(Wnd: Pointer; Show: Boolean); cdecl;
var
  W: TFmuxWindow;
begin
  W := Win(Wnd);
  if W = nil then
    Exit;
  if Show then
  begin
    if W.Kind = TWlWindowKind.Popup then
      W.Parent := PopupParent(W);
    if W.Form <> nil then
    begin
      with W.Form.Constraints do
      begin
        var Service: IFMXWindowConstraintsService;
        if TPlatformServices.Current.SupportsPlatformService(IFMXWindowConstraintsService, Service) then
          Service.SetConstraints(W.Form, MinWidth, MinHeight, MaxWidth, MaxHeight);
      end;
    end;
    if W.FCreate.StayOnTop and (W.Parent = nil) and (GMainWindow <> W) then
      W.Parent := GMainWindow;
    W.Show;
  end
  else
    W.Hide;
end;

procedure WlSetWindowState(Wnd: Pointer; AState: TFmuxWindowState); cdecl;
begin
  if Wnd <> nil then
    Win(Wnd).SetState(TWlWindowState(Ord(AState)));
end;

procedure WlSetWindowTitle(Wnd: Pointer; Title: PChar); cdecl;
begin
  if Wnd <> nil then
    Win(Wnd).SetTitle(Title);
end;

procedure WlSetWindowIcon(Wnd: Pointer; Data: Pointer; Size: Integer); cdecl;
var
  Stream: TMemoryStream;
  Source, Square: TBitmap;
  Map: TBitmapData;
  Pixels: TArray<Cardinal>;
  N, Y: Integer;
begin
  if Wnd = nil then
    Exit;
  if (Data = nil) or (Size <= 0) then
  begin
    Win(Wnd).SetIcon(nil, 0);
    Exit;
  end;
  Stream := TMemoryStream.Create;
  Source := TBitmap.Create;
  Square := nil;
  try
    try
      Stream.WriteBuffer(Data^, Size);
      Stream.Position := 0;
      Source.LoadFromStream(Stream);
      if (Source.Width <= 0) or (Source.Height <= 0) then
        Exit;
      N := Min(256, Max(Source.Width, Source.Height));
      Square := TBitmap.Create(N, N);
      Square.Clear(0);
      if Square.Canvas.BeginScene then
      try
        var Ratio := Min(N / Source.Width, N / Source.Height);
        var W := Source.Width * Ratio;
        var H := Source.Height * Ratio;
        Square.Canvas.DrawBitmap(Source, RectF(0, 0, Source.Width, Source.Height),
          RectF((N - W) / 2, (N - H) / 2, (N + W) / 2, (N + H) / 2), 1);
      finally
        Square.Canvas.EndScene;
      end;
      if Square.Map(TMapAccess.Read, Map) then
      try
        SetLength(Pixels, N * N);
        for Y := 0 to N - 1 do
          Move(Map.GetScanline(Y)^, Pixels[Y * N], N * 4);
        Win(Wnd).SetIcon(Pixels, N);
      finally
        Square.Unmap(Map);
      end;
    except
      on E: Exception do
        WlLogOnce('window-icon', 'cannot decode window icon: ' + E.Message);
    end;
  finally
    Square.Free;
    Source.Free;
    Stream.Free;
  end;
end;

procedure WlActivateWindow(Wnd: Pointer); cdecl;
begin
  // Wayland clients cannot raise or focus windows themselves: an xdg-activation token tied to the last input event.
  if Wnd <> nil then
    Win(Wnd).Activate;
end;

procedure WlWindowBringToFront(Wnd: Pointer); cdecl;
begin
  if Wnd <> nil then
    Win(Wnd).Activate;
end;

procedure WlWindowSendToBack(Wnd: Pointer); cdecl;
begin
end;

procedure WlGetClientSize(Wnd: Pointer; var R: TPointF); cdecl;
begin
  if Wnd <> nil then
    R := PointF(Win(Wnd).Width, Win(Wnd).Height)
  else
    R := PointF(0, 0);
end;

procedure WlSetClientSize(Wnd: Pointer; R: TPointF); cdecl;
var
  W: TFmuxWindow;
  OldW, OldH: Integer;
begin
  if Wnd = nil then
    Exit;
  WlLog(TWlLogLevel.Debug, 'SetClientSize %p %.0fx%.0f', [Wnd, R.X, R.Y]);
  W := Win(Wnd);
  OldW := W.Width;
  OldH := W.Height;
  W.SetSize(Round(R.X), Round(R.Y));
  // FMX reads the new bounds back from the platform (TCommonCustomForm.SetClientWidth sets its bounds from FBounds
  // right after this call), as GTK's synchronous size allocation did for libfmux.
  if (W.Width <> OldW) or (W.Height <> OldH) then
    W.ReportBounds;
end;

procedure WlGetWindowRect(Wnd: Pointer; var R: TRectF); cdecl;
var
  W: TFmuxWindow;
begin
  W := Win(Wnd);
  if W <> nil then
    R := W.WindowRect
  else
    R := TRectF.Empty;
end;

procedure WlSetWindowRect(Wnd: Pointer; R: TRectF); cdecl;
begin
  if Wnd = nil then
    Exit;
  WlLog(TWlLogLevel.Debug, 'SetWindowRect %p %.0f,%.0f %.0fx%.0f', [Wnd, R.Left, R.Top, R.Width, R.Height]);
  Win(Wnd).SetWindowRect(R);
end;

procedure WlInvalidateRect(Wnd: Pointer; R: TRectF); cdecl;
begin
  if Wnd <> nil then
    Win(Wnd).Invalidate(R);
end;

procedure WlProcessUpdates(Wnd: Pointer); cdecl;
begin
  if Wnd <> nil then
    Win(Wnd).PaintNow;
end;

function WlClientToScreen(Wnd: Pointer; Point: TPointF): TPointF; cdecl;
begin
  if Wnd <> nil then
    Result := Win(Wnd).ClientToScreen(Point)
  else
    Result := Point;
end;

function WlScreenToClient(Wnd: Pointer; Point: TPointF): TPointF; cdecl;
begin
  if Wnd <> nil then
    Result := Win(Wnd).ScreenToClient(Point)
  else
    Result := Point;
end;

function WlGetWindowScale(Wnd: Pointer): Single; cdecl;
begin
  if Wnd <> nil then
    Result := Win(Wnd).Scale
  else
    Result := 1;
end;

function WlGetWindowFullScreen(Wnd: Pointer): Boolean; cdecl;
begin
  Result := (Wnd <> nil) and Win(Wnd).FullScreen;
end;

procedure WlSetWindowFullScreen(Wnd: Pointer; AValue: Boolean); cdecl;
begin
  if Wnd <> nil then
    Win(Wnd).SetFullScreen(AValue);
end;

procedure WlSetCapture(Wnd: Pointer); cdecl;
begin
  // Wayland grabs the pointer implicitly while a button is held: the window keeps getting the events.
end;

procedure WlReleaseCapture(Wnd: Pointer); cdecl;
begin
end;

function WlGetWindowNativeHandle(Wnd: Pointer): Pointer; cdecl;
begin
  // Not a GtkWindow: the wl_surface (see also IFireLinuxNativeWindow).
  if Wnd <> nil then
    Result := Win(Wnd).Surface
  else
    Result := nil;
end;

function WlShowModal(Wnd: Pointer; Proc: TFmuxModal): Integer; cdecl;
var
  W: TFmuxWindow;
  R: Integer;
begin
  Result := 0;
  W := Win(Wnd);
  if W = nil then
    Exit;
  if GModalStack = nil then
    GModalStack := TList<TFmuxWindow>.Create;
  if (W.Parent = nil) and (W.Kind = TWlWindowKind.Toplevel) then
  begin
    if TopModalWindow <> nil then
      W.Parent := TopModalWindow
    else if (GMainWindow <> nil) and (GMainWindow <> W) then
      W.Parent := GMainWindow;
    W.SetTransientParent;
  end;
  GModalStack.Add(W);
  try
    R := 0;
    Disp.RunLoop(
      function: Boolean
      begin
        if not Disp.Windows.Contains(W) then
          Exit(True);
        R := 0;
        Proc(W.FCreate.Data, R);
        Result := R <> 0;
      end);
    Result := R;
  finally
    GModalStack.Remove(W);
  end;
end;

{$ENDREGION}

{$REGION 'Screens and pointer'}

function WlGetScreenSize: TPointF; cdecl;
var
  O: TWlOutput;
begin
  O := Disp.PrimaryOutput;
  if O <> nil then
    Result := PointF(O.LogicalBounds.Width, O.LogicalBounds.Height)
  else
    Result := PointF(1920, 1080);
end;

function WlGetScreenScale: Single; cdecl;
var
  O: TWlOutput;
begin
  O := Disp.PrimaryOutput;
  if O <> nil then
    Result := O.Scale
  else
    Result := 1;
end;

function WlGetDisplayInfo(DisplayInfo: PFmuxDisplayInfo; Index: Integer): Integer; cdecl;
var
  Outs: TArray<TWlOutput>;
begin
  Outs := Disp.OrderedOutputs;
  Result := Max(1, Length(Outs));
  if (DisplayInfo = nil) or (Index < 0) or (Index >= Result) then
    Exit;
  DisplayInfo.Primary := Index = 0;
  if Length(Outs) = 0 then
    DisplayInfo.BoundsRect := Rect(0, 0, 1920, 1080)
  else
    DisplayInfo.BoundsRect := Outs[Index].LogicalBounds;
  DisplayInfo.WorkareaRect := DisplayInfo.BoundsRect;
end;

function WlGetDisplayFromPoint(Point: TPoint): Integer; cdecl;
var
  Outs: TArray<TWlOutput>;
  I: Integer;
begin
  Outs := Disp.OrderedOutputs;
  for I := 0 to High(Outs) do
    if Outs[I].LogicalBounds.Contains(Point) then
      Exit(I);
  Result := -1;
end;

function WlGetDisplayFromWindow(Wnd: Pointer): Integer; cdecl;
var
  Outs: TArray<TWlOutput>;
  O: TWlOutput;
  I: Integer;
begin
  Result := 0;
  if Wnd = nil then
    Exit;
  Outs := Disp.OrderedOutputs;
  O := Win(Wnd).CurrentOutput;
  for I := 0 to High(Outs) do
    if Outs[I] = O then
      Exit(I);
  Result := Max(0, WlGetDisplayFromPoint(Win(Wnd).Origin.Round));
end;

function WlGetMousePos: TPointF; cdecl;
begin
  Result := Disp.PointerScreenPos;
end;

procedure WlSetCursor(Cursor: Integer); cdecl;
begin
  Disp.SetCursor(Cursor);
end;

{$ENDREGION}

{$REGION 'Clipboard'}

function WlClipboardHasText: Boolean; cdecl;
begin
  Result := Disp.ClipboardHasText;
end;

function WlClipboardGetText: PChar; cdecl;
begin
  // The string lives until the next call (FMX copies it at once).
  GClipboardText := Disp.ClipboardGetText;
  Result := PChar(GClipboardText);
end;

procedure WlClipboardSetText(Text: PChar); cdecl;
begin
  Disp.ClipboardSetText(Text);
end;

{$ENDREGION}

/// Waits for AFd (the portal's D-Bus connection) the way a modal form waits: the loop goes on (events, timers,
/// painting, FMX's idle processing) until AFd is readable, ATimeoutMs pass or the application terminates (False).
{$REGION 'Portal integration'}

function DialogPump(const AFd, ATimeoutMs: Integer): Boolean;
var
  D: TWlDisplay;
  Ready: Boolean;
  Watch: NativeInt;
  Deadline, Left: Int64;
begin
  D := Disp;
  Ready := False;
  Watch := D.AddFdWatch(AFd, POLLIN,
    procedure
    begin
      Ready := True;
    end);
  try
    Deadline := MonotonicMs + ATimeoutMs;
    while not Ready and not D.Terminated do
    begin
      if not D.ProcessEvents(0) then
      begin
        if Assigned(D.IdleProc) then
          D.IdleProc();
        Left := Deadline - MonotonicMs;
        if Ready or D.Terminated or (Left <= 0) then
          Break;
        D.ProcessEvents(Integer(Left));
      end;
      if MonotonicMs >= Deadline then
        Break;
    end;
  finally
    D.RemoveFdWatch(Watch);
  end;
  Result := not D.Terminated;
end;

/// The toplevel a dialog opened now belongs to: the innermost modal form, else the focused window (the toplevel of
/// a focused popup), else the main window.
function DialogOwner: TFmuxWindow;
var
  W: TWlWindow;
begin
  Result := TopModalWindow;
  if Result <> nil then
    Exit;
  W := Disp.KeyboardWindow;
  if W = nil then
    W := Disp.LastInputWindow;
  while (W <> nil) and (W.Kind = TWlWindowKind.Popup) do
    W := W.Parent;
  if (W <> nil) and Disp.Windows.Contains(W) and W.Visible then
    Exit(TFmuxWindow(W));
  Result := GMainWindow;
end;

/// A portal dialog opens: the program's windows take no input meanwhile, as under a modal form; its owner is
/// exported with xdg-foreign so that the portal can make its dialog a child of it ('' without xdg-foreign).
function DialogBeginModal: string;
var
  W: TFmuxWindow;
  Handle: string;
begin
  if GModalStack = nil then
    GModalStack := TList<TFmuxWindow>.Create;
  if GDialogParents = nil then
    GDialogParents := TList<TFmuxWindow>.Create;
  W := DialogOwner;
  GModalStack.Add(nil);
  Handle := '';
  if W <> nil then
    Handle := W.ExportToplevel;
  if Handle <> '' then
  begin
    GDialogParents.Add(W);
    Result := 'wayland:' + Handle;
  end
  else
  begin
    GDialogParents.Add(nil);
    Result := '';
  end;
end;

/// The portal dialog of the last DialogBeginModal is closed.
procedure DialogEndModal;
var
  W: TFmuxWindow;
  I: Integer;
begin
  if (GDialogParents <> nil) and (GDialogParents.Count > 0) then
  begin
    W := GDialogParents.Last;
    GDialogParents.Delete(GDialogParents.Count - 1);
    if W <> nil then
      W.UnexportToplevel;
  end;
  if GModalStack <> nil then
    for I := GModalStack.Count - 1 downto 0 do
      if GModalStack[I] = nil then
      begin
        GModalStack.Delete(I);
        Break;
      end;
end;

{$ENDREGION}

{$REGION 'Input method'}

function ImeControl: TControl;
var
  Object_: TObject;
begin
  Result := nil;
  if GImeData = nil then
    Exit;
  Object_ := TTextService(GImeData).Owner.GetObject;
  if Object_ is TStyledPresentation then
    Result := TStyledPresentation(Object_).PresentedControl
  else if Object_ is TControl then
    Result := TControl(Object_);
end;

function ImeDocument(Control: TControl; Service: TTextService): string;
begin
  // The modern FMX text service holds only the current line, even for a memo.
  if Control is TCustomMemo then
    Result := TCustomMemo(Control).Lines.Text
  else if Control is TCustomEdit then
    Result := TCustomEdit(Control).Text
  else
    Result := Service.Text;
end;

function ImeTextState: TWaylandTextState;
var
  Service: TTextService;
  TextInput: ITextInput;
  ReadOnly_: IReadOnly;
  Keyboard: IVirtualKeyboardControl;
  CaretOwner: ICaret;
  Caret: TCustomCaret;
  Flasher: IControl;
  Control, Parent: TControl;
  Point: TPointF;
  Bounds: TRect;
  Cursor, Anchor, First, Last: Integer;
  Document: string;
begin
  Result := Default(TWaylandTextState);
  if (GImeWindow = nil) or (GImeData = nil) then
    Exit;
  Service := TTextService(GImeData);
  if not Supports(Service.Owner, ITextInput, TextInput) then
    Exit;
  Control := ImeControl;
  Document := ImeDocument(Control, Service);
  Cursor := TextPointToOffset(Document, Service.CaretPosition);
  Bounds := TextInput.GetSelectionBounds;
  First := TextPointToOffset(Document, Bounds.TopLeft);
  Last := TextPointToOffset(Document, Bounds.BottomRight);
  if Cursor = First then
    Anchor := Last
  else
    Anchor := First;
  Result := MakeSurrounding(Document, Cursor, Anchor);
  Result.Enabled := InputAllowed(GImeWindow) and (Service.ImeMode <> TImeMode.imDisable);
  if (Control <> nil) and Supports(Control, IReadOnly, ReadOnly_) then
    Result.Enabled := Result.Enabled and not ReadOnly_.ReadOnly;
  if Service.Multiline then
    Result.Hint := ZWP_TEXT_INPUT_V3_CONTENT_HINT_MULTILINE;
  // Never expose passwords as surrounding text to the desktop IME.
  if (Control <> nil) and Supports(Control, IVirtualKeyboardControl, Keyboard) and Keyboard.IsPassword then
  begin
    Result.HasSurrounding := False;
    Result.Text := '';
    Result.Cursor := 0;
    Result.Anchor := 0;
    Result.Hint := ZWP_TEXT_INPUT_V3_CONTENT_HINT_HIDDEN_TEXT or ZWP_TEXT_INPUT_V3_CONTENT_HINT_SENSITIVE_DATA;
    Result.Purpose := ZWP_TEXT_INPUT_V3_CONTENT_PURPOSE_PASSWORD;
  end;
  if not ((Control is TCustomEdit) or (Control is TCustomMemo)) then
  begin
    Result.HasSurrounding := False;
    Result.Text := '';
    Result.Cursor := 0;
    Result.Anchor := 0;
  end;
  Point := TextInput.GetTargetClausePointF;
  Result.CursorRect := Rect(Round(Point.X), Round(Point.Y), Round(Point.X) + 1, Round(Point.Y) + 18);
  if (Control <> nil) and Supports(Control, ICaret, CaretOwner) then
  begin
    Caret := CaretOwner.GetObject;
    if (Caret <> nil) and Supports(Caret.Flasher, IControl, Flasher) then
    begin
      Parent := TControl(Flasher.GetObject).ParentControl;
      if Parent = nil then
        Parent := Control;
      Point := Parent.LocalToAbsolute(Caret.Pos);
      Result.CursorRect := Rect(Floor(Point.X), Floor(Point.Y),
        Ceil(Point.X + Max(1, Caret.Size.Width)), Ceil(Point.Y + Max(1, Caret.Size.Height)));
    end;
  end;
end;

procedure CancelImeComposition;
var
  Data: Pointer;
  Proc: TFmuxImeCommitProc;
begin
  Data := GImeData;
  Proc := GImeChanged;
  if not GImeComposing then
    Exit;
  GImeComposing := False;
  if (Data <> nil) and Assigned(Proc) then
    Proc(Data, nil);
end;

procedure DeleteImeSurrounding(Before_, After_: Cardinal);
var
  Service: TTextService;
  TextInput: ITextInput;
  Control: TControl;
  Bytes: UTF8String;
  Document: string;
  Bounds: TRect;
  First, Last, BeforeCount, AfterCount, StartByte, EndByte: Integer;

  procedure SelectAndDelete(Start, Count: Integer);
  begin
    if Count = 0 then
      Exit;
    if Control is TCustomEdit then
    begin
      TCustomEdit(Control).SelStart := Start;
      if GImeData <> Pointer(Service) then
        Exit;
      TCustomEdit(Control).SelLength := Count;
      if GImeData <> Pointer(Service) then
        Exit;
      TCustomEdit(Control).DeleteSelection;
    end
    else if Control is TCustomMemo then
    begin
      TCustomMemo(Control).SelStart := Start;
      if GImeData <> Pointer(Service) then
        Exit;
      TCustomMemo(Control).SelLength := Count;
      if GImeData <> Pointer(Service) then
        Exit;
      TCustomMemo(Control).DeleteSelection;
    end;
  end;

begin
  if (Before_ = 0) and (After_ = 0) then
    Exit;
  Service := TTextService(GImeData);
  if not Supports(Service.Owner, ITextInput, TextInput) then
    Exit;
  Control := ImeControl;
  Document := ImeDocument(Control, Service);
  Bounds := TextInput.GetSelectionBounds;
  First := TextPointToOffset(Document, Bounds.TopLeft);
  Last := TextPointToOffset(Document, Bounds.BottomRight);
  Bytes := UTF8String(Document);
  StartByte := Length(UTF8String(Copy(Document, 1, First)));
  EndByte := Length(UTF8String(Copy(Document, 1, Last)));
  if (Before_ > Cardinal(StartByte)) or (After_ > Cardinal(Length(Bytes) - EndByte)) then
    raise EArgumentException.Create('IME deletion exceeds the surrounding text');
  BeforeCount := Utf8RangeToUtf16(Bytes, StartByte - Integer(Before_), Before_);
  AfterCount := Utf8RangeToUtf16(Bytes, EndByte, After_);
  // Delete after the selection first, so indices before it remain stable.
  SelectAndDelete(Last, AfterCount);
  if GImeData <> Pointer(Service) then
    Exit;
  SelectAndDelete(First - BeforeCount, BeforeCount);
  if GImeData <> Pointer(Service) then
    Exit;
  if Control is TCustomEdit then
  begin
    TCustomEdit(Control).SelStart := First - BeforeCount;
    TCustomEdit(Control).SelLength := Last - First;
  end
  else if Control is TCustomMemo then
  begin
    TCustomMemo(Control).SelStart := First - BeforeCount;
    TCustomMemo(Control).SelLength := Last - First;
  end;
end;

procedure ApplyImeBatch(const Batch: TWaylandTextBatch);
var
  Data: Pointer;
  Window: TFmuxWindow;
  Empty: Char;
begin
  Data := GImeData;
  Window := GImeWindow;
  if (Data = nil) or (Window = nil) or not InputAllowed(Window) then
    Exit;
  try
    // All text-input events are applied as a single done transaction.
    Empty := #0;
    if GImeComposing and Assigned(GImeChanged) then
      GImeChanged(Data, @Empty);
    if (Data <> GImeData) or (Window <> GImeWindow) then
      Exit;
    DeleteImeSurrounding(Batch.BeforeLength, Batch.AfterLength);
    if (Data <> GImeData) or (Window <> GImeWindow) then
      Exit;
    if Batch.Commit <> '' then
    begin
      if not GImeComposing and Assigned(GImeStart) then
      begin
        GImeComposing := True;
        GImeStart(Data, nil);
      end;
      if (Data <> GImeData) or (Window <> GImeWindow) then
        Exit;
      GImeComposing := False;
      if Assigned(GImeCommit) then
        GImeCommit(Data, PChar(Batch.Commit));
    end;
    if (Data <> GImeData) or (Window <> GImeWindow) then
      Exit;
    if Batch.Preedit <> '' then
    begin
      if not GImeComposing and Assigned(GImeStart) then
      begin
        GImeComposing := True;
        GImeStart(Data, PChar(Batch.Preedit));
      end;
      if (Data <> GImeData) or (Window <> GImeWindow) then
        Exit;
      if Assigned(GImeChanged) then
        GImeChanged(Data, PChar(Batch.Preedit));
    end
    else
      CancelImeComposition;
  except
    Application.HandleException(nil);
  end;
end;

procedure WlImeEnterControl(Wnd: Pointer; StartProc, ChangedProc, CommitProc: TFmuxImeCommitProc; Rect: TRect; Data: Pointer); cdecl;
begin
  if Wnd = nil then
    Exit;
  CancelImeComposition;
  GImeWindow := Win(Wnd);
  GImeData := Data;
  GImeStart := StartProc;
  GImeChanged := ChangedProc;
  GImeCommit := CommitProc;
  if (GImeWindow = nil) or (GImeData = nil) then
    Exit;
  Disp.BeginTextInput(GImeWindow,
    function: TWaylandTextState
    begin
      Result := ImeTextState;
    end,
    procedure(Batch: TWaylandTextBatch)
    begin
      ApplyImeBatch(Batch);
    end,
    procedure
    begin
      CancelImeComposition;
    end);
end;

procedure WlImeExitControl(Wnd: Pointer); cdecl;
begin
  if (GImeWindow = nil) or (GImeWindow <> Win(Wnd)) then
    Exit;
  Disp.EndTextInput(GImeWindow, False); // TLinuxTextService.ExitControl ends its own composition immediately after us.
  GImeWindow := nil;
  GImeData := nil;
  GImeComposing := False;
  GImeStart := nil;
  GImeChanged := nil;
  GImeCommit := nil;
end;

procedure WlImeSetCaretPos(Value: TPoint); cdecl;
begin
  // Value is a text index (column/line), not a pixel coordinate. Poll the actual caret after FMX updates it.
end;

{$ENDREGION}

function WaylandEglDisplay: Pointer;
begin
  Result := WlConnect.Display;
end;

procedure AssignWaylandApi;
begin
  GDumpDir := GetEnvironmentVariable('FIRELINUX_DUMP_DIR');
  FMUX.Api.FmuxInit := WlInit;
  FMUX.Api.FmuxRun := WlRun;
  FMUX.Api.FmuxTerminate := WlTerminate;
  FMUX.Api.FmuxHandleMessage := WlHandleMessage;
  FMUX.Api.FmuxWakeMainThread := WlWakeMainThread;
  FMUX.Api.FmuxCreateTimer := WlCreateTimer;
  FMUX.Api.FmuxDestroyTimer := WlDestroyTimer;
  FMUX.Api.FmuxGetKeyState := WlGetKeyState;
  FMUX.Api.IsWayland := WlIsWayland;

  FMUX.Api.FmuxCreateWindow := WlCreateWindow;
  FMUX.Api.FmuxDestroyWindow := WlDestroyWindow;
  FMUX.Api.FmuxSetMainWindow := WlSetMainWindow;
  FMUX.Api.FmuxShowWindow := WlShowWindow;
  FMUX.Api.FmuxSetWindowState := WlSetWindowState;
  FMUX.Api.FmuxSetWindowTitle := WlSetWindowTitle;
  FMUX.Api.FmuxSetWindowIcon := WlSetWindowIcon; // partial: compositor icon requires xdg-toplevel-icon-v1
  FMUX.Api.FmuxActivateWindow := WlActivateWindow; // partial: xdg-activation request (compositor decides)
  FMUX.Api.FmuxWindowBringToFront := WlWindowBringToFront; // partial: xdg-activation request (compositor decides)
  FMUX.Api.FmuxWindowSendToBack := WlWindowSendToBack; // partial: no-op on Wayland
  FMUX.Api.FmuxGetClientSize := WlGetClientSize;
  FMUX.Api.FmuxSetClientSize := WlSetClientSize;
  FMUX.Api.FmuxGetWindowRect := WlGetWindowRect;
  FMUX.Api.FmuxSetWindowRect := WlSetWindowRect; // partial: the position of toplevels is virtual
  FMUX.Api.FmuxInvalidateRect := WlInvalidateRect;
  FMUX.Api.FmuxProcessUpdates := WlProcessUpdates;
  FMUX.Api.FmuxClientToScreen := WlClientToScreen;
  FMUX.Api.FmuxScreenToClient := WlScreenToClient;
  FMUX.Api.FmuxGetWindowScale := WlGetWindowScale;
  FMUX.Api.FmuxGetWindowFullScreen := WlGetWindowFullScreen;
  FMUX.Api.FmuxSetWindowFullScreen := WlSetWindowFullScreen;
  FMUX.Api.FmuxSetCapture := WlSetCapture; // partial: Wayland's implicit grab
  FMUX.Api.FmuxReleaseCapture := WlReleaseCapture; // partial: Wayland's implicit grab
  FMUX.Api.FmuxGetWindowNativeHandle := WlGetWindowNativeHandle; // partial: returns the wl_surface
  FMUX.Api.FmuxGetWindowNativeDrawingHandle := WlGetWindowNativeHandle; // partial: returns the wl_surface
  FMUX.Api.FmuxShowModal := WlShowModal;

  FMUX.Api.FmuxGetScreenSize := WlGetScreenSize;
  FMUX.Api.FmuxGetScreenScale := WlGetScreenScale;
  FMUX.Api.FmuxGetDisplayInfo := WlGetDisplayInfo; // partial: work area = whole output
  FMUX.Api.FmuxGetDisplayFromWindow := WlGetDisplayFromWindow;
  FMUX.Api.FmuxGetDisplayFromPoint := WlGetDisplayFromPoint;
  FMUX.Api.FmuxGetMousePos := WlGetMousePos; // partial: last position over an own window
  FMUX.Api.FmuxSetCursor := WlSetCursor;


  FMUX.Api.FmuxClipboardHasText := WlClipboardHasText;
  FMUX.Api.FmuxClipboardGetText := WlClipboardGetText;
  FMUX.Api.FmuxClipboardSetText := WlClipboardSetText;

  ConfigureDialogHooks(DialogPump, DialogBeginModal, DialogEndModal);

  FMUX.Api.FmuxImeEnterControl := WlImeEnterControl; // partial: FMUX callbacks have no preedit cursor/segment attributes
  FMUX.Api.FmuxImeExitControl := WlImeExitControl;
  FMUX.Api.FmuxImeSetCaretPos := WlImeSetCaretPos;
  FMUX.Api.FmuxBeginDragDrop := WlBeginDragDrop;
  ConfigureOpenGL(TEglPlatform.Wayland, WaylandEglDisplay);
end;

initialization
finalization
  GDragObject := Default(TDragObject);
  GDragWatch.Free;
  GDragService := nil;
  FreeAndNil(GDialogParents);
  FreeAndNil(GModalStack);
  ShutdownOpenGL;
  WlDisconnect;

end.

