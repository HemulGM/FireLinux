program CairoChecks;

// Compile with tools/build.ps1, run in a Wayland session. No Skia library is required.
uses
  System.StartUpCopy, System.SysUtils, System.Types, System.UITypes, System.Classes,
  FMX.Forms, FMX.Types, FMX.Graphics, FMX.TextLayout,
  FMUX.Api, FMXWayland.Cairo;

procedure Check(Value: Boolean; const Name: string);
begin
  if not Value then
    raise Exception.Create('FAIL: ' + Name);
  Writeln('PASS: ' + Name);
end;

function CodecRead(Param: Pointer; Bits: Pointer; Count: LongWord): Integer; cdecl;
begin
  if Bits = nil then Exit(TStream(Param).Size);
  TStream(Param).ReadBuffer(Bits^, Count);
  Result := 0;
end;

function CodecWrite(Param: Pointer; Bits: Pointer; Count: LongWord): Integer; cdecl;
begin
  TStream(Param).WriteBuffer(Bits^, Count);
  Result := 0;
end;

procedure CheckRaster;
var
  Bitmap: TBitmap;
  Data: TBitmapData;
  Pixel: Cardinal;
  Pixels: array[0..1023] of Cardinal;
  Context: Pointer;
begin
  Bitmap := TBitmap.Create(32, 32);
  try
    Check(Bitmap.Canvas.ClassName = 'TLinuxCanvas', 'FMX uses Cairo canvas');
    Bitmap.Clear(0);
    Check(Bitmap.Canvas.BeginScene, 'offscreen Cairo context');
    try
      Bitmap.Canvas.Fill.Color := $FFFF0000;
      Bitmap.Canvas.FillRect(RectF(0, 0, 16, 16), 0, 0, [], 0.5);
    finally
      Bitmap.Canvas.EndScene;
    end;
    Check(Bitmap.Map(TMapAccess.Read, Data), 'map Cairo pixels');
    try
      Pixel := PCardinal(PByte(Data.GetScanline(8)) + 8 * 4)^;
      Check((Pixel shr 24 >= 127) and (Pixel shr 24 <= 129), 'solid opacity applied once');
      Check(((Pixel shr 16) and 255) = (Pixel shr 24), 'premultiplied BGRA');
    finally
      Bitmap.Unmap(Data);
    end;
  finally
    Bitmap.Free;
  end;

  FillChar(Pixels, SizeOf(Pixels), 0);
  Context := CreateCairoFrame(@Pixels[0], 32, 32, 32 * 4, 2);
  try
    FmuxCanvasSetMatrix(Context, 1, 0, 0, 1, 2, 2);
    FmuxCanvasSetFillColor(Context, $FFFFFFFF);
    FmuxCanvasRect(Context, RectF(0, 0, 4, 4));
    FmuxCanvasFill(Context, 1);
  finally
    DestroyCairoFrame(Context);
  end;
  Check(Pixels[5 * 32 + 5] = $FFFFFFFF, '2x transform and translation');
  Check(Pixels[2 * 32 + 2] = 0, '2x transform leaves outside untouched');
  Context := CreateCairoFrame(@Pixels[0], 32, 32, 32 * 4, 2);
  try
    FmuxSave(Context);
    FmuxCanvasSetMatrix(Context, 1, 0, 0, 1, 0, 0);
    FmuxExcludeClipRect(Context, RectF(4, 4, 6, 6));
    FmuxCanvasSetFillColor(Context, $FF0000FF);
    FmuxCanvasRect(Context, RectF(0, 0, 16, 16));
    FmuxCanvasFill(Context, 1);
    FmuxRestore(Context);
  finally
    DestroyCairoFrame(Context);
  end;
  Check(Pixels[9 * 32 + 9] = $FFFFFFFF, 'exclude clip at 2x');
  Check(Pixels[20 * 32 + 20] = $FF0000FF, 'fill outside excluded clip');
end;

procedure CheckRepaints(const Scale: Single);
const
  Width = 64;
  Height = 64;
  Background = $FFEEEEEE;
var
  Partial, Reference: array[0..Width * Height - 1] of Cardinal;
  Context: Pointer;
  Previous, Current, Dirty: TRectF;
  Step, I: Integer;

  procedure DrawShape;
  begin
    FmuxCanvasSetFillColor(Context, $FF1177CC);
    FmuxCanvasRect(Context, Current);
    FmuxCanvasFill(Context, 1);
  end;

begin
  for I := 0 to High(Partial) do Partial[I] := Background;
  Previous := TRectF.Empty;
  for Step := 0 to 79 do
  begin
    Current := RectF(8.23 + Sin(Step * 0.3) * 3.5, 9.61 + Cos(Step * 0.2) * 2.75, 0, 0);
    Current.Right := Current.Left + 11.19;
    Current.Bottom := Current.Top + 8.43;
    if Step = 0 then Dirty := Current else Dirty := TRectF.Union(Previous, Current);
    Context := CreateCairoFrame(@Partial[0], Width, Height, Width * 4, Scale);
    try
      FmuxSetClipRects(Context, @Dirty, 1);
      FmuxCanvasClearRect(Context, Dirty, Background);
      DrawShape;
    finally
      DestroyCairoFrame(Context);
    end;
    Context := CreateCairoFrame(@Reference[0], Width, Height, Width * 4, Scale);
    try
      FmuxCanvasClear(Context, Background);
      DrawShape;
    finally
      DestroyCairoFrame(Context);
    end;
    if not CompareMem(@Partial[0], @Reference[0], SizeOf(Partial)) then
      raise Exception.CreateFmt('FAIL: partial repaint differs from full frame, scale %.2f, step %d', [Scale, Step]);
    Previous := Current;
  end;
  Check(True, Format('80 partial repaints match full frames at scale %.2f', [Scale]));
end;

procedure CheckText;
var
  Font: TFmuxFont;
  Family, Text: string;
  Layout: Pointer;
  Rects: array[0..5] of TRectF;
  Bounds: TRectF;
  Point: TPointF;
  Path: TArray<TFmuxPathPoint>;
  N, Index: Integer;
begin
  Family := 'sans';
  Font := Default(TFmuxFont);
  Font.Family := PChar(Family);
  Font.Size := 18;
  Font.Weight := 4; // TFontWeight.Regular
  Text := 'AéЖ😀Z';
  Layout := FmuxCreateTextLayout(PChar(Text), Font, 500, 100, 0, 0, False);
  try
    FmuxGetTextLayoutRect(Layout, Bounds);
    Check((Bounds.Width > 40) and (Bounds.Height > 10), 'Unicode text metrics');
    N := FmuxLayoutMeasureRange(Layout, 0, Text.Length, @Rects[0]);
    Check(N = 6, 'UTF-16 range length');
    Check(Rects[3] = Rects[4], 'surrogate pair maps to one glyph');
    Point := PointF(Rects[5].Left + 0.1, Rects[5].CenterPoint.Y);
    Index := FmuxLayoutPositionAtPoint(Layout, @Point);
    Check(Index = 5, 'UTF-8 hit testing returns UTF-16 index');
    N := FmuxLayoutToPath(Layout, nil, 0);
    SetLength(Path, N);
    Check((N > 10) and (FmuxLayoutToPath(Layout, @Path[0], N) = N), 'text outlines to FMX path');
  finally
    FmuxDestroyTextLayout(Layout);
  end;
  Layout := FmuxCreateTextLayout('Перенос текста по словам', Font, 80, 200, 0, 0, True);
  try
    FmuxGetTextLayoutRect(Layout, Bounds);
    Check(Bounds.Height > 35, 'Cyrillic wrapping');
  finally
    FmuxDestroyTextLayout(Layout);
  end;
end;

procedure CheckCodec(const Extension: string);
var
  Pixels: array[0..3] of Cardinal;
  Stream: TMemoryStream;
  Bitmap, Bits: Pointer;
  W, H: Integer;
begin
  Pixels[0] := $FFFF0000; Pixels[1] := $80008000;
  Pixels[2] := $FF0000FF; Pixels[3] := 0;
  Stream := TMemoryStream.Create;
  try
    Check(FmuxBitmapSave(CodecWrite, Stream, 2, 2, @Pixels[0], PChar(Extension)), Extension + ' encode');
    Stream.Position := 0;
    Bitmap := FmuxBitmapLoad(CodecRead, Stream, W, H, Bits);
    try
      Check((Bitmap <> nil) and (W = 2) and (H = 2), Extension + ' decode');
      if Extension = '.png' then
        Check(CompareMem(Bits, @Pixels[0], SizeOf(Pixels)), 'PNG alpha round trip');
    finally
      FmuxBitmapDestroy(Bitmap);
    end;
  finally
    Stream.Free;
  end;
end;

begin
  try
    Application.Initialize;
    CheckRaster;
    CheckRepaints(1);
    CheckRepaints(1.5);
    CheckRepaints(2);
    CheckText;
    CheckCodec('.png');
    CheckCodec('.jpg');
    Writeln('All Cairo checks passed');
  except
    on E: Exception do
    begin
      Writeln(ErrOutput, E.ClassName + ': ' + E.Message);
      Halt(1);
    end;
  end;
end.
