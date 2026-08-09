[CmdletBinding()]
param(
  [switch]$StopSupabase
)

$ErrorActionPreference = 'Stop'
$RepoRoot = (Resolve-Path (Join-Path $PSScriptRoot '..')).Path
$RuntimeRoot = Join-Path $RepoRoot '.tools\runtime'
$PidFile = Join-Path $RuntimeRoot 'web.pid'
$Supabase = Join-Path $RepoRoot '.tools\supabase-cli\supabase.exe'

if (Test-Path $PidFile) {
  $webPid = [int]([System.IO.File]::ReadAllText($PidFile).Trim())
  $process = Get-Process -Id $webPid -ErrorAction SilentlyContinue
  if ($process -and $process.ProcessName -eq 'node') {
    Stop-Process -Id $webPid -Force
  }
  Remove-Item -LiteralPath $PidFile -Force
}

if ($StopSupabase) {
  if (-not (Test-Path $Supabase)) {
    throw 'Supabase CLI local nao encontrada.'
  }
  $env:SUPABASE_TELEMETRY_DISABLED = '1'
  & $Supabase stop
  if ($LASTEXITCODE -ne 0) {
    throw 'Falha ao parar Supabase local.'
  }
}

Write-Output 'ELITE_LOCAL_RUNTIME_STOPPED'
