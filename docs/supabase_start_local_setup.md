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
