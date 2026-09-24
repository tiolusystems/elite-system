# ADR-016 - Motor de formulas versionado

Status: aceita e implementada como fundacao PRC-02B na migration 0151.

## Problema

O PRC-01 reproduz corretamente a regra vigente da Elite, mas sua formula esta
codificada na RPC de calculo. Ela soma 11 componentes fixos, escolhe entre
margem liquida e markup, calcula o preco a prazo por uma unica expressao e gera
18 vencimentos de 30 a 540 dias. Esse contrato deve continuar reproduzivel, mas
nao pode ser a formula universal de um produto SaaS.

Empresas diferentes precisam combinar parametros e prazos diferentes sem
alterar codigo. A solucao nao pode executar SQL, JavaScript, Python, `eval` ou
texto arbitrario fornecido pelo usuario.

## Decisao

O dominio `precificacao` possui, na migration aditiva 0151, um motor
deterministico baseado em AST JSON declarativa. A definicao matematica, o
catalogo semantico dos parametros, os valores usados em cada execucao e a grade
de prazos sao fatos distintos e versionados.

O PRC-01 continua oficial. O motor novo nasce em shadow mode e apenas compara
seus resultados com os calculos atuais. Nenhuma RPC, snapshot, exportacao ou
tabela existente muda de significado nesta fase.

## Modelo de dominio implementado

| Entidade | Responsabilidade |
|---|---|
| `prc_formula_perfis` | identidade estavel da formula, com codigo emitido pelo banco |
| `prc_formula_versoes` | documento canonico append-only com AST a vista, AST a prazo, politica de arredondamento e hash |
| `prc_formula_parametros` | catalogo semantico de parametros conhecidos pelo dominio |
| `prc_formula_versao_parametros` | contrato exato de parametros aceitos por uma versao |
| `prc_grade_prazos` | identidade estavel de uma grade |
| `prc_grade_prazo_versoes` | versao append-only da grade |
| `prc_grade_prazo_itens` | ordem, dias e fator de periodo de cada prazo |
| `prc_formula_revisoes` | decisao segregada de aprovacao ou rejeicao |
| `prc_formula_lifecycle_eventos` | ativacao, substituicao e retirada append-only |
| `prc_formula_shadow_execucoes` | avaliacao append-only do motor novo sem efeito oficial |
| `prc_formula_promocao_evidencias` | fundacao para evidencia humana futura, sem promocao automatica |

As entidades seguem os prefixos `prc_*`, a auditoria e o default-deny do dominio.

## Identidade, versao e estado

- o perfil possui identidade estavel e codigo `FML-########` emitido pelo banco;
- a grade possui identidade estavel e codigo `PRZ-########` emitido pelo banco;
- cada alteracao cria uma nova versao; versoes nao sofrem `UPDATE` ou `DELETE`;
- cada versao registra autor, motivo, instante, documento canonico e SHA-256;
- aprovacao exige ator diferente do autor;
- revisao usa `PENDING`, `APPROVED` e `REJECTED`;
- lifecycle do motor shadow usa `ACTIVE`, `SUPERSEDED` e `WITHDRAWN`;
- somente versoes aprovadas podem ser ativadas e avaliadas em shadow mode;
- ativar uma nova versao substitui atomicamente a versao ativa anterior;
- versoes retiradas ou substituidas sao historicas e nao podem ser reativadas;
- `ACTIVE` nao promove a formula ao calculo oficial; PRC-01 continua oficial;
- uma execucao congela os IDs e hashes exatos da formula e da grade usadas.

## Separacao semantica

1. A definicao da formula e a AST que combina valores.
2. O parametro define nome, tipo e unidade, sem conter valor operacional.
3. O valor do parametro pertence a uma execucao ou rodada e fica congelado no
   snapshot dessa execucao.
4. A grade de prazos define os vencimentos avaliados e suas variaveis de
   periodo, independentemente da formula.

Uma formula usa somente os parametros declarados em sua versao. A entrada de
avaliacao deve conter exatamente os valores requeridos; parametro ausente ou
extra falha fechado. Para deixar de usar um parametro, cria-se outra versao da
formula sem referencia a ele.

## DSL e AST

A DSL e um documento JSON validado. Nao existe parser de expressao textual. A
raiz e uma arvore composta somente pelos seguintes tipos de no:

| `kind` | Conteudo permitido |
|---|---|
| `constant` | decimal normalizado como texto e unidade explicita |
| `parameter` | codigo de parametro declarado na versao |
| `variable` | `cash_price`, `term_period` ou `term_days` |
| `operation` | operador permitido e lista ordenada de argumentos |

Operadores permitidos na versao inicial:

- `add`;
- `sub`;
- `mul`;
- `div`;
- `pow`.

Exemplo reduzido:

```json
{
  "schema": "prc-formula-ast-v1",
  "result_unit": "BRL_L",
  "root": {
    "kind": "operation",
    "op": "div",
    "args": [
      {"kind": "parameter", "code": "custo_base"},
      {
        "kind": "operation",
        "op": "sub",
        "args": [
          {"kind": "constant", "value": "1", "unit": "FRACTION"},
          {"kind": "parameter", "code": "encargos_e_lucro"}
        ]
      }
    ]
  }
}
```

Chaves desconhecidas, operador desconhecido, no sem tipo, profundidade ou
quantidade acima do limite e referencia nao declarada invalidam o documento.
Os limites implementados sao 32 niveis e 512 nos por AST.
Cada token decimal canonico tem no maximo 64 caracteres e `pow` aceita
expoente de magnitude ate 32. Exceder esses limites falha fechado antes do
calculo, sem alterar os perfis Elite nem o exemplo alternativo.

## Tipos e unidades

O catalogo inicial e fechado e extensivel por migration:

| Tipo semantico | Unidade inicial | Uso |
|---|---|---|
| `money_rate` | `BRL_L` | custo ou preco por litro |
| `fraction` | `FRACTION` | comissao, tributo, margem, markup, juros e risco |
| `scalar` | `SCALAR` | multiplicador adimensional |
| `period` | `PERIOD` | fator de periodo da grade |
| `duration` | `DAY` | prazo em dias |

Regras minimas de inferencia:

- soma e subtracao exigem tipos e unidades iguais;
- multiplicacao por `FRACTION` ou `SCALAR` preserva a unidade do outro operando;
- divisao por `FRACTION` ou `SCALAR` preserva a unidade do numerador;
- divisao de unidades iguais produz `SCALAR`;
- `pow` exige base adimensional e expoente `SCALAR` ou `PERIOD`;
- a formula a vista e a formula a prazo devem resultar em `BRL_L`;
- divisao por zero, potencia fora do dominio numerico e resultado nao finito
  falham fechado;
- todos os calculos usam `numeric`, nunca ponto flutuante.

Assim, uma expressao que some `BRL_L` com `FRACTION` e recusada antes da
aprovacao.

## Formula a vista e formula a prazo

Cada versao possui duas ASTs independentes:

- `formula_vista_ast` pode usar parametros;
- `formula_prazo_ast` pode usar parametros, `cash_price`, `term_period` e
  `term_days`.

A formula a prazo nao e gerada implicitamente a partir da formula a vista. Ela
e validada, versionada, aprovada e hasheada no mesmo documento canonico.

## Grade de prazos

Cada item de uma versao da grade possui:

- `ordem`, unica e crescente;
- `prazo_dias`, positivo e unico;
- `fator_periodo`, decimal positivo usado por `term_period`.

A Elite usa 18 itens: dias 30, 60, ..., 540 e fatores 1, 2, ..., 18. Outra
empresa pode usar 28, 56 e 84 dias com fatores 1, 2 e 3, ou 30, 45, 60 e 90
dias com fatores definidos explicitamente. O avaliador nunca deriva o fator do
numero de dias de forma implicita.

## Validacao e avaliador deterministico

A migration 0151 mantem em `precificacao_internal` funcoes privadas
equivalentes a:

- `validar_prc_formula_ast(jsonb, jsonb)`;
- `avaliar_prc_formula_ast(jsonb, jsonb, jsonb)`.

O primeiro JSON e a AST, o segundo e o contrato ou os valores tipados e o
terceiro, quando aplicavel, contem somente as variaveis de prazo. As funcoes nao
sao executaveis por `PUBLIC`, `anon` ou `authenticated`.

Antes da aprovacao, a validacao comprova estrutura, operadores, referencias,
tipos, unidades, resultado e limites de complexidade. Na avaliacao, o motor
percorre a arvore por casos fechados e usa somente operacoes `numeric`. Nao ha
SQL dinamico nem chamada de funcao indicada pelo documento.

## Documento canonico e hash

O documento `prc-formula-v1` contem identidade e versao, ASTs, contrato de
parametros, `term_grid_version_id` e `term_grid_sha256`, arredondamento, escala
e versao do avaliador. Na execucao, os hashes persistidos da formula e da grade
sao revalidados antes de produzir resultado; o documento shadow inclui os dois
IDs e os dois hashes. Decimais sao strings normalizadas; arrays preservam
ordem semantica; objetos sao `jsonb`.
O SHA-256 usa o helper canonico do PRC sobre esse documento completo.

Uma execucao persiste valores tipados, resultados exatos e comerciais, ator e
instante em fato append-only. Alterar uma formula futura nao altera esse fato
nem qualquer exportacao historica do PRC-01.

## Golden master Elite

O golden master usa dois perfis aprovados, ambos com a grade Elite:

1. `elite_margem_liquida_v1`:
   `custo_base / (1 - comissao - tributacao - marketing - lucro_minimo)`.
2. `elite_markup_v1`:
   `custo_base * (1 + markup) / (1 - comissao - tributacao - marketing)`.

`custo_base` e a soma de materia-prima, embalagem, custo de pontuacao do
vendedor, custo de pontuacao da revenda, premiacao da revenda, premio de
producao e frete.

Ambos usam a formula a prazo:

```text
cash_price + cash_price *
  ((((1 + juros_mensais) ^ term_period) - 1) + risco) /
   (1 - comissao - tributacao - marketing))
```

A paridade exige igualdade exata dos intermediarios `numeric`, dos 18 valores
exatos e dos valores comerciais com `HALF_UP` e duas casas. Nao ha tolerancia
por ponto flutuante.

## Perfil alternativo

O mesmo avaliador deve aceitar outro perfil, sem mudanca de codigo:

```text
formula_vista = (materia_prima + embalagem + frete) * (1 + markup)
formula_prazo = cash_price * ((1 + juros_mensais) ^ term_period)
parametros = materia_prima, embalagem, frete, markup, juros_mensais
grade = 28, 56, 84 dias; fatores = 1, 2, 3
```

Esse perfil declara exatamente esses cinco parametros. Nao requer lucro_minimo,
comissao, tributacao, marketing, risco, pontuacoes ou premiacoes.

## Aprovacao e auditoria

Criacao, nova versao, revisao e ativacao usam RPCs auditadas, idempotentes e
serializadas. O autor nao aprova a propria versao. Tabelas de definicao,
revisao, grade e execucao shadow sao append-only. Leitura da aplicacao ocorre
por superficie governada; tabelas e helpers privados permanecem sem grants para
`anon` e `authenticated`.

## Compatibilidade e strangler

- `prc_politicas`, calculos, snapshots, RPCs e exportacoes atuais permanecem;
- a migration 0151 nao altera a semantica de `prc-calculation-v2`;
- a RPC atual continua produzindo o resultado oficial;
- o motor novo recebe valores explicitos de entrada e grava somente resultado
  shadow, sem alterar fatos oficiais;
- divergencia shadow nao muda preco, decisao ou publicacao comercial;
- a troca do motor oficial exige gate separado e decisao humana explicita.

## Shadow mode

Cada execucao shadow pode referenciar o calculo oficial e registra IDs e hashes
da formula e da grade, hash de entrada, preco a vista, prazos e hash do resultado.
A comparacao com o calculo oficial e um gate posterior; a 0151 nao grava um
relatorio de diferencas. Erro no motor novo nao transforma seu resultado em fato oficial.

O gate de paridade exige golden master Elite, perfil alternativo, repetibilidade,
isolamento entre empresas, seguranca da AST, unidades, concorrencia,
idempotencia e historico imutavel.

## Limite organizacional

O produto opera com um database por organizacao. O banco e a fronteira de
isolamento e a migration nao cria `tenant_id`, `company_id` ou identificador
organizacional paralelo. Perfis e grades continuam configuracoes do dominio,
enquanto tipos e unidades permanecem controlados por migration.

## Governanca decidida

As permissoes `precificacao.formula.manage`, `precificacao.formula.review` e
`precificacao.formula.lifecycle` separam criacao, revisao e operacao. Todas sao
default-deny. O autor nao revisa a propria versao. A autoridade futura de
promocao pertence ao lifecycle e dependera de evidencia explicita; a 0151 nao
implementa promocao automatica nem substitui o calculo oficial.

## Riscos

- uma DSL ampla demais recria execucao de codigo por outro nome;
- uma DSL estreita demais pode nao representar regras futuras;
- arredondamento em nos intermediarios pode quebrar o golden master;
- unidade incorreta pode produzir resultado numericamente valido e
  semanticamente falso;
- ativacao prematura pode substituir o calculo oficial sem paridade;
- escopo organizacional incorreto pode compartilhar formula entre empresas.

## Nao objetivos do PRC-02B

- alterar `/custos-precos`;
- substituir o calculo atual;
- publicar lista comercial;
- definir UI de edicao da AST;
- criar linguagem textual;
- implementar rodada, grupos, lotes ou fontes automaticas.

## Evidencia executavel

O smoke `tests/sql/prc02_versioned_formula_engine.sql` cobre golden masters,
perfil alternativo, segregacao, lifecycle, idempotencia, AST fechada, unidades,
limites e default-deny. O contrato de upgrade preserva a superficie PRC-01 ao
aplicar `0150 -> 0151`.
