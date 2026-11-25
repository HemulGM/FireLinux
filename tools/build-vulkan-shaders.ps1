<# Rebuild the embedded shaders after editing shaders/viewport.vert or .frag.
   Requires the glslangValidator CLI (e.g. Vulkan SDK) and Python 3 only at development time.
   The app never loads a shader compiler library. #>
param(
  [string] $GlslangValidator = 'glslangValidator',
  [string] $Python = 'python',
  [string] $BuildRoot = ''
)
$ErrorActionPreference = 'Stop'
$root = Split-Path $PSScriptRoot -Parent
if (-not $BuildRoot) { $BuildRoot = Join-Path $root 'out\vulkan-shaders' }
New-Item -ItemType Directory -Force -Path $BuildRoot | Out-Null
$BuildRoot = (Resolve-Path $BuildRoot).Path
foreach ($stage in 'vert', 'frag') {
  & $GlslangValidator -V --target-env vulkan1.0 (Join-Path $root "shaders\viewport.$stage") -o (Join-Path $BuildRoot "viewport.$stage.spv")
  if ($LASTEXITCODE -ne 0) { throw "glslangValidator failed for $stage" }
}
Push-Location $root
try {
  & $Python (Join-Path $PSScriptRoot 'embed-vulkan-shaders.py') $BuildRoot
  if ($LASTEXITCODE -ne 0) { throw 'Embedding SPIR-V failed' }
} finally { Pop-Location }
