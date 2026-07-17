# UX-01C.4 - Decisão de tipos de insumo

Status: autorizada por Luciano e implementada na migration `0063_govern_raw_material_input_types.sql`.

## Problema

`cad_materias_primas.tipo` é texto livre. O campo será usado por estoque,
conversões, fórmulas, produção e relatórios; portanto, não pode depender de
grafias livres como `liquido`, `líquido`, `LIQ` ou nomes históricos.

O sistema não deve inventar uma classificação para valores existentes. Todo
valor sem correspondência homologada deve continuar preservado e ficar em
revisão.

## Contrato relacional proposto

### `cad_tipos_insumo`

| Campo | Regra |
|---|---|
| `id` | Chave primária técnica |
| `codigo` | Chave natural estável, única, sem depender do rótulo |
| `nome` | Rótulo operacional em PT-BR |
| `descricao` | Explicação opcional do uso |
| `status` | `active`, `pending_review` ou `inactive` |
| `origem_dados` | `sistema` ou `excel_legado` |
| `created_by` / `updated_by` | Ator humano ou ator de migração |
| `created_at` / `updated_at` | Rastreabilidade temporal |

Não haverá catálogo inicial inventado. Os códigos e rótulos operacionais serão
homologados por Luciano antes de qualquer carga definitiva.

### Alteração em `cad_materias_primas`

- adicionar `tipo_insumo_id bigint null` com FK para `cad_tipos_insumo(id)`;
- manter temporariamente `tipo` para preservar o valor original e permitir
  reconciliação;
- impedir que a interface operacional continue gravando novo texto livre;
- tornar a FK obrigatória somente depois do backfill homologado e da resolução
  de todas as pendências;
- nunca substituir silenciosamente o conteúdo histórico de `tipo`.

## Backfill e pendências

1. Normalizar apenas para comparação: caixa, acentos e espaços.
2. Gerar uma fila com cada valor histórico distinto e sua contagem.
3. Luciano escolhe o tipo governado correspondente ou marca `revisar`.
4. Registros sem decisão mantêm `tipo_insumo_id = null` e passam para
   `status = pending_review` quando ainda não estiverem em revisão.
5. O valor original permanece disponível para auditoria e reconciliação.
6. Nenhum histórico é promovido automaticamente para operação corrente.

## RPCs e alçadas

| Ação | RPC proposta | Alçada |
|---|---|---|
| Criar tipo | `create_cad_tipo_insumo` | `cadastros.tipos_insumo.create` |
| Alterar identidade | `update_cad_tipo_insumo` | `cadastros.tipos_insumo.update` |
| Ativar | `activate_cad_tipo_insumo` | `cadastros.tipos_insumo.activate` |
| Desativar | `deactivate_cad_tipo_insumo` | `cadastros.tipos_insumo.deactivate` |
| Classificar MP | `set_cad_materia_prima_tipo` | `cadastros.materias_primas.update.technical` |

Todas as escritas devem usar `begin_audited_rpc` e
`log_audited_rpc_change`, registrar `before_json`/`after_json`, motivo e ator.
Não haverá escrita direta para `authenticated`.

## Leitura e RLS

- leitura somente para usuário autenticado com perfil ativo;
- nenhuma permissão para `anon` ou `PUBLIC`;
- `service_role` nunca será exposta ao cliente;
- catálogo inativo continua consultável para histórico, mas não aparece como
  opção para novos cadastros;
- origem e chaves técnicas não serão exibidas como texto cru na interface.

## Interface após autorização

- filtro por tipo, situação e texto;
- seletor relacional de tipo de insumo no cadastro e na edição;
- opção `Em revisão` quando a MP ainda não tiver classificação homologada;
- painel de pendências com valor histórico preservado;
- mensagens PT-BR para vazio, erro, bloqueio e sucesso;
- nenhum underscore, enum cru ou erro PostgreSQL visível;
- layouts desktop, notebook e mobile sem rolagem horizontal.

## Idempotência e integridade

- `codigo` único por tipo de insumo;
- FK impede referência inexistente;
- tipo inativo não pode ser atribuído a novo cadastro;
- reexecução do backfill não duplica decisões nem altera registros já
  homologados;
- desativação é lógica, nunca `DELETE` físico.

## Validação exigida

- instalação da migration em PostgreSQL descartável `elite-validation-*`;
- upgrade da cadeia atual sem reset do runtime ativo;
- smoke de usuário autorizado, sem alçada e anônimo;
- teste de FK, unicidade, desativação, idempotência e auditoria;
- teste de que MP histórica sem decisão permanece em revisão;
- TypeScript, ESLint, build dirigido e contrato visual após a UI;
- capturas reais em 360x800, 390x844, 1366x768 e 1920x1080;
- nenhuma captura ou dado operacional versionado.

## Rollback

Antes de uso operacional, o rollback pode remover RPCs, policies, FK, coluna e
catálogo, preservando `cad_materias_primas.tipo`. Depois que a FK se tornar a
fonte oficial, o rollback deve ser por migration compensatória e nunca apagar
as classificações já registradas.

## Limite da decisão

Esta decisão cobre somente o pacote estrutural de tipos de insumo. Clientes,
endereços, municípios, contatos, revendas, veículos, produtos e embalagens
permanecem fora desta migration e continuam registrados na matriz consolidada.
