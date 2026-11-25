{ Shared FMUX callbacks for the X11 and Wayland backends. MIT license, see LICENSE. }
unit FireLinux.Fmux;

interface

procedure AssignSharedFmuxApi;

implementation

uses
  System.SysUtils, System.Types, System.UITypes, System.Math, FMX.Dialogs,
  FMX.DialogHelper, FMUX.Api, FireLinux.Cairo, FireLinux.Log, FireLinux.OpenGL,
  FireLinux.RasterFrame, FireLinux.Dialogs, FireLinux.DialogTypes;

var
  GVersionInfo: TFmuxVersionInfo;

procedure SetLog(Log: TFmuxLog); cdecl;
begin
  // FMX passes a procedure that writes to stdout; FireLinux logs to stderr itself (FIRELINUX_LOG).
end;

procedure GetVersionInfo(var VI: TFmuxVersionInfo); cdecl;
begin
  VI := GVersionInfo;
end;

procedure SetVersionInfo(var VI: TFmuxVersionInfo); cdecl;
begin
  GVersionInfo := VI;
end;

function IsBroadway: Boolean; cdecl;
begin
  Result := False;
end;

{$REGION 'Bitmaps and the paint context'}

function BitmapCreate(Width, Height: Integer; Bits: Pointer): Pointer; cdecl;
var
  B: PFmuxBitmap;
begin
  New(B);
  B.Width := Max(0, Width);
  B.Height := Max(0, Height);
  B.OwnsData := Bits = nil;
  if B.OwnsData then
    B.Data := AllocMem(NativeInt(B.Width) * B.Height * 4)
  else
    B.Data := Bits;
  Result := B;
end;

procedure BitmapDestroy(Bitmap: Pointer); cdecl;
var
  B: PFmuxBitmap;
begin
  B := Bitmap;
  if B = nil then
    Exit;
  if B.OwnsData then
    FreeMem(B.Data);
  Dispose(B);
end;

procedure GetBitmapInfo(Bitmap: Pointer; var Width, Height: Integer; var Data: Pointer); cdecl;
var
  B: PFmuxBitmap;
begin
  B := Bitmap;
  if B = nil then
  begin
    Width := 0;
    Height := 0;
    Data := nil;
    Exit;
  end;
  Width := B.Width;
  Height := B.Height;
  Data := B.Data;
end;

/// Source-over of premultiplied ASrc with opacity AOpacity (0..256) onto ADst.
function Blend(const ADst, ASrc: Cardinal; const AOpacity: Cardinal): Cardinal; inline;
var
  SA, InvA: Cardinal;
  RB, G: Cardinal;
begin
  RB := (((ASrc and $00FF00FF) * AOpacity) shr 8) and $00FF00FF;
  G := (((ASrc shr 8) and $00FF00FF) * AOpacity) and $FF00FF00;
  SA := G shr 24;
  InvA := 255 - SA;
  Result := (RB or G) + ((((ADst and $00FF00FF) * InvA) shr 8) and $00FF00FF) +
    ((((ADst shr 8) and $00FF00FF) * InvA) and $FF00FF00);
end;

procedure CanvasDrawBitmap(Ctx, Bitmap: Pointer; Src, Dst: TRectF; Opacity: Single; HighSpeed: Boolean); cdecl;
var
  F: PRasterFrame;
  B: PFmuxBitmap;
  DX, DY, DW, DH, SX, SY, SW, SH, X, Y, CX, CY, CW, CH, SrcX, SrcY: Integer;
  DRow, SRow: PCardinal;
  Op: Cardinal;
begin
  // FMX's cairo canvas (its window and bitmap contexts); the Skia raster canvas passes the frame.
  if IsCairoContext(Ctx) then
  begin
    CairoDrawBitmap(Ctx, Bitmap, Src, Dst, Opacity, HighSpeed);
    Exit;
  end;
  F := Ctx;
  B := Bitmap;
  if (F = nil) or (B = nil) or (B.Data = nil) then
    Exit;
  if F.Bits = nil then
  begin
    // External presentation: nothing to copy, but the frame counts as painted.
    F.Drawn := True;
    Exit;
  end;
  // Destination in buffer pixels; source in bitmap pixels.
  DX := Round(Dst.Left * F.Scale);
  DY := Round(Dst.Top * F.Scale);
  DW := Round(Dst.Width * F.Scale);
  DH := Round(Dst.Height * F.Scale);
  SX := Round(Src.Left);
  SY := Round(Src.Top);
  SW := Round(Src.Width);
  SH := Round(Src.Height);
  if (DW <= 0) or (DH <= 0) or (SW <= 0) or (SH <= 0) then
    Exit;
  Op := EnsureRange(Round(Opacity * 256), 0, 256);
  // Clip the destination to the frame.
  CX := Max(DX, 0);
  CY := Max(DY, 0);
  CW := Min(DX + DW, F.Width) - CX;
  CH := Min(DY + DH, F.Height) - CY;
  if (CW <= 0) or (CH <= 0) then
    Exit;
  if (DW = SW) and (DH = SH) and (Op >= 256) then
  begin
    // 1:1 copy (the Skia raster canvas always draws so): rows clipped to the bitmap too.
    SrcX := SX + (CX - DX);
    CW := Min(CW, B.Width - SrcX);
    for Y := CY to CY + CH - 1 do
    begin
      SrcY := SY + (Y - DY);
      if (SrcY < 0) or (SrcY >= B.Height) or (CW <= 0) or (SrcX < 0) then
        Continue;
      Move((PByte(B.Data) + (NativeInt(SrcY) * B.Width + SrcX) * 4)^,
        (PByte(F.Bits) + NativeInt(Y) * F.Stride + CX * 4)^, CW * 4);
    end;
  end
  else
  begin
    // Scaled (nearest neighbour) and/or with opacity.
    for Y := CY to CY + CH - 1 do
    begin
      SrcY := SY + ((Y - DY) * SH) div DH;
      if (SrcY < 0) or (SrcY >= B.Height) then
        Continue;
      SRow := PCardinal(PByte(B.Data) + NativeInt(SrcY) * B.Width * 4);
      DRow := PCardinal(PByte(F.Bits) + NativeInt(Y) * F.Stride + CX * 4);
      for X := CX to CX + CW - 1 do
      begin
        SrcX := SX + ((X - DX) * SW) div DW;
        if (SrcX >= 0) and (SrcX < B.Width) then
        begin
          if Op >= 256 then
            DRow^ := PCardinal(PByte(SRow) + SrcX * 4)^
          else
            DRow^ := Blend(DRow^, PCardinal(PByte(SRow) + SrcX * 4)^, Op);
        end;
        Inc(DRow);
      end;
    end;
  end;
  F.Drawn := True;
end;

{$ENDREGION}

{$REGION 'Dialogs'}

const
  CDialogButtonBits: array[TMsgDlgBtn] of Integer = (FMUX_BTN_Yes, FMUX_BTN_No, FMUX_BTN_OK, FMUX_BTN_Cancel,
    FMUX_BTN_Abort, FMUX_BTN_Retry, FMUX_BTN_Ignore, FMUX_BTN_All, FMUX_BTN_NoToAll, FMUX_BTN_YesToAll,
    FMUX_BTN_Help, FMUX_BTN_Close);

function MessageDialog(AMessage: PChar; DlgType, Buttons: Integer): Integer; cdecl;
var
  Btns: TMsgDlgButtons;
  B, Default: TMsgDlgBtn;
begin
  // FMX passes no default button: the first affirmative one is.
  Btns := [];
  for B := Low(TMsgDlgBtn) to High(TMsgDlgBtn) do
    if Buttons and CDialogButtonBits[B] <> 0 then
      Include(Btns, B);
  if Btns = [] then
    Btns := [TMsgDlgBtn.mbOK];
  Default := TMsgDlgBtn.mbOK;
  for B in [TMsgDlgBtn.mbOK, TMsgDlgBtn.mbYes, TMsgDlgBtn.mbRetry, TMsgDlgBtn.mbIgnore, TMsgDlgBtn.mbClose] do
    if B in Btns then
    begin
      Default := B;
      Break;
    end;
  // The backend's message dialog: by default FMX's own dialog form (FMX.DialogHelper), modal.
  Result := GetFireLinuxDialogBackend.MessageDialog(string(AMessage),
    TMsgDlgType(EnsureRange(DlgType, Ord(Low(TMsgDlgType)), Ord(High(TMsgDlgType)))), Btns, Default);
end;

/// The filters of an FMX filter string: "name|patterns|name|patterns..." with patterns separated by ';'.
function ParseFilter(const AFilter: string): TArray<TFireLinuxFileFilter>;
var
  Parts, Patterns: TArray<string>;
  Pattern: string;
  F: TFireLinuxFileFilter;
  I: Integer;
begin
  Result := nil;
  if AFilter.Trim = '' then
    Exit;
  Parts := AFilter.Split(['|']);
  I := 0;
  while I < Length(Parts) do
  begin
    Patterns := nil;
    if I + 1 < Length(Parts) then
      for Pattern in Parts[I + 1].Split([';']) do
        if Pattern.Trim <> '' then
          Patterns := Patterns + [Pattern.Trim];
    if Patterns = nil then
      Patterns := ['*'];
    F.Name := Parts[I].Trim;
    if F.Name = '' then
      F.Name := string.Join(';', Patterns);
    F.Patterns := Patterns;
    Result := Result + [F];
    Inc(I, 2);
  end;
end;

function FilesDialog(Title, Filter, InitialName, InitialDir, Files: PChar; MaxLength: Integer; var FilterIndex: Integer; AOptions: Integer): Boolean; cdecl;
var
  Request: TFireLinuxFileDialogRequest;
  Paths: TArray<string>;
  Backend: IFireLinuxDialogBackend;
  SelectedIndex: Integer;
  Output: string;
begin
  MessageDialogCheckInUIThread;
  Result := False;
  if (Files = nil) or (MaxLength <= 0) then
    Exit;
  Files^ := #0;
  Request := Default(TFireLinuxFileDialogRequest);
  if AOptions and FMUX_FilesDialog_FOLDER <> 0 then
    Request.Kind := TFireLinuxFileDialogKind.SelectFolder
  else if AOptions and FMUX_FilesDialog_SAVE <> 0 then
    Request.Kind := TFireLinuxFileDialogKind.SaveFile
  else
    Request.Kind := TFireLinuxFileDialogKind.OpenFile;
  Request.Title := string(Title);
  Request.InitialFile := string(InitialName);
  Request.InitialFolder := string(InitialDir);
  Request.FilterIndex := FilterIndex;
  Request.Multiple := (AOptions and FMUX_FilesDialog_MULTY <> 0) and
    (Request.Kind <> TFireLinuxFileDialogKind.SaveFile);
  Request.ConfirmOverwrite := AOptions and FMUX_FilesDialog_OVERWRITE <> 0;
  Request.Filters := ParseFilter(string(Filter));
  WlLog(TWlLogLevel.Debug, 'files dialog kind %d "%s" filter "%s" name "%s" folder "%s" options $%x',
    [Ord(Request.Kind), Request.Title, string(Filter), Request.InitialFile, Request.InitialFolder, AOptions]);
  Backend := GetFireLinuxDialogBackend;
  SelectedIndex := FilterIndex;
  if not Backend.FileDialog(Request, Paths, SelectedIndex) then
    Exit;
  if Length(Paths) = 0 then
    raise EArgumentException.Create('Dialog backend returned no files');
  if ((not Request.Multiple) or (Request.Kind = TFireLinuxFileDialogKind.SaveFile)) and (Length(Paths) <> 1) then
    raise EArgumentException.Create('Dialog backend returned multiple files for a single selection');
  for Output in Paths do
    if (Output = '') or Output.Contains(#0) or Output.Contains(#10) or Output.Contains(#13) then
      raise EArgumentException.Create('Invalid filename returned by dialog backend');
  Output := string.Join(#10, Paths);
  if Length(Output) >= MaxLength then
    raise EArgumentException.Create('Selected filenames exceed the FMUX file dialog buffer');
  Move(PChar(Output)^, Files^, (Length(Output) + 1) * SizeOf(Char));
  FilterIndex := SelectedIndex;
  Result := True;
end;

function InputQuery(ACaption, APrompt, AValue: PChar; MaxLength: Integer): Boolean; cdecl;
var
  Backend: IFireLinuxDialogBackend;
  Values: TArray<string>;
begin
  MessageDialogCheckInUIThread;
  Result := False;
  if (AValue = nil) or (MaxLength <= 0) then
    Exit;
  Backend := GetFireLinuxDialogBackend;
  Values := [string(AValue)];
  if not Backend.InputQuery(string(ACaption), [string(APrompt)], Values) then
    Exit;
  if (Length(Values) <> 1) or (Length(Values[0]) >= MaxLength) or Values[0].Contains(#0) then
    raise EArgumentException.Create('Input result exceeds the FMUX input buffer');
  Move(PChar(Values[0])^, AValue^, (Length(Values[0]) + 1) * SizeOf(Char));
  Result := True;
end;

{$ENDREGION}

function ClipboardHasImage: Boolean; cdecl;
begin
  Result := False;
end;

procedure ClipboardGetImage(Data: Pointer; var W, H: Integer); cdecl;
begin
  W := 0;
  H := 0;
end;

function ClipboardHasCustom(Format: PChar): Boolean; cdecl;
begin
  Result := False;
end;

procedure ClipboardGetCustom(Format: PChar; Data: Pointer; var Size: Integer); cdecl;
begin
  Size := 0;
end;

procedure AddTooltip(Wnd: Pointer; Text: PChar); cdecl;
begin
end;

procedure RemoveTooltip(Wnd: Pointer); cdecl;
begin
end;

procedure AddGestureRecognizer(Wnd: Pointer; ARec: Integer); cdecl;
begin
end;

procedure RemoveGestureRecognizer(Wnd: Pointer; ARec: Integer); cdecl;
begin
end;

procedure AssignSharedFmuxApi;
begin
  FMUX.Api.FmuxSetLog := SetLog; // partial: FireLinux logs to stderr itself (FIRELINUX_LOG)
  FMUX.Api.FmuxGetVersionInfo := GetVersionInfo;
  FMUX.Api.FmuxSetVersionInfo := SetVersionInfo;
  FMUX.Api.IsBroadway := IsBroadway;
  FMUX.Api.FmuxAddTooltip := AddTooltip; // partial: no-op (no native tooltips)
  FMUX.Api.FmuxRemoveTooltip := RemoveTooltip; // partial: no-op
  FMUX.Api.FmuxAddGestureRecognizer := AddGestureRecognizer; // partial: no-op (no touch gestures yet)
  FMUX.Api.FmuxRemoveGestureRecognizer := RemoveGestureRecognizer; // partial: no-op
  FMUX.Api.FmuxBitmapCreate := BitmapCreate;
  FMUX.Api.FmuxBitmapDestroy := BitmapDestroy;
  FMUX.Api.FmuxGetBitmapInfo := GetBitmapInfo;
  FMUX.Api.FmuxCanvasDrawBitmap := CanvasDrawBitmap;
  FMUX.Api.FmuxClipboardHasImage := ClipboardHasImage; // partial: no images yet (always False)
  FMUX.Api.FmuxClipboardGetImage := ClipboardGetImage; // partial: no images yet
  FMUX.Api.FmuxClipboardHasCustom := ClipboardHasCustom; // partial: no custom formats yet (always False)
  FMUX.Api.FmuxClipboardGetCustom := ClipboardGetCustom; // partial: no custom formats yet
  FMUX.Api.FmuxMessageDialog := MessageDialog; // partial: FMX's own dialog form (or the dialog backend's)
  FMUX.Api.FmuxInputQuery := InputQuery; // partial: the dialog backend's (FMX uses its own form anyway)
  FMUX.Api.FmuxFilesDialog := FilesDialog;
  FMUX.Api.FmuxCreateSharedContext := CreateSharedOpenGLContext;
  FMUX.Api.FmuxCreateThreadContext := CreateThreadOpenGLContext;
  FMUX.Api.FmuxMakeCurrentContext := MakeOpenGLContextCurrent;
  AssignCairoApi;
end;

end.

