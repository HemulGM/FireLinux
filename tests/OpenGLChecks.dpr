program OpenGLChecks;

// Build with tools/build.ps1; run in a Wayland session (DISPLAY may be unset).
uses
  System.StartUpCopy, System.SysUtils, System.Types, System.UITypes, System.Classes,
  FMX.Forms, FMX.Types, FMX.Types3D, FMX.Graphics, FMUX.Api, Linuxapi.OpenGL,
  FMXWayland.OpenGL,
  HelloMain,
  HelloWindow;

procedure Check(Value: Boolean; const Name: string);
begin
  if not Value then raise Exception.Create('FAIL: ' + Name);
  Writeln('PASS: ' + Name);
end;

procedure CheckSharedTextures;
var
  Main: Pointer;
  Texture: Cardinal;
  Worker: TThread;
  WorkerError: string;
  SharedTexture: Boolean;
begin
  Main := FmuxCreateSharedContext;
  Check(Main <> nil, 'shared desktop OpenGL context');
  Writeln('OpenGL: ', string(PAnsiChar(glGetString(GL_VERSION))));
  glGenTextures(1, @Texture);
  glBindTexture(GL_TEXTURE_2D, Texture);
  glTexImage2D(GL_TEXTURE_2D, 0, GL_RGBA8, 2, 2, 0, GL_RGBA, GL_UNSIGNED_BYTE, nil);
  glFinish;
  SharedTexture := False;
  Worker := TThread.CreateAnonymousThread(
    procedure
    begin
      try
        FmuxMakeCurrentContext(FmuxCreateThreadContext);
        SharedTexture := glIsTexture(Texture) <> 0;
        FmuxMakeCurrentContext(nil);
      except on E: Exception do WorkerError := E.Message; end;
    end);
  Worker.FreeOnTerminate := False;
  try
    Worker.Start;
    Worker.WaitFor;
  finally
    Worker.Free;
  end;
  FmuxMakeCurrentContext(Main);
  glDeleteTextures(1, @Texture);
  Check(WorkerError = '', 'worker context: ' + WorkerError);
  Check(SharedTexture, 'textures shared between main and worker contexts');
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
    CheckRenderTarget;
    CheckSharedTextures;
    CheckViewport;
    Writeln('All OpenGL checks passed');
  except on E: Exception do begin Writeln(ErrOutput, E.ClassName + ': ' + E.Message); Halt(1); end; end;
end.
