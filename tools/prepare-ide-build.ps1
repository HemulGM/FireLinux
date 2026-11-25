<#
.SYNOPSIS
  Pre-build event for Delphi IDE/MSBuild Linux64 projects using FMXWayland.
.DESCRIPTION
  Generates the replacement FMUX.Api, prepares the missing Linux FMX.Filter resource,
  and optionally copies Delphi's Skia runtime with -Skia. No compiler is launched here:
  the IDE builds the project with its normal Linux64 compiler and SDK settings.
#>
param(
  [Parameter(Mandatory = $true)] [string] $Bds,
  [Parameter(Mandatory = $true)] [string] $GenDir,
  [Parameter(Mandatory = $true)] [string] $OutputDir,
  [ValidateSet('Release', 'Debug')] [string] $Config = 'Release',
  [string] $FmxLinux = '',
  [switch] $Skia
)

$ErrorActionPreference = 'Stop'
if (-not (Test-Path (Join-Path $Bds 'bin\dcclinux64.exe'))) { throw "No Linux64 compiler in $Bds" }
$source = Join-Path $Bds 'source\fmx\FMUX.Api.pas'
if ($FmxLinux) { $source = Join-Path $FmxLinux 'source\FMUX.Api.pas' }
if (-not (Test-Path $source)) { throw "No $source; set the FMX Linux GetIt directory in the pre-build event" }

New-Item -ItemType Directory -Force -Path $GenDir, $OutputDir | Out-Null
& (Join-Path $PSScriptRoot 'gen-fmux-api.ps1') -Bds $Bds -Source $source -Out (Join-Path $GenDir 'FMUX.Api.pas')

$resource = Join-Path $Bds "lib\linux64\$Config\FMX.Filter.res"
if (-not (Test-Path $resource)) { $resource = Join-Path $Bds "lib\win64\$Config\FMX.Filter.res" }
Copy-Item -LiteralPath $resource -Destination $GenDir -Force
if ($Skia) { Copy-Item -LiteralPath (Join-Path $Bds 'Redist\linux64\libsk4d.so') -Destination $OutputDir -Force }
Write-Host "FMXWayland prepared for Linux64 $Config"
