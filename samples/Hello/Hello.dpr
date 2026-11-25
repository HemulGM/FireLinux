program Hello;

{ FireLinux sample: streamed FMX forms with tabs for controls, animations/images, dialogs and the platform.

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
  FMUX.Api in '..\..\src\FMUX.Api.pas',
  HelloBackendProbe in 'HelloBackendProbe.pas' {HelloBackendProbeForm},
  HelloTitleBar in 'HelloTitleBar.pas',
  HelloMain in 'HelloMain.pas' {HelloForm},
  HelloWindow in 'HelloWindow.pas' {DemoWindow},
  FireLinux.Wayland.Fmux in '..\..\src\Backends\Wayland\FireLinux.Wayland.Fmux.pas',
  FireLinux.Vulkan in '..\..\src\Rendering\FireLinux.Vulkan.pas',
  FireLinux.VulkanApi in '..\..\src\Rendering\FireLinux.VulkanApi.pas',
  FireLinux.VulkanDevice in '..\..\src\Rendering\FireLinux.VulkanDevice.pas',
  FireLinux.OpenGL in '..\..\src\Rendering\FireLinux.OpenGL.pas',
  FireLinux.Cairo in '..\..\src\Rendering\FireLinux.Cairo.pas',
  FireLinux.CairoApi in '..\..\src\Rendering\FireLinux.CairoApi.pas',
  FireLinux.DBus in '..\..\src\Dialogs\FireLinux.DBus.pas',
  FireLinux.DialogTypes in '..\..\src\Dialogs\FireLinux.DialogTypes.pas',
  FireLinux.Dialogs in '..\..\src\Dialogs\FireLinux.Dialogs.pas',
  FireLinux.FileDialog in '..\..\src\Dialogs\FireLinux.FileDialog.pas' {FireLinuxFileDialog},
  FireLinux.Portal in '..\..\src\Dialogs\FireLinux.Portal.pas',
  FireLinux.Keys in '..\..\src\FireLinux.Keys.pas',
  FireLinux.Log in '..\..\src\FireLinux.Log.pas',
  FireLinux.Wayland.Native in '..\..\src\Backends\Wayland\FireLinux.Wayland.Native.pas',
  FireLinux.Wayland.Platform in '..\..\src\Backends\Wayland\FireLinux.Wayland.Platform.pas',
  FireLinux.Wayland.DragDrop in '..\..\src\Backends\Wayland\FireLinux.Wayland.DragDrop.pas',
  FireLinux.Menus in '..\..\src\FireLinux.Menus.pas' {FireLinuxMainMenuView: TFrame},
  FireLinux.Wayland.TextInput in '..\..\src\Backends\Wayland\FireLinux.Wayland.TextInput.pas',
  FireLinux.Posix in '..\..\src\FireLinux.Posix.pas',
  FireLinux.Wayland.Client in '..\..\src\Backends\Wayland\FireLinux.Wayland.Client.pas',
  FireLinux.Wayland.Cursor in '..\..\src\Backends\Wayland\FireLinux.Wayland.Cursor.pas',
  FireLinux.Xkb in '..\..\src\FireLinux.Xkb.pas',
  FireLinux.Wayland.Protocol.CursorShapeV1 in '..\..\src\Backends\Wayland\Protocols\FireLinux.Wayland.Protocol.CursorShapeV1.pas',
  FireLinux.Wayland.Protocol.FractionalScaleV1 in '..\..\src\Backends\Wayland\Protocols\FireLinux.Wayland.Protocol.FractionalScaleV1.pas',
  FireLinux.Wayland.Protocol.TabletV2 in '..\..\src\Backends\Wayland\Protocols\FireLinux.Wayland.Protocol.TabletV2.pas',
  FireLinux.Wayland.Protocol.TextInputUnstableV3 in '..\..\src\Backends\Wayland\Protocols\FireLinux.Wayland.Protocol.TextInputUnstableV3.pas',
  FireLinux.Wayland.Protocol.Viewporter in '..\..\src\Backends\Wayland\Protocols\FireLinux.Wayland.Protocol.Viewporter.pas',
  FireLinux.Wayland.Protocol.Wayland in '..\..\src\Backends\Wayland\Protocols\FireLinux.Wayland.Protocol.Wayland.pas',
  FireLinux.Wayland.Protocol.XdgActivationV1 in '..\..\src\Backends\Wayland\Protocols\FireLinux.Wayland.Protocol.XdgActivationV1.pas',
  FireLinux.Wayland.Protocol.XdgDecorationUnstableV1 in '..\..\src\Backends\Wayland\Protocols\FireLinux.Wayland.Protocol.XdgDecorationUnstableV1.pas',
  FireLinux.Wayland.Protocol.XdgToplevelIconV1 in '..\..\src\Backends\Wayland\Protocols\FireLinux.Wayland.Protocol.XdgToplevelIconV1.pas',
  FireLinux.Wayland.Protocol.XdgForeignUnstableV2 in '..\..\src\Backends\Wayland\Protocols\FireLinux.Wayland.Protocol.XdgForeignUnstableV2.pas',
  FireLinux.Wayland.Protocol.XdgShell in '..\..\src\Backends\Wayland\Protocols\FireLinux.Wayland.Protocol.XdgShell.pas',
  FireLinux.FmuxLoad in '..\..\src\FireLinux.FmuxLoad.pas',
  FireLinux.Frame in '..\..\src\FireLinux.Frame.pas',
  FireLinux.SystemFont in '..\..\src\FireLinux.SystemFont.pas',
  FireLinux.X11.Fmux in '..\..\src\Backends\X11\FireLinux.X11.Fmux.pas',
  FireLinux.X11.Xlib in '..\..\src\Backends\X11\FireLinux.X11.Xlib.pas',
  FireLinux.Backend.Factory in '..\..\src\FireLinux.Backend.Factory.pas',
  FireLinux.Fmux in '..\..\src\FireLinux.Fmux.pas',
  FireLinux.RasterFrame in '..\..\src\Rendering\FireLinux.RasterFrame.pas';

var
  Backend3D: string;
  TitleBarForm: TTitleBarForm;
  BackendProbe: Boolean;

begin
  Application.Initialize;
  BackendProbe := False;
  Backend3D := GetEnvironmentVariable('FIRELINUX_3D_BACKEND').ToLower;
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

