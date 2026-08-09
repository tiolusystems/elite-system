[CmdletBinding()]
param(
  [Parameter(Mandatory = $true)]
  [ValidatePattern('^[^@\s]+@[^@\s]+\.[^@\s]+$')]
  [string]$Email,

  [Parameter(Mandatory = $true)]
  [ValidateLength(1, 160)]
  [string]$DisplayName,

  [ValidatePattern('^https?://(127\.0\.0\.1|localhost)(:\d+)?$')]
  [string]$ApplicationUrl = 'http://127.0.0.1:3000'
)

$ErrorActionPreference = 'Stop'
$RepoRoot = (Resolve-Path (Join-Path $PSScriptRoot '..')).Path
$Supabase = Join-Path $RepoRoot '.tools\supabase-cli\supabase.exe'

function Get-SupabaseEnvironment {
  $previousErrorActionPreference = $ErrorActionPreference
  $ErrorActionPreference = 'Continue'
  try {
    $status = & $Supabase status -o env 2>$null
    $statusExitCode = $LASTEXITCODE
  } finally {
    $ErrorActionPreference = $previousErrorActionPreference
  }
  if ($statusExitCode -ne 0) {
    throw 'Supabase local nao esta ativo.'
  }

  $values = @{}
  foreach ($line in $status) {
    if ($line -match '^([A-Z0-9_]+)="?(.*?)"?$') {
      $values[$matches[1]] = $matches[2].TrimEnd('"')
    }
  }
  return $values
}

if (-not (Test-Path $Supabase)) {
  throw 'Supabase CLI local nao encontrada.'
}

$normalizedEmail = $Email.Trim().ToLowerInvariant()
$emailDomain = ($normalizedEmail -split '@', 2)[1]
$reservedDomains = @('example.com', 'example.net', 'example.org')
if (
  $emailDomain -match '(^|\.)(local|invalid|test)$' -or
  $reservedDomains -contains $emailDomain
) {
  throw 'Informe um email real. Dominios ficticios ou reservados nao podem criar acesso.'
}

$supabaseEnvironment = Get-SupabaseEnvironment
$apiUrl = $supabaseEnvironment['API_URL']
$serviceRoleKey = $supabaseEnvironment['SERVICE_ROLE_KEY']
if (-not $apiUrl -or -not $serviceRoleKey) {
  throw 'Supabase status nao retornou API_URL e SERVICE_ROLE_KEY.'
}

$apiUri = [Uri]$apiUrl
if ($apiUri.Host -notin @('127.0.0.1', 'localhost', '::1')) {
  throw 'Este script aceita somente Supabase local. Bootstrap cloud exige procedimento operacional separado.'
}

$headers = @{
  apikey = $serviceRoleKey
  Authorization = "Bearer $serviceRoleKey"
  'Content-Type' = 'application/json'
}
$redirectTo = "$($ApplicationUrl.TrimEnd('/'))/auth/confirm?flow=invite"
$inviteUri = "$apiUrl/auth/v1/invite?redirect_to=$([Uri]::EscapeDataString($redirectTo))"
$inviteBody = @{
  email = $normalizedEmail
  data = @{
    display_name = $DisplayName.Trim()
    elite_role = 'admin'
    invitation_pending = $true
    bootstrap_origin = 'local_operator'
  }
} | ConvertTo-Json -Depth 4

$invitedUser = Invoke-RestMethod `
  -Method Post `
  -Uri $inviteUri `
  -Headers $headers `
  -Body $inviteBody

try {
  $bootstrapBody = @{
    p_user_id = $invitedUser.id
    p_display_name = $DisplayName.Trim()
  } | ConvertTo-Json
  Invoke-RestMethod `
    -Method Post `
    -Uri "$apiUrl/rest/v1/rpc/bootstrap_first_system_admin" `
    -Headers $headers `
    -Body $bootstrapBody | Out-Null
} catch {
  Invoke-RestMethod `
    -Method Delete `
    -Uri "$apiUrl/auth/v1/admin/users/$($invitedUser.id)" `
    -Headers $headers `
    -ErrorAction SilentlyContinue | Out-Null
  throw
}

Write-Output 'ELITE_FIRST_ADMIN_BOOTSTRAP_OK'
Write-Output "Convite enviado para: $normalizedEmail"
Write-Output 'Abra o email de convite, confirme o endereco e defina a senha.'
if ($supabaseEnvironment['INBUCKET_URL']) {
  Write-Output "Caixa de email local: $($supabaseEnvironment['INBUCKET_URL'])"
}
