[CmdletBinding()]
param(
  [ValidateRange(1024, 65535)]
  [int]$Port = 3000
)

$ErrorActionPreference = 'Stop'
$RepoRoot = (Resolve-Path (Join-Path $PSScriptRoot '..')).Path
$Launcher = Join-Path $PSScriptRoot 'launch-elite-system.ps1'
$PowerShell = Join-Path $env:SystemRoot 'System32\WindowsPowerShell\v1.0\powershell.exe'
$Programs = [Environment]::GetFolderPath('Programs')
$ShortcutDirectory = Join-Path $Programs 'Elite System'
$ShortcutPath = Join-Path $ShortcutDirectory 'Elite System.lnk'

if (-not (Test-Path $Launcher)) {
  throw "Lancador nao encontrado: $Launcher"
}
if (-not (Test-Path $PowerShell)) {
  throw 'Windows PowerShell nao encontrado.'
}

$edgeCandidates = @(
  (Join-Path ${env:ProgramFiles(x86)} 'Microsoft\Edge\Application\msedge.exe'),
  (Join-Path $env:ProgramFiles 'Microsoft\Edge\Application\msedge.exe')
) | Where-Object { $_ -and (Test-Path $_) }
$Edge = $edgeCandidates | Select-Object -First 1

New-Item -ItemType Directory -Force -Path $ShortcutDirectory | Out-Null

$shell = New-Object -ComObject WScript.Shell
$shortcut = $shell.CreateShortcut($ShortcutPath)
$shortcut.TargetPath = $PowerShell
$shortcut.Arguments = "-NoProfile -ExecutionPolicy Bypass -WindowStyle Hidden -File `"$Launcher`" -Port $Port"
$shortcut.WorkingDirectory = $RepoRoot
$shortcut.Description = 'Inicia e abre o Elite System'
$shortcut.WindowStyle = 7
if ($Edge) {
  $shortcut.IconLocation = "$Edge,0"
}
$shortcut.Save()

Write-Output 'ELITE_START_MENU_SHORTCUT_OK'
Write-Output "Atalho: $ShortcutPath"
