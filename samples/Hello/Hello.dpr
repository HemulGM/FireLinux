program Hello;

{ FMXWayland sample: streamed FMX forms with tabs for controls, animations/images, dialogs and the platform.

  Command line:
    --quit-after=N   closes the main form after N seconds (tests: clean exit)
    --verbose        writes events and control positions to stdout
    --tab=images|dialogs|platform|drag|3d  selects the initial demo tab
    --3d=opengl|vulkan  selects the 3D backend before any FMX textures are created
    --selftest       runs the non-interactive integration checks
    --backend-probe  opens the fixture used by the compositor tests
    --own-titlebar   opens the custom window frame sample }

uses
  System.StartUpCopy,
  System.SysUtils,
  FMX.Forms,
  FMX.Types,
{$IFDEF FMXWAYLAND_DPROJ}
  // The MSBuild pre-build generates this file for the selected configuration.
  // It must take precedence over FMUX.Api.pas beside the project from older builds.
  {$IFDEF DEBUG}
  FMUX.Api in '..\..\gen\Linux64\Debug\FMUX.Api.pas',
  {$ELSE}
  FMUX.Api in '..\..\gen\Linux64\Release\FMUX.Api.pas',
  {$ENDIF}
{$ENDIF}
{$IF Defined(FASTCANVAS)}
  HelloFastCanvas in 'HelloFastCanvas.pas',
{$ELSEIF Defined(SKIA) and not Defined(NOSKIA)}
  FMX.Skia,
{$IFEND}
  HelloBackendProbe in 'HelloBackendProbe.pas' {HelloBackendProbeForm},
  HelloTitleBar in 'HelloTitleBar.pas',
  HelloMain in 'HelloMain.pas' {HelloForm},
  HelloWindow in 'HelloWindow.pas' {DemoWindow},
  FMXWayland.Fmux in '..\..\src\FMXWayland.Fmux.pas',
  FMXWayland.Vulkan in '..\..\src\FMXWayland.Vulkan.pas',
  FMXWayland.VulkanApi in '..\..\src\FMXWayland.VulkanApi.pas',
  FMXWayland.VulkanDevice in '..\..\src\FMXWayland.VulkanDevice.pas',
  FMXWayland.OpenGL in '..\..\src\FMXWayland.OpenGL.pas',
  FMXWayland.Cairo in '..\..\src\FMXWayland.Cairo.pas',
  FMXWayland.CairoApi in '..\..\src\FMXWayland.CairoApi.pas',
  FMXWayland.DBus in '..\..\src\FMXWayland.DBus.pas',
  FMXWayland.DialogTypes in '..\..\src\FMXWayland.DialogTypes.pas',
  FMXWayland.Dialogs in '..\..\src\FMXWayland.Dialogs.pas',
  FMXWayland.FileDialog in '..\..\src\FMXWayland.FileDialog.pas' {FMXWaylandFileDialog},
  FMXWayland.Portal in '..\..\src\FMXWayland.Portal.pas',
  FMXWayland.Keys in '..\..\src\FMXWayland.Keys.pas',
  FMXWayland.Log in '..\..\src\FMXWayland.Log.pas',
  FMXWayland.Native in '..\..\src\FMXWayland.Native.pas',
  FMXWayland.Platform in '..\..\src\FMXWayland.Platform.pas',
  FMXWayland.DragDrop in '..\..\src\FMXWayland.DragDrop.pas',
  FMXWayland.Menus in '..\..\src\FMXWayland.Menus.pas' {FMXWaylandMainMenuView: TFrame},
  FMXWayland.TextInput in '..\..\src\FMXWayland.TextInput.pas',
  FMXWayland.Posix in '..\..\src\FMXWayland.Posix.pas',
  FMXWayland.Wayland in '..\..\src\FMXWayland.Wayland.pas',
  FMXWayland.WaylandCursor in '..\..\src\FMXWayland.WaylandCursor.pas',
  FMXWayland.Xkb in '..\..\src\FMXWayland.Xkb.pas',
  FMXWayland.Protocol.CursorShapeV1 in '..\..\src\Protocols\FMXWayland.Protocol.CursorShapeV1.pas',
  FMXWayland.Protocol.FractionalScaleV1 in '..\..\src\Protocols\FMXWayland.Protocol.FractionalScaleV1.pas',
  FMXWayland.Protocol.TabletV2 in '..\..\src\Protocols\FMXWayland.Protocol.TabletV2.pas',
  FMXWayland.Protocol.TextInputUnstableV3 in '..\..\src\Protocols\FMXWayland.Protocol.TextInputUnstableV3.pas',
  FMXWayland.Protocol.Viewporter in '..\..\src\Protocols\FMXWayland.Protocol.Viewporter.pas',
  FMXWayland.Protocol.Wayland in '..\..\src\Protocols\FMXWayland.Protocol.Wayland.pas',
  FMXWayland.Protocol.XdgActivationV1 in '..\..\src\Protocols\FMXWayland.Protocol.XdgActivationV1.pas',
  FMXWayland.Protocol.XdgDecorationUnstableV1 in '..\..\src\Protocols\FMXWayland.Protocol.XdgDecorationUnstableV1.pas',
  FMXWayland.Protocol.XdgToplevelIconV1 in '..\..\src\Protocols\FMXWayland.Protocol.XdgToplevelIconV1.pas',
  FMXWayland.Protocol.XdgForeignUnstableV2 in '..\..\src\Protocols\FMXWayland.Protocol.XdgForeignUnstableV2.pas',
  FMXWayland.Protocol.XdgShell in '..\..\src\Protocols\FMXWayland.Protocol.XdgShell.pas';

var
  Backend3D: string;
  TitleBarForm: TTitleBarForm;
  BackendProbe: Boolean;
{$IFDEF FASTCANVAS}
  Reason: string;
{$ENDIF}

begin
{$IF Defined(FASTCANVAS)}
  // FastCanvas on Vulkan; FMX's own canvas when there is no Vulkan device it can use.
  if InstallHelloFastCanvas(Reason) then
  begin
    HelloCanvasInfo := HelloFastCanvasInfo;
    HelloSaveFrame :=
      function(AForm: TCommonCustomForm; AFileName: string): string
      begin
        Result := SaveHelloFastCanvasFrame(AForm, AFileName);
      end;
    HelloPresentation := 'Vulkan, VK_KHR_wayland_surface';
  end
  else
    HelloCanvasInfo :=
      function: string
      begin
        Result := 'FastCanvas not installed: ' + Reason;
      end;
{$ELSEIF Defined(SKIA) and not Defined(NOSKIA)}
  GlobalUseSkia := True;
{$IFEND}
  Application.Initialize;
  BackendProbe := False;
  Backend3D := GetEnvironmentVariable('FMXWAYLAND_3D_BACKEND').ToLower;
  for var I := 1 to ParamCount do
  begin
    if ParamStr(I).StartsWith('--3d=') then
      Backend3D := ParamStr(I).Substring(5).ToLower
    else if (ParamStr(I) = '--backend-probe') or ParamStr(I).StartsWith('--early-popup') or
      ParamStr(I).StartsWith('--dialog-dir=') or ParamStr(I).StartsWith('--quit-in-folder-dialog=') then
      BackendProbe := True;
  end;
  if Backend3D = 'vulkan' then
    RegisterVulkanContext
  else if (Backend3D <> '') and (Backend3D <> 'opengl') then
    raise Exception.Create('Unknown 3D backend: ' + Backend3D);
  if OwnTitleBarRequested then
    Application.CreateForm(TTitleBarForm, TitleBarForm)
  else if BackendProbe then
    Application.CreateForm(THelloBackendProbe, HelloBackendProbeForm)
  else
    Application.CreateForm(THelloForm, HelloForm);
  Application.Run;
end.

