# Receita RLS + RPC auditada

Data: 2026-07-04

## Objetivo

Transformar o piloto de `cadastros` em uma receita repetivel para proximos dominios.

Esta receita nasce de tres exemplos validados:

- `clientes`: escopo inicial `own/any`;
- `pessoas_comerciais`: eixo por tipo de alteracao de negocio;
- `materias_primas`: eixo por risco do campo alterado.

E passa a incluir a regra de `estoque`: eixo por tipo de evento/movimento, porque saldo nao deve ser editado diretamente.

## Arvore de decisao

### 1. Existe dono operacional claro?

Use `own/any` quando o registro tem dono operacional claro e esse dono normalmente edita o proprio registro.

Exemplos:

- cliente criado ou acompanhado por vendedor;
- pedido criado por vendedor;
- rascunho criado por usuario.

Padrao de action keys:

| Caso | Formato |
|---|---|
| Proprio escopo | `<dominio>.<entidade>.<acao>.own` |
| Fora do escopo | `<dominio>.<entidade>.<acao>.any` |

A RPC deve gravar em `permission_context`:

- `alcada_usada`;
- `scope`;
- motivo da decisao de escopo, quando aplicavel.

### 2. Registro e compartilhado, mas a sensibilidade muda por tipo de alteracao?

Use eixo por tipo de alteracao de negocio.

Exemplos:

- identidade de pessoa comercial;
- papel comercial;
- vinculo com vendedor responsavel;
- elegibilidade de comissao;
- status operacional.

Padrao de action keys:

| Caso | Formato |
|---|---|
| Identidade | `<dominio>.<entidade>.update.identity` |
| Papel/regra/vinculo | `<dominio>.<entidade>.update.<tipo_da_mudanca>` |
| Desativacao | `<dominio>.<entidade>.deactivate` |

Quando a alteracao mudar papeis, vinculos ou regras de comissao, a RPC deve registrar diff explicito, nao apenas blob bruto:

- itens adicionados;
- itens removidos;
- valor antes;
- valor depois;
- motivo padronizado quando fizer sentido.

### 3. Registro e tecnico/compartilhado, e a sensibilidade muda pelo campo?

Use eixo por risco de campo.

Exemplos:

- materia-prima;
- produto;
- embalagem;
- formula;
- CQ;
- dados regulatorios;
- estoque minimo.

Padrao de action keys:

| Caso | Formato |
|---|---|
| Identidade descritiva | `<dominio>.<entidade>.update.identity` |
| Campo tecnico | `<dominio>.<entidade>.update.technical` |
| Politica operacional | `<dominio>.<entidade>.update.<politica>` |
| Campo regulatorio | `<dominio>.<entidade>.update.regulatory` |
| Desativacao | `<dominio>.<entidade>.deactivate` |

Nao criar RPC generica que aceite campos de varios eixos ao mesmo tempo. Se uma tela visual permitir alterar multiplos grupos, a camada de aplicacao deve chamar uma RPC por eixo.

### 4. O estado e derivado de eventos ou movimentos?

Use eixo por tipo de evento/movimento quando o registro principal nao deve ser sobrescrito diretamente, e sim reconstruido a partir de fatos auditaveis.

Exemplos:

- entrada de MP por NF/XML;
- entrada de PA/PI por OP;
- reserva de PA por romaneio;
- reserva de MP/PA/PI por OP;
- baixa de PA por romaneio confirmado;
- consumo de MP/PA/PI por OP finalizada;
- transformacao de PA em PI ou PI em PA;
- ajuste manual de inventario;
- cancelamento, estorno ou reversao auditada.

Padrao de action keys:

| Caso | Formato |
|---|---|
| Entrada com documento-fonte | `<dominio>.<familia>.entry.<origem>` |
| Reserva operacional | `<dominio>.<familia>.reserve.<origem>` |
| Baixa/consumo operacional | `<dominio>.<familia>.issue.<origem>` ou `<dominio>.<familia>.consume.<origem>` |
| Transformacao | `<dominio>.<familia>.transform` |
| Ajuste manual de inventario | `<dominio>.<familia>.adjust` |
| Estorno/reversao | `<dominio>.<familia>.reverse.<origem>` |

Regras obrigatorias:

- nunca criar RPC do tipo `update_saldo` ou campo editavel de saldo fisico;
- saldo fisico deve ser derivado da soma de movimentos append-only;
- saldo disponivel deve ser derivado de saldo fisico menos reservas ativas;
- reserva nao baixa saldo fisico, apenas reduz disponibilidade;
- movimento deve ter `tipo_movimento`, `quantidade`, origem, documento-fonte quando houver e usuario;
- sinal da quantidade deve ser validado por tipo de movimento no banco;
- correcao de erro deve ser novo movimento de reversao/ajuste, nao edicao do movimento original;
- tabelas de movimento devem ter gatilho contra `update` e `delete`;
- ajuste manual de inventario exige motivo obrigatorio e alcada mais forte que movimento com documento-fonte.

Para RPCs de movimento, `before_json` e `after_json` nao representam uma edicao do mesmo registro. Eles devem representar, no minimo, o estado derivado antes/depois do lote ou documento-fonte:

- saldo fisico antes/depois;
- saldo disponivel antes/depois;
- reservas ativas relacionadas;
- movimento ou reserva criada;
- origem operacional que justificou o evento.

Assim, o log explica por que o saldo mudou sem transformar saldo em estado editavel.

## Onde validar regras

### Banco

Validacao deve ficar no banco quando a regra e invariavel e protege integridade do dado.

Exemplos:

- NCM com exatamente 8 digitos;
- densidade positiva;
- estoque minimo maior ou igual a zero;
- status dentro de lista permitida;
- motivo obrigatorio;
- soft-delete sem hard-delete.

Motivo: a RPC `security definer` e o ultimo ponto de controle antes do dado virar verdade. Client ajuda a UX, mas nao e fronteira de seguranca.

### Aplicacao

Validacao pode ficar na aplicacao quando depende de UX, fluxo, perfil visual ou escolha de tela.

Exemplos:

- mostrar campos obrigatorios antes do submit;
- separar uma tela multi-eixo em chamadas de RPC por eixo;
- formatar mensagem de erro;
- montar detalhe visual de diff;
- bloquear submit incompleto no browser.

Regra: se a validacao protege integridade permanente, tambem deve existir no banco.

## Contrato de RPC

Toda RPC de escrita critica deve:

1. validar permissao no inicio com action key especifica;
2. travar o registro com `for update` quando houver alteracao de linha existente;
3. carregar `before_json`;
4. validar entradas no banco;
5. executar a alteracao;
6. carregar `after_json`;
7. chamar `log_audit_event(...)`;
8. retornar o ID da entidade alterada.

Exemplo estrutural:

```sql
perform public.require_current_user_permission('<action_key>');

select to_jsonb(t)
  into v_before
  from public.<tabela> t
 where t.id = p_id
 for update;

-- validar entradas e executar update

select to_jsonb(t)
  into v_after
  from public.<tabela> t
 where t.id = p_id;

perform public.log_audit_event(
  '<dominio>',
  '<tabela>',
  p_id::text,
  '<acao_auditavel>',
  '<action_key>',
  'success',
  v_before,
  v_after,
  jsonb_build_object('alcada_usada', '<action_key>', 'axis', '<eixo>'),
  'database_rpc',
  jsonb_build_object('source', '<nome_da_funcao>', 'motivo', trim(p_motivo))
);
```

## Negativa de permissao

Nao tentar logar negativa dentro da mesma funcao que vai dar `raise exception`, porque o PostgreSQL reverte a transacao.

Contrato atual:

- RPC bloqueia com `not allowed: <action_key>`;
- camada Next.js chama `auditedRpc`;
- `auditedRpc` chama `log_permission_denied(...)` em chamada separada;
- testes impedem Server Actions de chamar `.rpc(...)` diretamente.

Limite: acesso direto ao banco fora do Next.js, como SQL editor, script administrativo ou integracao futura, nao fica coberto pelo wrapper. Esse caminho precisa usar RPC auditada ou auditoria propria.

## Soft-delete

Cadastro mestre e dado operacional historico. Nao usar hard-delete como regra normal.

Padrao:

- coluna `status`;
- desativacao por `status = 'inactive'`;
- RPC de desativacao propria;
- motivo obrigatorio;
- `before_json.status` e `after_json.status` validados em smoke.

Hard-delete so pode existir em rotina tecnica excepcional, documentada, restrita e fora do fluxo operacional comum.

## Checklist de migration

Antes de considerar uma migration pronta:

1. action keys novas em `permission_actions`;
2. uma RPC por eixo real de alcada;
3. `revoke all on function ... from public`;
4. `grant execute ... to authenticated`;
5. escrita direta nas tabelas ja bloqueada por RLS/grants do dominio;
6. validacoes de integridade dentro do SQL;
7. `before_json` e `after_json`;
8. `permission_context` com `alcada_usada` e eixo/escopo;
9. `metadata_json` com diff especifico quando blob bruto for ruim para auditoria;
10. teste estatico contra regressao relevante;
11. smoke em PostgreSQL descartavel limpo;
12. documento de validacao.

## Smoke minimo

Para cada dominio:

| Caso | Obrigatorio |
|---|---|
| Usuario ativo permitido | Sim |
| Escrita direta na tabela bloqueada | Sim |
| RPC permitida gera log `success` | Sim |
| `before_json` e `after_json` conferidos | Sim |
| Override negado gera `not allowed` | Sim |
| `log_permission_denied(...)` registra `denied` | Sim |
| Usuario sem perfil bloqueado | Sim |
| Usuario inativo bloqueado | Sim |
| Role `anon` bloqueada | Sim |
| Validacao negativa de dominio | Quando houver regra de formato/faixa |

## Ordem recomendada apos cadastros

Priorizar `estoque` antes de `seguranca`.

Motivo:

- `estoque` toca PCP, romaneio, CQ, XML/NF, producao e relatorios;
- o dominio tem impacto operacional real e alto acoplamento;
- movimentos e reservas exigem auditoria forte e append-only;
- aplicar a receita em estoque testa o padrao sob pressao operacional maior.

`seguranca` deve receber a receita madura depois desse passo, porque e a tabela mais sensivel do sistema. Nela, ajuste de padrao e endurecimento de permissao nao devem acontecer ao mesmo tempo.
