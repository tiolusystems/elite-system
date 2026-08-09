[CmdletBinding()]
param()

$ErrorActionPreference = 'Stop'

$baseUrl = $env:ELITE_VALIDATION_API_URL
$publishableKey = $env:ELITE_VALIDATION_PUBLISHABLE_KEY
$jwtSecret = $env:ELITE_VALIDATION_JWT_SECRET

if ([string]::IsNullOrWhiteSpace($baseUrl) -or
    [string]::IsNullOrWhiteSpace($publishableKey) -or
    [string]::IsNullOrWhiteSpace($jwtSecret)) {
  throw 'ELITE_VALIDATION_API_URL, ELITE_VALIDATION_PUBLISHABLE_KEY and ELITE_VALIDATION_JWT_SECRET are required.'
}

function ConvertTo-Base64Url {
  param([Parameter(Mandatory = $true)][byte[]]$Bytes)

  return [Convert]::ToBase64String($Bytes).TrimEnd('=').Replace('+', '-').Replace('/', '_')
}

function New-TestJwt {
  param([Parameter(Mandatory = $true)][string]$Subject)

  $header = '{"alg":"HS256","typ":"JWT"}'
  $expiresAt = [DateTimeOffset]::UtcNow.AddMinutes(15).ToUnixTimeSeconds()
  $payload = [ordered]@{
    aud = 'authenticated'
    exp = $expiresAt
    role = 'authenticated'
    sub = $Subject
  } | ConvertTo-Json -Compress
  $headerPart = ConvertTo-Base64Url ([Text.Encoding]::UTF8.GetBytes($header))
  $payloadPart = ConvertTo-Base64Url ([Text.Encoding]::UTF8.GetBytes($payload))
  $unsigned = "$headerPart.$payloadPart"
  $hmac = [Security.Cryptography.HMACSHA256]::new([Text.Encoding]::UTF8.GetBytes($jwtSecret))
  try {
    $signature = ConvertTo-Base64Url ($hmac.ComputeHash([Text.Encoding]::UTF8.GetBytes($unsigned)))
  } finally {
    $hmac.Dispose()
  }
  return "$unsigned.$signature"
}

function Invoke-DeniedWrite {
  param(
    [Parameter(Mandatory = $true)][string]$Context,
    [Parameter(Mandatory = $true)][string]$Table,
    [Parameter(Mandatory = $true)][ValidateSet('POST', 'PATCH', 'DELETE')][string]$Method,
    [string]$Token
  )

  $headers = @{ apikey = $publishableKey }
  if (-not [string]::IsNullOrWhiteSpace($Token)) {
    $headers.Authorization = "Bearer $Token"
  }
  $uri = "$($baseUrl.TrimEnd('/'))/rest/v1/$Table"
  if ($Method -ne 'POST') {
    $uri += '?id=eq.-9223372036854775808'
  }
  try {
    $response = Invoke-WebRequest -UseBasicParsing -Uri $uri -Method $Method -Headers $headers `
      -ContentType 'application/json' -Body '{}'
    if ($Method -eq 'POST' -or [int]$response.StatusCode -ne 204) {
      throw "direct $Method unexpectedly succeeded for $Context on $Table"
    }
    # PostgREST may return 204 when RLS exposes zero matching rows. The caller
    # compares full-table fingerprints before and after the HTTP sweep.
  } catch [System.Net.WebException] {
    $status = [int]$_.Exception.Response.StatusCode
    if ($status -lt 400 -or $status -ge 500) {
      throw "unexpected HTTP $status for direct $Method by $Context on $Table"
    }
  }
}

$tablesByDomain = [ordered]@{
  cadastros = 'cad_clientes'
  pedidos = 'com_pedidos'
  estoque = 'est_lotes_pa'
  pcp = 'pcp_formula_versoes'
  producao = 'pcp_ordens_producao'
  romaneio = 'exp_romaneios'
  faturamento = 'fat_notas_fiscais'
  financeiro = 'fin_pedido_planos_pagamento'
  metas = 'com_meta_periodos'
  importacao = 'migration_batches'
  seguranca = 'user_profiles'
}

$contexts = [ordered]@{
  anon = $null
  authenticated_zero_grant = New-TestJwt '00000000-0000-4000-8000-000000000066'
  authenticated_normal = New-TestJwt '00000000-0000-4000-8000-000000000067'
}

$attempts = 0
foreach ($context in $contexts.GetEnumerator()) {
  foreach ($table in $tablesByDomain.Values) {
    foreach ($method in @('POST', 'PATCH', 'DELETE')) {
      Invoke-DeniedWrite -Context $context.Key -Table $table -Method $method -Token $context.Value
      $attempts++
    }
  }
}

Write-Output "ELITE_DATA_API_NON_BYPASS_OK attempts=$attempts domains=$($tablesByDomain.Count) contexts=$($contexts.Count)"
