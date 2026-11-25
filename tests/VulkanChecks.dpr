program VulkanChecks;

// Build with tools/build.ps1; run in a Wayland session (DISPLAY may be unset).
uses
  System.StartUpCopy, System.SysUtils, System.Types, System.UITypes, System.Classes,
  FMX.Forms, FMX.Types, FMX.Types3D, FMX.Graphics, FMUX.Api,
  FMXWayland.Vulkan, FMX.Materials, System.Math.Vectors,
  HelloMain,
  HelloWindow;

{$I FMXWayland.VulkanShaders.inc}

type
  TSPIRVMaterial = class(TMaterial)
  private
    VS, PS: TContextShader;
  protected
    procedure DoInitialize; override;
    procedure DoApply(const Context: TContext3D); override;
  public
    destructor Destroy; override;
  end;

procedure TSPIRVMaterial.DoInitialize;
begin
  VS := TContextShader.Create;
  VS.LoadFromData('vulkan-test.fvs', TContextShaderKind.VertexShader, '', []);
  PS := TContextShader.Create;
  PS.LoadFromData('vulkan-test.fps', TContextShaderKind.PixelShader, '', []);
  RegisterVulkanShader(VS, ViewportVertSPV);
  RegisterVulkanShader(PS, ViewportFragSPV);
end;

procedure TSPIRVMaterial.DoApply(const Context: TContext3D);
begin
  Context.SetShaders(VS, PS);
  Context.SetShaderVariable('MVPMatrix', Context.CurrentModelViewProjectionMatrix);
  Context.SetShaderVariable('MaterialColor', TAlphaColor($FFCC22AA));
  Context.SetShaderVariable('Opacity', [Vector3D(1, 0, 0, 0)]);
  Context.SetShaderVariable('VulkanParams', [Vector3D(0, 0, 0, 0)]);
end;

destructor TSPIRVMaterial.Destroy;
begin VS.Free; PS.Free; inherited; end;

procedure Check(Value: Boolean; const Name: string);
begin
  if not Value then raise Exception.Create('FAIL: ' + Name);
  Writeln('PASS: ' + Name);
end;

procedure CheckRenderTarget;
var
  Texture: TTexture;
  Context: TContext3D;
  Pixels: array[0..1023] of Cardinal;
begin
  Texture := TTexture.Create;
  try
    Texture.Style := [TTextureStyle.RenderTarget];
    Texture.SetSize(32, 32);
    Context := TContextManager.CreateFromTexture(Texture, TMultisample.None, True);
    try
      Check(Context.BeginScene, 'FBO with depth/stencil');
      try
        Context.Clear([TClearTarget.Color, TClearTarget.Depth, TClearTarget.Stencil],
          $FF336699, 1, 0);
      finally Context.EndScene; end;
      Context.CopyToBits(@Pixels[0], 32 * 4, Rect(0, 0, 32, 32));
      Check((Pixels[0] = $FF336699) and (Pixels[1023] = $FF336699),
        'BGRA readback matches clear color');
    finally Context.Free; end;
  finally Texture.Free; end;
end;

procedure CheckRasterStates;
var
  Target, Sample: TTexture;
  Context: TContext3D;
  Vertices: TVertexBuffer;
  Indices: TIndexBuffer;
  Color: TColorMaterial;
  Textured: TTextureMaterial;
  Custom: TSPIRVMaterial;
  Projection: TMatrix3D;
  Pixels: array[0..1023] of Cardinal;
  Texels: array[0..3] of Cardinal;
  Crop: array[0..1151] of Cardinal;
  Checker: array[0..4095] of Cardinal;
  Secondary: TTexture;
  SecondaryContext: TContext3D;

  procedure Quad(const AColor: TAlphaColor; Z: Single; Opacity: Single = 1);
  begin
    Color.Color := AColor;
    for var I := 0 to 3 do Vertices.Vertices[I] :=
      Point3D(Vertices.Vertices[I].X, Vertices.Vertices[I].Y, Z);
    Context.DrawTriangles(Vertices, Indices, Color, Opacity);
  end;

  procedure BeginFrame;
  begin
    Check(Context.BeginScene, 'begin raster state frame');
    Context.SetContextState(TContextState.cs2DScene);
    Context.SetContextState(TContextState.csAllFace);
    Context.SetContextState(TContextState.csColorWriteOn);
    Context.SetContextState(TContextState.csScissorOff);
    Context.SetContextState(TContextState.csStencilOff);
    Context.SetContextState(TContextState.csZTestOff);
    Context.SetContextState(TContextState.csZWriteOff);
    Context.SetContextState(TContextState.csAlphaBlendOff);
    Context.Clear([TClearTarget.Color, TClearTarget.Depth, TClearTarget.Stencil], $FF000000, 1, 0);
  end;

  procedure EndFrame;
  begin
    Context.EndScene;
    Context.CopyToBits(@Pixels[0], 128, Rect(0, 0, 32, 32));
  end;

begin
  Target := TTexture.Create;
  Sample := TTexture.Create;
  Vertices := TVertexBuffer.Create([TVertexFormat.Vertex, TVertexFormat.TexCoord0], 4);
  Indices := TIndexBuffer.Create(6, TIndexFormat.UInt32);
  Color := TColorMaterial.Create;
  Textured := TTextureMaterial.Create;
  Custom := TSPIRVMaterial.Create;
  Context := nil;
  try
    Target.Style := [TTextureStyle.RenderTarget]; Target.SetSize(32, 32);
    Context := TContextManager.CreateFromTexture(Target, TMultisample.None, True);
    Projection := TMatrix3D.Identity;
    Projection.m41 := 0.00001; // Explicit clip-space projection through FMX's render-to matrix API.
    Context.SetRenderToMatrix(Projection);
    Vertices.Vertices[0] := Point3D(-1, -1, 0.2);
    Vertices.Vertices[1] := Point3D(1, -1, 0.2);
    Vertices.Vertices[2] := Point3D(-1, 1, 0.2);
    Vertices.Vertices[3] := Point3D(1, 1, 0.2);
    Vertices.TexCoord0[0] := PointF(0, 1); Vertices.TexCoord0[1] := PointF(1, 1);
    Vertices.TexCoord0[2] := PointF(0, 0); Vertices.TexCoord0[3] := PointF(1, 0);
    Indices[0] := 0; Indices[1] := 1; Indices[2] := 2;
    Indices[3] := 2; Indices[4] := 1; Indices[5] := 3;
    BeginFrame;
    Context.SetContextState(TContextState.csZTestOn);
    Context.SetContextState(TContextState.csZWriteOn);
    Quad($FFFF0000, 0.2);
    Quad($FF0000FF, 0.8);
    EndFrame;
    Check(Pixels[16 * 32 + 16] = $FFFF0000, 'depth test hides later geometry behind foreground');
    BeginFrame;
    Quad($FFFF0000, 0.2);
    Context.SetContextState(TContextState.csAlphaBlendOn);
    Quad($FF00FF00, 0.2, 0.5);
    EndFrame;
    Check((Abs(Integer((Pixels[528] shr 16) and 255) - 127) <= 1) and
      (Abs(Integer((Pixels[528] shr 8) and 255) - 128) <= 1), 'premultiplied opacity blending');
    BeginFrame;
    Context.SetScissorRect(RectF(0, 0, 16, 32));
    Context.SetContextState(TContextState.csScissorOn);
    Quad($FF00FF00, 0.2);
    EndFrame;
    Check((Pixels[16 * 32 + 8] = $FF00FF00) and (Pixels[16 * 32 + 24] = $FF000000), 'scissor clips to logical rectangle');
    BeginFrame;
    Context.SetContextState(TContextState.csStencilOn);
    Context.SetStencilFunc(TStencilFunc.Always, 1, 255);
    Context.SetStencilOp(TStencilOp.Replace, TStencilOp.Replace, TStencilOp.Replace);
    Context.SetContextState(TContextState.csColorWriteOff);
    Context.SetScissorRect(RectF(0, 0, 16, 32));
    Context.SetContextState(TContextState.csScissorOn);
    Quad($FFFFFFFF, 0.2);
    Context.SetContextState(TContextState.csScissorOff);
    Context.SetContextState(TContextState.csColorWriteOn);
    Context.SetStencilFunc(TStencilFunc.Equal, 1, 255);
    Context.SetStencilOp(TStencilOp.Keep, TStencilOp.Keep, TStencilOp.Keep);
    Quad($FF0000FF, 0.2);
    EndFrame;
    Check((Pixels[16 * 32 + 8] = $FF0000FF) and (Pixels[16 * 32 + 24] = $FF000000), 'stencil mask and color write state');
    Sample.SetSize(2, 2);
    Sample.MinFilter := TTextureFilter.Nearest; Sample.MagFilter := TTextureFilter.Nearest;
    Texels[0] := $FFFF0000; Texels[1] := $FF00FF00; Texels[2] := $FF0000FF; Texels[3] := $FFFFFFFF;
    Sample.UpdateTexture(@Texels[0], 8);
    Textured.Texture := Sample;
    BeginFrame;
    Context.DrawTriangles(Vertices, Indices, Textured, 1);
    EndFrame;
    Check((Pixels[8 * 32 + 8] = $FFFF0000) and (Pixels[8 * 32 + 24] = $FF00FF00) and
      (Pixels[24 * 32 + 8] = $FF0000FF), 'texture channels, orientation and nearest sampling');
    BeginFrame;
    Context.DrawTriangles(Vertices, Indices, Textured, 1);
    Texels[0] := $FF00FFFF; Texels[1] := $FF00FFFF; Texels[2] := $FF00FFFF; Texels[3] := $FF00FFFF;
    Sample.UpdateTexture(@Texels[0], 8);
    Context.SetScissorRect(RectF(16, 0, 32, 32));
    Context.SetContextState(TContextState.csScissorOn);
    Context.DrawTriangles(Vertices, Indices, Textured, 1);
    EndFrame;
    Check((Pixels[8 * 32 + 8] = $FFFF0000) and (Pixels[8 * 32 + 24] = $FF00FFFF),
      'texture replacement retains resources referenced by earlier draws');
    for var I := 0 to High(Crop) do Crop[I] := $12345678;
    Context.CopyToBits(@Crop[0], 36 * 4, Rect(4, 4, 12, 12));
    Check((Crop[0] = $12345678) and (Crop[4 * 36 + 4] = $FFFF0000) and
      (Crop[4 * 36 + 12] = $12345678), 'partial readback preserves destination coordinates and padding');
    Secondary := TTexture.Create;
    SecondaryContext := nil;
    try
      Secondary.Style := [TTextureStyle.RenderTarget]; Secondary.SetSize(32, 32);
      SecondaryContext := TContextManager.CreateFromTexture(Secondary, TMultisample.None, False);
      SecondaryContext.SetRenderToMatrix(Projection);
      Check(SecondaryContext.BeginScene, 'begin second render target');
      try
        SecondaryContext.SetContextState(TContextState.cs2DScene);
        SecondaryContext.SetContextState(TContextState.csAllFace);
        SecondaryContext.SetContextState(TContextState.csScissorOff);
        SecondaryContext.SetContextState(TContextState.csStencilOff);
        SecondaryContext.SetContextState(TContextState.csAlphaBlendOff);
        Textured.Texture := Target;
        SecondaryContext.DrawTriangles(Vertices, Indices, Textured, 1);
      finally SecondaryContext.EndScene; end;
      SecondaryContext.CopyToBits(@Pixels[0], 128, Rect(0, 0, 32, 32));
      Check((Pixels[8 * 32 + 8] = $FFFF0000) and (Pixels[8 * 32 + 24] = $FF00FFFF),
        'render target sampled by another context without a vertical flip');
    finally SecondaryContext.Free; Secondary.Free; end;
    Textured.Texture := Sample;
    for var I := 0 to 3 do Texels[I] := $80800000;
    Sample.UpdateTexture(@Texels[0], 8);
    BeginFrame;
    Quad($FF0000FF, 0.2);
    Context.SetContextState(TContextState.csAlphaBlendOn);
    Context.DrawTriangles(Vertices, Indices, Textured, 1);
    EndFrame;
    Check((Abs(Integer((Pixels[528] shr 16) and 255) - 128) <= 1) and
      (Abs(Integer(Pixels[528] and 255) - 127) <= 1), 'transparent texture is premultiplied exactly once');
    Sample.SetSize(64, 64);
    for var Y := 0 to 63 do
      for var X := 0 to 63 do
        if Odd(X + Y) then Checker[Y * 64 + X] := $FFFF0000 else Checker[Y * 64 + X] := $FF0000FF;
    Sample.UpdateTexture(@Checker[0], 64 * 4);
    BeginFrame;
    Context.DrawTriangles(Vertices, Indices, Textured, 1);
    EndFrame;
    Check((Abs(Integer((Pixels[528] shr 16) and 255) - 128) <= 1) and
      (Abs(Integer(Pixels[528] and 255) - 128) <= 1), 'generated mipmaps filter minified checkerboard');
    BeginFrame;
    Context.DrawTriangles(Vertices, Indices, Custom, 1);
    EndFrame;
    Check(Pixels[528] = $FFCC22AA, 'registered custom SPIR-V shader pair renders through FMX');
    Textured.Texture := Target;
    Check(Context.BeginScene, 'begin feedback rejection frame');
    try
      try
        Context.DrawTriangles(Vertices, Indices, Textured, 1);
        Check(False, 'active render target sampling must fail');
      except on E: EContext3DException do
        Check(E.Message.Contains('active render target'), 'active target feedback rejected explicitly'); end;
    finally Context.EndScene; end;
  finally
    Custom.Free; Textured.Free; Color.Free; Indices.Free; Vertices.Free; Context.Free; Sample.Free; Target.Free;
  end;
end;

procedure CheckViewport;
var
  Form: THelloForm;
  Before, After: TBitmap;
  A, B: TBitmapData;
  Changed, Shapes, X, Y: Integer;

  procedure Capture(Bitmap: TBitmap);
  begin
    Bitmap.SetSize(Round(Form.Viewport3D1.Width), Round(Form.Viewport3D1.Height));
    Check(Bitmap.Canvas.BeginScene, 'Cairo capture');
    try Form.Viewport3D1.PaintTo(Bitmap.Canvas, Bitmap.BoundsF);
    finally Bitmap.Canvas.EndScene; end;
  end;

begin
  Form := THelloForm.Create(nil);
  Before := TBitmap.Create;
  After := TBitmap.Create;
  try
    Form.SceneSpin.IsChecked := False;
    Form.DemoTabs.ActiveTab := Form.TabItem3D;
    Form.Show;
    for X := 1 to 20 do begin Application.ProcessMessages; TThread.Sleep(10); end;
    Capture(Before);
    Check(Form.Viewport3D1.Context <> nil, 'real TViewport3D creates context');
    Form.SceneCube.RotationAngle.Y := Form.SceneCube.RotationAngle.Y + 65;
    Capture(After);
    Check(Before.Map(TMapAccess.Read, A), 'first frame map');
    try
      Check(After.Map(TMapAccess.Read, B), 'second frame map');
      try
        Changed := 0; Shapes := 0;
        for Y := 0 to Before.Height - 1 do
          for X := 0 to Before.Width - 1 do
          begin
            if A.GetPixel(X, Y) <> $FF192331 then Inc(Shapes);
            if A.GetPixel(X, Y) <> B.GetPixel(X, Y) then Inc(Changed);
          end;
        Check(Shapes > 1000, 'lit meshes rendered through Cairo readback');
        Check(Changed > 100, 'rotation changes actual rendered pixels');
      finally After.Unmap(B); end;
    finally Before.Unmap(A); end;
    Form.Viewport3D1.Multisample := TMultisample.None;
    Form.ClientWidth := 760;
    Application.ProcessMessages;
    Capture(After);
    Check(After.Width = Round(Form.Viewport3D1.Width), 'resize and MSAA recreation');
    Form.Viewport3D1.Multisample := TMultisample.FourSamples;
    Capture(After);
    Check(Form.Viewport3D1.Context.BeginScene, 'restored multisample context');
    Form.Viewport3D1.Context.EndScene;
  finally
    After.Free; Before.Free; Form.Free;
  end;
end;

begin
  try
    Application.Initialize;
    RegisterVulkanContext;
    Writeln('Vulkan: ', VulkanRendererName);
    Check(TContextManager.DefaultContextClass = TVulkanContext, 'Vulkan selected without OpenGL fallback');
    CheckRenderTarget;
    CheckRasterStates;

    CheckViewport;
    Writeln('All Vulkan checks passed');
  except on E: Exception do begin Writeln(ErrOutput, E.ClassName + ': ' + E.Message); Halt(1); end; end;
end.
