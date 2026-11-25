{ FMXWayland: desktop OpenGL contexts over EGL on Wayland and X11. MIT license. }
unit FMXWayland.OpenGL;

interface

// FMX.Context.Linux owns rendering, shaders and FBOs. This unit owns only the
// native context lifetime. No window EGL surface is needed by TViewport3D.
function CreateSharedOpenGLContext: Pointer; cdecl;

function CreateThreadOpenGLContext: Pointer; cdecl;

procedure MakeOpenGLContextCurrent(Context: Pointer); cdecl;

procedure ShutdownOpenGL;

implementation

uses
  System.SysUtils, System.Generics.Collections, Posix.Dlfcn, FMUX.Api,
  FMXWayland.Platform;

type
  TEGLContext = class
    Handle: Pointer;
  end;

  TGetPlatformDisplay = function(platform: Cardinal; NativeDisplay: Pointer; Attributes: PInteger): Pointer; cdecl;

const
  EGL_NONE = $3038;
  EGL_OPENGL_API = $30A2;
  EGL_PLATFORM_X11_EXT = $31D5;
  EGL_PLATFORM_WAYLAND_EXT = $31D8;
  ConfigAttributes: array[0..12] of Integer = (
    $3033, $0004, // EGL_SURFACE_TYPE, EGL_WINDOW_BIT (Wayland configs)
    $3040, $0008, // EGL_RENDERABLE_TYPE, EGL_OPENGL_BIT (desktop compatibility GL)
    $3024, 8, $3023, 8, $3022, 8, $3021, 8, EGL_NONE);
  ContextAttributes: array[0..0] of Integer = (EGL_NONE);

var
  LibraryHandle: NativeUInt;
  Display, Config: Pointer;
  Shared: TEGLContext;
  Contexts: TObjectList<TEGLContext>;
  Lock: TObject;
  eglGetProcAddress: function(Name: PAnsiChar): Pointer; cdecl;
  eglInitialize: function(Dpy: Pointer; Major, Minor: PInteger): Cardinal; cdecl;
  eglBindAPI: function(Api: Cardinal): Cardinal; cdecl;
  eglChooseConfig: function(Dpy: Pointer; Attributes: PInteger; Configs: PPointer; ConfigSize: Integer; Count: PInteger): Cardinal; cdecl;
  eglCreateContext: function(Dpy, Cfg, Share: Pointer; Attributes: PInteger): Pointer; cdecl;
  eglMakeCurrent: function(Dpy, Draw, ReadSurface, Ctx: Pointer): Cardinal; cdecl;
  eglDestroyContext: function(Dpy, Ctx: Pointer): Cardinal; cdecl;
  eglTerminate: function(Dpy: Pointer): Cardinal; cdecl;
  eglGetError: function: Integer; cdecl;
  eglQueryString: function(Dpy: Pointer; Name: Integer): PAnsiChar; cdecl;

procedure Check(Success: Boolean; const Operation: string);
begin
  if not Success then
    raise Exception.CreateFmt('OpenGL: %s failed (EGL 0x%s)', [Operation, IntToHex(eglGetError(), 4)]);
end;

function Symbol(const Name: PAnsiChar): Pointer;
begin
  Result := dlsym(LibraryHandle, Name);
  if Result = nil then
    raise Exception.CreateFmt('OpenGL: libEGL.so.1 has no %s', [string(Name)]);
end;

procedure Initialize;
var
  GetPlatformDisplay: TGetPlatformDisplay;
  Count: Integer;
  Candidate: Pointer;
begin
  if Display <> nil then
    Exit;
  if LibraryHandle = 0 then
  begin
    LibraryHandle := dlopen('libEGL.so.1', RTLD_NOW or RTLD_LOCAL);
    if LibraryHandle = 0 then
      raise Exception.Create('OpenGL: cannot load system libEGL.so.1');
  end;
  @eglGetProcAddress := Symbol('eglGetProcAddress');
  @eglInitialize := Symbol('eglInitialize');
  @eglBindAPI := Symbol('eglBindAPI');
  @eglChooseConfig := Symbol('eglChooseConfig');
  @eglCreateContext := Symbol('eglCreateContext');
  @eglMakeCurrent := Symbol('eglMakeCurrent');
  @eglDestroyContext := Symbol('eglDestroyContext');
  @eglTerminate := Symbol('eglTerminate');
  @eglGetError := Symbol('eglGetError');
  @eglQueryString := Symbol('eglQueryString');
  @GetPlatformDisplay := eglGetProcAddress('eglGetPlatformDisplayEXT');
  if not Assigned(GetPlatformDisplay) then
    raise Exception.Create('OpenGL: eglGetPlatformDisplayEXT is required');
  if Assigned(FMUX.Api.IsWayland) and not FMUX.Api.IsWayland() then
    Candidate := GetPlatformDisplay(EGL_PLATFORM_X11_EXT, nil, nil)
  else
    Candidate := GetPlatformDisplay(EGL_PLATFORM_WAYLAND_EXT, WlConnect.Display, nil);
  Check(Candidate <> nil, 'get platform display');
  Check(eglInitialize(Candidate, nil, nil) <> 0, 'initialize platform display');
  try
    if not (' ' + string(eglQueryString(Candidate, $3055)) + ' ').Contains(' EGL_KHR_surfaceless_context ') then
      raise Exception.Create('OpenGL: EGL_KHR_surfaceless_context is required for offscreen rendering');
    Check(eglBindAPI(EGL_OPENGL_API) <> 0, 'bind desktop OpenGL');
    Count := 0;
    Check(eglChooseConfig(Candidate, @ConfigAttributes[0], @Config, 1, @Count) <> 0,
      'choose configuration');
    if Count = 0 then
      raise Exception.Create('OpenGL: no desktop OpenGL Wayland configuration');
    Contexts := TObjectList<TEGLContext>.Create(True);
    Display := Candidate;
  except
    eglTerminate(Candidate);
    raise;
  end;
end;

function NewContext(Share: Pointer): TEGLContext;
begin
  // EGL API binding is thread local, including on worker threads.
  Check(eglBindAPI(EGL_OPENGL_API) <> 0, 'bind desktop OpenGL');
  Result := TEGLContext.Create;
  try
    Result.Handle := eglCreateContext(Display, Config, Share, @ContextAttributes[0]);
    Check(Result.Handle <> nil, 'create compatibility context');
    // TViewport3D renders exclusively into FMX-owned FBOs. A surfaceless
    // context avoids wl_egl_window and leaves Cairo's wl_shm presentation intact.
    MakeOpenGLContextCurrent(Result);
    Contexts.Add(Result);
  except
    if Result.Handle <> nil then
      eglDestroyContext(Display, Result.Handle);
    Result.Free;
    raise;
  end;
end;

function CreateSharedOpenGLContext: Pointer; cdecl;
begin
  TMonitor.Enter(Lock);
  try
    Initialize;
    if Shared = nil then
      Shared := NewContext(nil);
    MakeOpenGLContextCurrent(Shared);
    Result := Shared;
  finally
    TMonitor.Exit(Lock);
  end;
end;

function CreateThreadOpenGLContext: Pointer; cdecl;
begin
  TMonitor.Enter(Lock);
  try
    if Shared = nil then
      CreateSharedOpenGLContext;
    Result := NewContext(Shared.Handle);
  finally
    TMonitor.Exit(Lock);
  end;
end;

procedure MakeOpenGLContextCurrent(Context: Pointer); cdecl;
var
  Native: TEGLContext;
begin
  if Display = nil then
    raise Exception.Create('OpenGL: display is not initialized');
  if Context = nil then
    Check(eglMakeCurrent(Display, nil, nil, nil) <> 0, 'release current context')
  else
  begin
    Native := TEGLContext(Context);
    Check(eglMakeCurrent(Display, nil, nil, Native.Handle) <> 0,
      'make context current');
  end;
end;

procedure ShutdownOpenGL;
var
  Native: TEGLContext;
begin
  // Called after FMX has freed its GL objects, before disconnecting wl_display.
  if Display <> nil then
  begin
    eglMakeCurrent(Display, nil, nil, nil);
    for Native in Contexts do
    begin
      eglDestroyContext(Display, Native.Handle);
    end;
    FreeAndNil(Contexts);
    Shared := nil;
    eglTerminate(Display);
    Display := nil;
  end;
  // Keep the loader resident: FMX units may still finalize GL entry points.
end;

initialization
  Lock := TObject.Create;

finalization
  Lock.Free;

end.

