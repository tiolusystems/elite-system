# Supabase start local

Data: 2026-07-03

## Objetivo

Deixar a maquina preparada para executar:

```powershell
.\.tools\supabase-cli\supabase.exe start
```

## Instalado/preparado

- Supabase CLI local: `.tools/supabase-cli/supabase.exe`.
- Supabase CLI validada: `2.109.0`.
- PostgreSQL descartavel para validacao de migrations: `.tools/pg-validate`.
- Docker Desktop instalado em `C:\Program Files\Docker`.
- Docker CLI instalado em `C:\Program Files\Docker\Docker\resources\bin\docker.exe`.
- WSL moderno instalado via MSI oficial Microsoft: `2.7.10.0`.
- Features Windows habilitadas via DISM:
  - `Microsoft-Windows-Subsystem-Linux`;
  - `VirtualMachinePlatform`.

## Validado antes do Docker

As migrations `0001` a `0006` foram aplicadas com sucesso em PostgreSQL descartavel usando `psql -v ON_ERROR_STOP=1`.

Smoke tests estruturais passaram:

- cadastro minimo;
- pedido;
- credito;
- romaneio;
- separacao;
- confirmacao;
- baixa PA;
- estorno;
- travas negativas de saldo e pedido bloqueado.

## Bloqueio atual

`supabase start` ainda nao sobe porque Docker Desktop permanece com engine `stopped`.

Sinais observados:

- `docker desktop status` retorna `Status stopped`;
- `docker version` acessa o cliente, mas o servidor retorna erro 500;
- `wsl --version` retorna WSL `2.7.10.0`;
- `wsl --status` informa que WSL2 nao pode iniciar porque a virtualizacao nao esta ativa para o Windows;
- DISM mostra WSL e VirtualMachinePlatform habilitados com reinicializacao possivel.

## Proximo passo operacional

Reiniciar o Windows para carregar as features habilitadas.

Apos reiniciar:

```powershell
cd "C:\Users\luuci\Documents\Codex\2026-07-02\Elite System\04-sistema"
wsl --status
Start-Process "C:\Program Files\Docker\Docker\Docker Desktop.exe"
.\.tools\supabase-cli\supabase.exe start
```

Se apos reiniciar o WSL ainda informar que virtualizacao nao esta habilitada, sera necessario habilitar Intel VT-x/Virtualization Technology no BIOS/UEFI da maquina.

<!-- ELITE_WINDOWS_RESERVED_PORTS_START -->
## Atenção — conflito de portas no Windows/Docker

Registro operacional atualizado em **08/08/2026**.

Nesta máquina, o Windows/Hyper-V apresentou uma faixa de exclusão TCP que inclui:

`	ext
54320-54419
`

Essa faixa abrange as portas padrão usadas pelo Supabase local deste projeto, incluindo 54320, 54321, 54322, 54323, 54324, 54327 e 54329.

### Sintomas observados

- AuthRetryableFetchError: fetch failed no Next.js/Supabase Auth;
- Test-NetConnection 127.0.0.1 -Port 54321 retorna TcpTestSucceeded : False;
- a CLI do Supabase pode inicialmente informar que o ambiente está em execução;
- docker ps pode mostrar containers do projeto publicados em portas alternativas;
- ao tentar recriar o stack nas portas padrão, o Docker pode falhar com:

`	ext
bind: An attempt was made to access a socket in a way forbidden by its access permissions
`

### Diagnóstico obrigatório

Antes de tratar etch failed como defeito da aplicação, verificar:

`powershell
netsh interface ipv4 show excludedportrange protocol=tcp
`

Também conferir a porta efetivamente publicada pelo Docker:

`powershell
docker ps --format "{{.Names}} | {{.Status}} | {{.Ports}}"
`

E testar diretamente a API configurada:

`powershell
Test-NetConnection 127.0.0.1 -Port 54321
`

### Regra operacional

- Não remover arbitrariamente faixas de exclusão administradas pelo Windows, Hyper-V, WSL ou Docker.
- Quando as portas padrão do Supabase estiverem dentro de uma faixa reservada, usar uma faixa alternativa estável e livre.
- supabase/config.toml e pps/web/.env.local devem permanecer coerentes entre si.
- Depois de alterar portas, executar supabase stop e supabase start para recriar os bindings.
- Antes de qualquer alteração de portas, preservar backup do supabase/config.toml e do pps/web/.env.local.

Este problema já ocorreu mais de uma vez nesta máquina e deve ser considerado uma verificação padrão do ambiente local.
<!-- ELITE_WINDOWS_RESERVED_PORTS_END -->
