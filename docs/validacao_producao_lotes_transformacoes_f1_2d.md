# Validacao F1.2d - Lotes, Estoque e Transformacoes

Data: 2026-07-15

## Escopo

O bloco separa do painel legado as consultas e operacoes de:

- lotes MP, PA e PI;
- saldos fisico, reservado e disponivel;
- validade, status e origem;
- liberacao auditada de lote PA/PI bloqueado;
- OP de reprocessamento e transformacao;
- consumo do lote de origem e geracao de novo lote PA/PI.

Nenhuma migration foi criada. As telas reutilizam os contratos auditados de OP,
reserva, inicio, cancelamento, CQ, finalizacao e liberacao de lote ja existentes.

## Rotas

- `/producao/estoque` - consulta responsiva do livro de estoque derivado;
- `/producao/transformacoes` - abertura e acompanhamento de OP do tipo
  `reprocessamento`;
- `/producao/qualidade?tipo=reprocessamento` - CQ e finalizacao filtrados para
  transformacoes em processo.

## Cenario funcional local

Todos os registros usados possuem identificacao `HML` e pertencem ao Supabase
local de teste.

1. Selecionado o lote MP `HML-MP-0058-L01`, com 90 kg fisicos e disponiveis.
2. Aberta a OP `OP-20260715-0000003`, tipo `reprocessamento`, pela formula
   `9058 - HML Produto PI 0058 / v1`.
3. Reservados 10 kg do lote MP; o saldo fisico permaneceu 90 e o disponivel
   passou a 80.
4. Iniciada a OP pela tela de Transformacoes.
5. Registrado CQ aprovado com pH 6,5, densidade 1 kg/L, volume 10 L, massa
   10 kg, temperatura 25 C e participantes de teste.
6. Finalizada a OP com saida PI de 10 kg.
7. A transacao consumiu a reserva e criou o lote
   `PI-20260715-0000002`, disponivel e com origem `pcp_op:3:finish`.

## Reconciliacao

| Medida | Antes | Durante a reserva | Depois |
|---|---:|---:|---:|
| MP fisica | 90 | 90 | 80 |
| MP reservada | 0 | 10 | 0 |
| MP disponivel | 90 | 80 | 80 |
| PI fisico agregado | 10 | 10 | 20 |

O card final da OP informa o componente como `Consumido`, a reserva como
`baixada`, CQ `aprovado` e uma saida PI disponivel. Nao houve edicao direta de
saldo.

## Achado funcional controlado

Uma primeira OP de teste, `OP-20260715-0000002`, demonstrou que
`quantidade_planejada` nao escala os componentes da formula. A OP foi cancelada
antes de reserva ou movimento de estoque. A interface passou a chamar esse
valor de quantidade de referencia e a tela de Transformacoes nao o solicita.

A definicao de lote absoluto ou escala proporcional, incluindo rendimento,
unidade, perdas e arredondamento, foi registrada como `DEC-013`. Nenhuma regra
foi inventada nesta entrega.

## Responsividade

As duas rotas foram verificadas em viewport com 1265 px:

- Estoque: `clientWidth = 1265`, `scrollWidth = 1265`;
- Transformacoes: `clientWidth = 1265`, `scrollWidth = 1265`.

Os lotes usam cards responsivos e nao uma tabela larga. As capturas permanecem
como evidencia local e nao sao versionadas.

## Validacao automatizada

- `python -m unittest tests.test_production_operational_workbench`: 9 testes
  aprovados;
- TypeScript `--noEmit --incremental false`: aprovado;
- ESLint direcionado aos arquivos web alterados: aprovado;
- build Next.js 16.2.10: aprovado, incluindo as rotas
  `/producao/estoque` e `/producao/transformacoes`;
- `git diff --check`: aprovado no fechamento.

## Limites

- validacao executada somente no Supabase local de teste;
- nenhum dado foi escrito no Supabase cloud;
- `F1.2d` ainda nao foi publicada;
- homologacao autenticada do bloco anterior no staging aguarda o login de
  Luciano;
- ativacao de saldos operacionais reais continua bloqueada pela `DEC-012`.
