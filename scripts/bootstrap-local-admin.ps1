[CmdletBinding()]
param(
  [Parameter(Mandatory = $true)]
  [ValidatePattern('^[^@\s]+@[^@\s]+\.[^@\s]+$')]
  [string]$Email,

  [Parameter(Mandatory = $true)]
  [ValidateLength(1, 160)]
  [string]$DisplayName
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

function New-TemporaryPassword {
  $upper = 'ABCDEFGHJKLMNPQRSTUVWXYZ'
  $lower = 'abcdefghijkmnopqrstuvwxyz'
  $digits = '23456789'
  $symbols = '!@#$%&*?'
  $all = $upper + $lower + $digits + $symbols
  $random = [System.Security.Cryptography.RandomNumberGenerator]::Create()

  function Get-RandomCharacter([string]$Alphabet) {
    $buffer = New-Object byte[] 4
    $random.GetBytes($buffer)
    $index = [BitConverter]::ToUInt32($buffer, 0) % $Alphabet.Length
    return $Alphabet[[int]$index]
  }

  $characters = New-Object System.Collections.Generic.List[char]
  $characters.Add((Get-RandomCharacter $upper))
  $characters.Add((Get-RandomCharacter $lower))
  $characters.Add((Get-RandomCharacter $digits))
  $characters.Add((Get-RandomCharacter $symbols))
  while ($characters.Count -lt 18) {
    $characters.Add((Get-RandomCharacter $all))
  }

  for ($index = $characters.Count - 1; $index -gt 0; $index -= 1) {
    $buffer = New-Object byte[] 4
    $random.GetBytes($buffer)
    $swap = [BitConverter]::ToUInt32($buffer, 0) % ($index + 1)
    $current = $characters[$index]
    $characters[$index] = $characters[[int]$swap]
    $characters[[int]$swap] = $current
  }
  $random.Dispose()
  return -join $characters
}

if (-not (Test-Path $Supabase)) {
  throw 'Supabase CLI local nao encontrada.'
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
$temporaryPassword = New-TemporaryPassword
$createBody = @{
  email = $Email.Trim().ToLowerInvariant()
  password = $temporaryPassword
  email_confirm = $true
  user_metadata = @{
    temporary_password_bootstrap = $true
    bootstrap_origin = 'local_operator'
  }
} | ConvertTo-Json -Depth 4

$createdUser = Invoke-RestMethod `
  -Method Post `
  -Uri "$apiUrl/auth/v1/admin/users" `
  -Headers $headers `
  -Body $createBody

try {
  $bootstrapBody = @{
    p_user_id = $createdUser.id
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
    -Uri "$apiUrl/auth/v1/admin/users/$($createdUser.id)" `
    -Headers $headers `
    -ErrorAction SilentlyContinue | Out-Null
  throw
}

Write-Output 'ELITE_FIRST_ADMIN_BOOTSTRAP_OK'
Write-Output "Login: $($Email.Trim().ToLowerInvariant())"
Write-Output "Senha temporaria (exibida uma unica vez): $temporaryPassword"
Write-Output 'No primeiro login o sistema exigira a troca da senha.'
