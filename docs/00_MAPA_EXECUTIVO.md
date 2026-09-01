# Elite System - mapa executivo

## Uso obrigatorio

Este e o primeiro arquivo de toda tarefa. Ele localiza o trabalho sem exigir
releitura integral do repositorio.

Ordem minima:

1. este mapa;
2. `docs/01_ESTADO_ATUAL.md`;
3. `docs/02_DECISOES_PENDENTES.md`;
4. somente os arquivos do modulo afetado.

O mapa detalhado continua sendo
`docs/arquitetura/ARQUITETURA_GERAL.md`. Nao duplicar arquitetura aqui.

## Classificacao da tarefa

| Nivel | Tipo | Leitura | Validacao |
|---|---|---|---|
| `T0` | resposta, regra ou explicacao sem codigo | nenhuma, salvo fonte citada | nenhuma |
| `T1` | ajuste localizado ou documentacao | entrada + arquivos diretamente afetados | teste direcionado + `git diff --check` |
| `T2` | mudanca dentro de um modulo | mapa, dono, dependencia direta, codigo e teste do modulo | gates do modulo uma vez |
| `T3` | arquitetura, seguranca, migration ou dependencia transversal | mapa detalhado + decisao + impacto | autorizacao previa e gate completo proporcional |

## Localizador rapido

| Assunto | Modulo dono | Ponto inicial |
|---|---|---|
| fechamento operacional e tolerancia a erro | transversal, sem novo modulo | `docs/validacoes/OPS_GATE_01_MATRIZ.md` |
| login, usuario, permissao, MFA | `seguranca` | `apps/web/app/seguranca`, `apps/web/app/login` |
| progresso, dependencias e implantacao | `core` | `/modulos`; `docs/implantacao/00_MAPA_IMPLANTACAO_MODULOS.md` |
| perfis combinaveis e permissoes atomicas | `seguranca` | `docs/seguranca/00_MATRIZ_INICIAL_PERFIS_PERMISSOES.md` |
| ajuda, suporte e solicitacoes | `core` no portal; `seguranca` nas acoes sensiveis | `docs/suporte/00_PLANO_EVOLUCAO_SUPORTE.md`; futura `/suporte` |
| MP, produto, embalagem, cliente | `cadastros` | `apps/web/app/cadastros` |
| linguagem PT-BR e campos controlados de Cadastros | `cadastros` | `docs/UX_DATA_GOVERNANCE_PTBR.md` |
| manuais por processo e tela | modulo proprietario do fluxo | `docs/manuais/README.md` |
| pedido, credito, Kanban | `pedidos` | `apps/web/app/pedidos` |
| formacao de custos e precos | `precificacao` | `apps/web/app/custos-precos`, migration `0138` |
| lotes, movimentos e saldos | `estoque` | RPCs e migrations `est_*` |
| formula, OP, CQ, POP e transformacao | `pcp` | `apps/web/app/pcp`, `apps/web/app/producao`; `docs/decisao_pops_documentos_controlados.md` |
| romaneio e expedicao | `expedicao` | `apps/web/app/romaneios` |
| NF XML de entrada | `importacao` | `apps/web/app/importacao-xml` |
| historico do Excel | `auditoria` | `/importacao-historica/mp`; `elite_system/services/historical_workbook.py` |
| relatorio e rastreabilidade | `relatorios` | `apps/web/app/relatorios` |

## Regra de leitura

- Nao executar inventario geral para tarefa `T0` ou `T1`.
- Nao reler migrations em cadeia; comecar pela vigente e pelo teste de contrato.
- Nao repetir teste se entrada, codigo, banco e `HEAD` relevantes nao mudaram.
- Apos duas tentativas infrutiferas, investigar a causa antes de trocar de caminho.
- Gate completo fica reservado a `T3`, seguranca, release ou mudanca transversal.

## Gate de arquitetura

Exigem autorizacao previa do usuario:

- criar, remover ou dividir modulo;
- mudar dominio proprietario de tabela ou regra;
- criar dependencia entre modulos;
- mudar raiz de rota ou boundary de autenticacao/autorizacao;
- substituir framework, banco, provedor ou estrategia de deploy;
- alterar fluxo principal aprovado.

Correcao interna que preserva esses limites nao muda a arvore arquitetonica.

## Fechamento obrigatorio

Toda tarefa concluida atualiza `docs/01_ESTADO_ATUAL.md` com entrega, validacao e
proxima tarefa. Toda decisao ainda aberta entra em
`docs/02_DECISOES_PENDENTES.md`. Push continua dependendo de autorizacao.

Enquanto o `OPS-GATE-01` estiver em execucao, nenhuma lacuna futura deve ser
interpretada como autorizacao para criar modulo, dashboard, PWA, integracao ou
regra de negocio. Defeito objetivo de uma funcao existente e corrigido no
dominio proprietario; funcionalidade futura permanece bloqueada e documentada.
