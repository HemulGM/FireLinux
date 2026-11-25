{ FireLinux: native display backends for Delphi FireMonkey on Linux.
  Copyright (c) 2026 Fasday. MIT license, see LICENSE. }

/// <summary>Initializes the FMUX function pointers before FMX uses them.</summary>
/// <remarks>FMUX.Api imports this helper before FireLinux.Backend.Factory. The factory imports adapters that
/// depend on FMX.Platform.Linux, which itself uses FMUX.Api. This helper breaks the initialization cycle by
/// calling LoadLib before FMX.Platform.Linux can call FmuxSetLog. LoadLib's guard prevents a second installation.</remarks>
unit FireLinux.FmuxLoad;

interface

implementation

uses
  FMUX.Api;

initialization
  LoadLib;

end.
