[CmdletBinding()]
param(
  [ValidateRange(1024, 65535)]
  [int]$Port = 3000
)

$ErrorActionPreference = 'Stop'
$RepoRoot = (Resolve-Path (Join-Path $PSScriptRoot '..')).Path
$StartScript = Join-Path $PSScriptRoot 'start-local.ps1'
$AppUrl = "http://127.0.0.1:$Port/producao"

if (-not (Test-Path $StartScript)) {
  throw "Inicializador local nao encontrado: $StartScript"
}

& $StartScript -Port $Port | Out-Null

$edgeCandidates = @(
  (Join-Path ${env:ProgramFiles(x86)} 'Microsoft\Edge\Application\msedge.exe'),
  (Join-Path $env:ProgramFiles 'Microsoft\Edge\Application\msedge.exe')
) | Where-Object { $_ -and (Test-Path $_) }

$Edge = $edgeCandidates | Select-Object -First 1
if (-not $Edge) {
  throw 'Microsoft Edge nao encontrado.'
}

Start-Process `
  -FilePath $Edge `
  -ArgumentList @("--app=$AppUrl", '--start-maximized', '--no-first-run') `
  -WorkingDirectory $RepoRoot | Out-Null
