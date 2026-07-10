[CmdletBinding()]
param(
  [ValidateRange(1024, 65535)]
  [int]$Port = 3000,

  [switch]$SkipSupabaseStart
)

$ErrorActionPreference = 'Stop'
$RepoRoot = (Resolve-Path (Join-Path $PSScriptRoot '..')).Path
$WebRoot = Join-Path $RepoRoot 'apps\web'
$ToolsRoot = Join-Path $RepoRoot '.tools'
$RuntimeRoot = Join-Path $ToolsRoot 'runtime'
$Supabase = Join-Path $ToolsRoot 'supabase-cli\supabase.exe'
$EnvFile = Join-Path $WebRoot '.env.local'

New-Item -ItemType Directory -Force -Path $RuntimeRoot | Out-Null

function Test-DockerEngine {
  & docker version --format '{{.Server.Version}}' *> $null
  return $LASTEXITCODE -eq 0
}

function Start-DockerEngine {
  if (Test-DockerEngine) {
    return
  }

  $desktop = 'C:\Program Files\Docker\Docker\Docker Desktop.exe'
  if (-not (Test-Path $desktop)) {
    throw 'Docker Desktop nao encontrado.'
  }

  Start-Process -FilePath $desktop -WindowStyle Hidden | Out-Null
  for ($attempt = 0; $attempt -lt 60; $attempt += 1) {
    Start-Sleep -Seconds 5
    if (Test-DockerEngine) {
      return
    }
  }

  throw 'Docker Engine nao ficou pronto em 5 minutos.'
}

function Get-SupabaseEnvironment {
  $status = & $Supabase status -o env 2>$null
  if ($LASTEXITCODE -ne 0) {
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

function Resolve-NodeExecutable {
  $command = Get-Command node -ErrorAction SilentlyContinue
  if ($command) {
    return $command.Source
  }

  $localNode = Join-Path $ToolsRoot 'node-runtime\node.exe'
  if (Test-Path $localNode) {
    return $localNode
  }

  $runtimeRoot = Join-Path $env:LOCALAPPDATA 'OpenAI\Codex\runtimes\cua_node'
  $runtimeNode = Get-ChildItem $runtimeRoot -Filter node.exe -File -Recurse -ErrorAction SilentlyContinue |
    Sort-Object LastWriteTime -Descending |
    Select-Object -First 1
  if ($runtimeNode) {
    return $runtimeNode.FullName
  }

  throw 'Node.js 24 nao encontrado. Instale Node ou disponibilize o runtime em .tools/node-runtime.'
}

if (-not (Test-Path $Supabase)) {
  throw 'Supabase CLI local nao encontrada em .tools/supabase-cli.'
}
if (-not (Test-Path (Join-Path $WebRoot 'node_modules\next\dist\bin\next'))) {
  throw 'Dependencias web ausentes. Execute pnpm install --frozen-lockfile em apps/web.'
}

Start-DockerEngine
if (-not $SkipSupabaseStart) {
  $env:SUPABASE_TELEMETRY_DISABLED = '1'
  & $Supabase start | Out-Null
  if ($LASTEXITCODE -ne 0) {
    throw 'Falha ao iniciar Supabase local.'
  }
}

$supabaseEnvironment = Get-SupabaseEnvironment
$apiUrl = $supabaseEnvironment['API_URL']
$publicKey = $supabaseEnvironment['PUBLISHABLE_KEY']
if (-not $publicKey) {
  $publicKey = $supabaseEnvironment['ANON_KEY']
}
$serviceRoleKey = $supabaseEnvironment['SERVICE_ROLE_KEY']
if (-not $apiUrl -or -not $publicKey -or -not $serviceRoleKey) {
  throw 'Supabase status nao retornou API_URL, chave publica e service role.'
}

$envLines = @(
  "NEXT_PUBLIC_SUPABASE_URL=$apiUrl",
  "NEXT_PUBLIC_SUPABASE_PUBLISHABLE_KEY=$publicKey",
  "SUPABASE_SERVICE_ROLE_KEY=$serviceRoleKey",
  'ELITE_DATABASE_MODE=local',
  'ELITE_DATABASE_LABEL=Supabase local - dados de teste'
)
[System.IO.File]::WriteAllLines($EnvFile, $envLines, [System.Text.UTF8Encoding]::new($false))

$healthUrl = "http://127.0.0.1:$Port/api/health"
try {
  $existing = Invoke-RestMethod -Uri $healthUrl -TimeoutSec 3
  if ($existing.status -eq 'ok') {
    Write-Output "Elite System ja esta ativo em http://127.0.0.1:$Port"
    return
  }
} catch {
  # No healthy web process is listening on the requested port.
}

$node = Resolve-NodeExecutable
$next = 'node_modules\next\dist\bin\next'
$stdout = Join-Path $RuntimeRoot 'web.stdout.log'
$stderr = Join-Path $RuntimeRoot 'web.stderr.log'
$pidFile = Join-Path $RuntimeRoot 'web.pid'
$process = Start-Process -FilePath $node `
  -ArgumentList @($next, 'dev', '--hostname', '0.0.0.0', '--port', $Port) `
  -WorkingDirectory $WebRoot `
  -RedirectStandardOutput $stdout `
  -RedirectStandardError $stderr `
  -WindowStyle Hidden `
  -PassThru
[System.IO.File]::WriteAllText($pidFile, $process.Id.ToString())

for ($attempt = 0; $attempt -lt 60; $attempt += 1) {
  Start-Sleep -Seconds 2
  if ($process.HasExited) {
    throw "Next.js encerrou durante a inicializacao. Consulte $stderr"
  }
  try {
    $health = Invoke-RestMethod -Uri $healthUrl -TimeoutSec 3
    if ($health.status -eq 'ok') {
      Write-Output 'ELITE_LOCAL_RUNTIME_OK'
      Write-Output "Aplicacao: http://127.0.0.1:$Port"
      Write-Output "Supabase Studio: $($supabaseEnvironment['STUDIO_URL'])"
      Write-Output 'Banco identificado visualmente como local/dados de teste.'
      return
    }
  } catch {
    # Keep waiting until Next.js reports healthy or the timeout expires.
  }
}

Stop-Process -Id $process.Id -Force -ErrorAction SilentlyContinue
throw "Elite System nao respondeu ao health-check. Consulte $stderr"
