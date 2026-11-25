program Hello;

{ FMXWayland sample: streamed FMX forms with tabs for controls, animations/images, dialogs and the platform.

  Command line:
    --quit-after=N   closes the main form after N seconds (tests: clean exit)
    --verbose        writes events and control positions to stdout
    --tab=images|dialogs|platform|drag|3d  selects the initial demo tab
    --3d=opengl|vulkan  selects the 3D backend before any FMX textures are created
    --selftest       runs the non-interactive integration checks }

uses
  System.StartUpCopy,
  System.SysUtils,
  FMX.Forms,
  FMX.Types,
  HelloMain in 'HelloMain.pas' {HelloForm},
  HelloWindow in 'HelloWindow.pas' {DemoWindow},
  FMUX.Api in 'FMUX.Api.pas',
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
  FMXWayland.Protocol.XdgShell in '..\..\src\Protocols\FMXWayland.Protocol.XdgShell.pas';

var
  Backend3D: string;

begin
  // FMXWayland implements the standard FMX.Canvas.Linux API with system Cairo and Pango.
  Application.Initialize;
  Backend3D := GetEnvironmentVariable('FMXWAYLAND_3D_BACKEND').ToLower;
  for var I := 1 to ParamCount do
    if ParamStr(I).StartsWith('--3d=') then
      Backend3D := ParamStr(I).Substring(5).ToLower;
  if Backend3D = 'vulkan' then
    RegisterVulkanContext
  else if (Backend3D <> '') and (Backend3D <> 'opengl') then
    raise Exception.Create('Unknown 3D backend: ' + Backend3D);
  //RegisterVulkanContext;
  Application.CreateForm(THelloForm, HelloForm);
  Application.Run;
end.

