{ Shared raster buffer passed to FMX's raster canvas by the display backends. MIT license, see LICENSE. }
unit FireLinux.RasterFrame;

interface

type
  /// <summary>Premultiplied BGRA pixels at device resolution. Bits is nil during external presentation.</summary>
  TRasterFrame = record
    Bits: Pointer;
    Stride: Integer;
    Width: Integer;
    Height: Integer;
    Scale: Single;
    /// <summary>Set by the renderer after writing the frame.</summary>
    Drawn: Boolean;
  end;
  PRasterFrame = ^TRasterFrame;

implementation

end.
