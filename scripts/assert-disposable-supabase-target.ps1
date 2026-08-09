[CmdletBinding()]
param(
  [Parameter(Mandatory = $true)]
  [ValidateNotNullOrEmpty()]
  [string]$TargetProjectId,

  [Parameter(Mandatory = $true)]
  [ValidateSet('db-reset', 'db-start', 'destructive-migration')]
  [string]$Operation,

  [Parameter(Mandatory = $true)]
  [ValidateNotNullOrEmpty()]
  [string]$TargetContainer,

  [Parameter(Mandatory = $true)]
  [ValidateNotNullOrEmpty()]
  [string]$TargetVolume,

  [switch]$ExplicitAuthorization
)

$ErrorActionPreference = 'Stop'

function Stop-DestructiveValidation {
  param([Parameter(Mandatory = $true)][string]$Reason)

  [Console]::Error.WriteLine("ELITE_DESTRUCTIVE_VALIDATION_BLOCKED: $Reason")
  exit 64
}

$repositoryRoot = Split-Path -Parent $PSScriptRoot
$supabaseConfig = Join-Path $repositoryRoot 'supabase/config.toml'

if (-not (Test-Path -LiteralPath $supabaseConfig -PathType Leaf)) {
  Stop-DestructiveValidation 'supabase/config.toml nao encontrado.'
}

$projectMatch = Select-String -Path $supabaseConfig -Pattern '^project_id\s*=\s*"([^"]+)"\s*$' |
  Select-Object -First 1

if ($null -eq $projectMatch) {
  Stop-DestructiveValidation 'project_id ativo nao identificado em supabase/config.toml.'
}

$activeProjectId = $projectMatch.Matches[0].Groups[1].Value.Trim().ToLowerInvariant()
$targetId = $TargetProjectId.Trim().ToLowerInvariant()
$targetContainerNormalized = $TargetContainer.Trim().ToLowerInvariant()
$targetVolumeNormalized = $TargetVolume.Trim().ToLowerInvariant()
$activeContainer = "supabase_db_$activeProjectId"

if (-not $ExplicitAuthorization.IsPresent) {
  Stop-DestructiveValidation 'autorizacao destrutiva explicita ausente.'
}

if ($targetId -eq $activeProjectId) {
  Stop-DestructiveValidation "o projeto '$targetId' e o runtime local ativo."
}

if ($targetId -notmatch '^elite-validation-[a-z0-9][a-z0-9-]*$') {
  Stop-DestructiveValidation 'o projeto descartavel deve usar o prefixo elite-validation-.'
}

if ($targetContainerNormalized -eq $activeContainer) {
  Stop-DestructiveValidation "o container '$TargetContainer' pertence ao runtime ativo."
}

$expectedContainer = "supabase_db_$targetId"
if ($targetContainerNormalized -ne $expectedContainer) {
  Stop-DestructiveValidation "container proprio esperado: '$expectedContainer'."
}

if (-not $targetVolumeNormalized.Contains($targetId)) {
  Stop-DestructiveValidation 'o volume deve ser proprio e conter o identificador descartavel.'
}

Write-Output "ELITE_DISPOSABLE_TARGET_OK project=$targetId operation=$Operation"
