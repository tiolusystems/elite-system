# Matriz de propriedade dos modulos

Data: 2026-07-10

| Dominio proprietario | Tabelas/prefixos principais | Pode depender de | Escrita externa permitida |
|---|---|---|---|
| seguranca | `user_profiles`, `permission_actions`, overrides, `action_logs` | Supabase Auth | somente RPC administrativa auditada |
| cadastros | `cad_*`, `cadastro_validation_issues` | seguranca para ator | somente RPC de cadastro |
| pedidos/comercial | `com_pedidos`, itens, comissionados, credito, transicoes | cadastros, seguranca | somente RPC de pedido |
| estoque | `est_lotes_*`, `est_movimentos_*`, reservas | cadastros, seguranca | somente API/RPC de evento de estoque |
| PCP/CQ | `pcp_*` | cadastros e API de estoque | somente RPC PCP/CQ |
| expedicao | `exp_*` | pedidos e API de estoque | somente RPC de romaneio |
| faturamento | `fat_*` | pedidos e expedicao | somente RPC/evento fiscal |
| financeiro | `fin_*`, recebimentos e liberacoes legadas | pedidos, faturamento, pessoas comerciais | somente RPC/evento financeiro |
| metas | `com_meta_*` | pedidos e comissionados | somente RPC/evento de meta |
| importacao | `imp_*` | cadastros e API de estoque | somente RPC de staging/resolucao |
| auditoria/migracao | `source_*`, `migration_*`, reconciliacoes | leitura de todos os dominios | somente RPC/ferramenta controlada |
| relatorios | views `rel_*` e read models | leitura conforme RLS dos dominios | nenhuma escrita operacional |

## Regras

1. Toda tabela possui um unico dominio proprietario.
2. Leitura cruzada usa view/read model quando a consulta agrega varios dominios.
3. Escrita cruzada usa uma funcao interna estavel do dominio proprietario.
4. Orquestrador pode abrir uma unica transacao, mas nao deve duplicar a regra interna do dominio chamado.
5. Mudanca de schema deve preservar assinatura publica ou publicar migration de contrato e atualizar consumidores no mesmo bloco.
6. Excecao temporaria deve estar listada na decisao de arquitetura e protegida por teste de regressao.
7. SQL editor, script administrativo e integracao externa seguem as mesmas RPCs; service role nao e atalho operacional.
8. Toda action key declara `runtime_module_key` e `runtime_access_kind`; permissao sem dono nao entra no schema.
9. Toda rota autenticada declara modulo em `sys_module_routes`; rota nova sem registro e negada.
10. Dependencia de rollout nao concede escrita cruzada: cada dominio continua dono de suas RPCs.

## Runtime e rollout

A migration `0041` materializa esta matriz em `sys_modules`, `sys_module_routes` e `sys_module_dependencies`. Ambiente e promocao sao ledgers append-only, consultados pelo gate central de permissoes.

O acesso efetivo exige simultaneamente:

- perfil ativo;
- action key permitida;
- modulo liberado no ambiente autoritativo;
- maturidade compativel com o ambiente;
- dependencias obrigatorias disponiveis.

## Proxima extracao de contrato

1. API interna de estoque para consumo/entrada de OP.
2. API interna de estoque para baixa/estorno de romaneio.
3. API interna fiscal para devolucao.
4. API interna de metas para cancelamento/devolucao.

Essa ordem reduz o acoplamento nos fluxos mais centrais sem quebrar a atomicidade ja validada.
