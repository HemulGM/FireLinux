{ Selects and installs a native backend for FMX on Linux. MIT license, see LICENSE. }
unit FireLinux.Backend.Factory;

interface

type
  TInstallStubsProc = procedure;

procedure InstallFmuxApi(AInstallStubs: TInstallStubsProc);

implementation

uses
  System.SysUtils, FMUX.Api, FireLinux.Log, FireLinux.Wayland.Client,
  FireLinux.Fmux, FireLinux.Wayland.Fmux, FireLinux.X11.Fmux;

{$SCOPEDENUMS ON}
type
  TBackendKind = (Wayland, X11);
{$SCOPEDENUMS OFF}

  TBackendInitProc = procedure(Flags: Integer); cdecl;

  TBackendInstaller = procedure;

var
  GMode: string;
  GInstallStubs: TInstallStubsProc;
  GInitialize: TBackendInitProc;

function PreferredBackend: TBackendKind;
var
  Error: string;
  Display: Pointer;
begin
  if (GMode <> '') and (GMode <> 'auto') and (GMode <> 'wayland') and (GMode <> 'x11') then
  begin
    // Unit initialization precedes FMX's exception handler: report a useful error instead of runtime error 217.
    WlLog(TWlLogLevel.Error, 'FIRELINUX_BACKEND must be auto, wayland or x11');
    Halt(1);
  end;
  if GMode = 'x11' then
    Exit(TBackendKind.X11);
  if GMode = 'wayland' then
    Exit(TBackendKind.Wayland);
  // An inherited WAYLAND_SOCKET is a single-use fd. Probing it would consume the application's connection.
  if GetEnvironmentVariable('WAYLAND_SOCKET') <> '' then
    Exit(TBackendKind.Wayland);
  if (GetEnvironmentVariable('XDG_RUNTIME_DIR') = '') and
    not GetEnvironmentVariable('WAYLAND_DISPLAY').StartsWith('/') then
    Exit(TBackendKind.X11);
  // Probe only the transport here: LoadLib can run before FMX and the generated protocol units initialize.
  // The real connection (and its globals) is established by FmuxInit.
  if not LoadWaylandClient(Error) then
    Exit(TBackendKind.X11);
  Display := wl_display_connect(nil);
  if Display = nil then
    Exit(TBackendKind.X11);
  wl_display_disconnect(Display);
  Result := TBackendKind.Wayland;
end;

function CreateBackend(AKind: TBackendKind): TBackendInstaller;
begin
  if AKind = TBackendKind.Wayland then
    Result := AssignWaylandApi
  else
    Result := AssignX11Api;
end;

procedure BindBackend(AKind: TBackendKind); forward;

procedure InitializeBackend(Flags: Integer); cdecl;
begin
  try
    try
      GInitialize(Flags);
    except
      on E: EWaylandConnectionError do
      begin
        if GMode = 'wayland' then
          raise;
        WlLog(TWlLogLevel.Warning, 'Wayland unavailable: %s; trying X11', [E.Message]);
        BindBackend(TBackendKind.X11);
        GInitialize(Flags);
      end;
    end;
  except
    on E: Exception do
    begin
      WlLog(TWlLogLevel.Error, E.Message);
      Halt(1);
    end;
  end;
end;

procedure BindBackend(AKind: TBackendKind);
var
  Install: TBackendInstaller;
begin
  Install := CreateBackend(AKind);
  GInstallStubs();
  AssignSharedFmuxApi;
  Install();
  GInitialize := FMUX.Api.FmuxInit;
  FMUX.Api.FmuxInit := InitializeBackend;
end;

procedure InstallFmuxApi(AInstallStubs: TInstallStubsProc);
begin
  GInstallStubs := AInstallStubs;
  GMode := LowerCase(Trim(GetEnvironmentVariable('FIRELINUX_BACKEND')));
  BindBackend(PreferredBackend);
end;

end.

