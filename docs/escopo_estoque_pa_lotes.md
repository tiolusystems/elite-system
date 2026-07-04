# Escopo de estoque PA por lote

Data da etapa: 2026-07-03

## Decisao

O estoque de produto acabado deve ser controlado por lote real no banco, nao apenas por texto digitado no romaneio.

O romaneio continua sendo o evento operacional que gera baixa de PA, mas a baixa passa a afetar um livro de estoque por lote, com saldo fisico, reserva e disponibilidade.

## Regras implementadas

1. Entrada de PA cria saldo fisico positivo por lote.
2. Reserva de PA nao baixa saldo fisico; ela reduz apenas o saldo disponivel.
3. Romaneio confirmado baixa saldo fisico do lote reservado.
4. Estorno de romaneio devolve saldo fisico ao mesmo lote.
5. Ajuste manual exige motivo e gera movimento auditavel.
6. Movimentos de estoque PA sao append-only; correcao deve ser feita por novo movimento, nao por edicao do historico.
7. Reserva so pode ocorrer se o lote pertence ao mesmo produto/embalagem do item do pedido.
8. Reserva so pode ocorrer se houver saldo disponivel suficiente.

## Estrutura criada

Migration: `supabase/migrations/0007_pa_stock_lots_foundation.sql`.

Tabelas:

- `est_lotes_pa`: cadastro operacional de lote PA por produto/embalagem.
- `est_movimentos_pa`: livro append-only de movimentos fisicos de PA.
- `est_reservas_pa`: reservas ativas, baixadas, liberadas ou estornadas por romaneio.

Evolucao do romaneio:

- `exp_romaneio_itens.lote_pa_id`: vinculo opcional ao lote PA real.
- `exp_romaneio_movimentos_pa.lote_pa_id`: rastreia o lote real no movimento gerado pelo romaneio.

View:

- `est_lotes_pa_saldos`: consolida entradas, saidas, saldo fisico, reserva ativa e saldo disponivel por lote.

## Funcoes auditaveis

- `create_est_lote_pa`: cria lote PA e entrada inicial/producao/transformacao.
- `registrar_est_reserva_pa`: reserva lote PA para item de romaneio.
- `registrar_est_ajuste_pa`: registra ajuste manual positivo ou negativo com motivo obrigatorio.
- `confirmar_exp_romaneio`: agora exige reserva PA ativa e gera baixa fisica em `est_movimentos_pa`.
- `cancelar_exp_romaneio`: libera reservas ativas antes da confirmacao.
- `estornar_exp_romaneio`: gera estorno fisico de PA e marca reserva baixada como estornada.

## Auditoria

Cada funcao operacional chama `public.log_action`, mantendo trilha com hash encadeado em `action_logs`.

O livro `est_movimentos_pa` tambem tem gatilho contra `update` e `delete`. Assim, saldos sao recalculados por eventos, e nao por sobrescrita do passado.

## Validacao descartavel

Banco local descartavel:

- Pasta: `.tools/pg-validate-0007`
- Porta: `55433`
- Sem dados reais.

Smoke test executado:

1. Criou cliente, vendedor, produto, embalagem e produto/embalagem.
2. Criou lote PA com entrada de 10 unidades.
3. Criou pedido aberto de 6 unidades.
4. Criou romaneio total em rascunho.
5. Reservou 6 unidades do lote.
6. Validou saldo fisico 10, reserva 6 e saldo disponivel 4.
7. Confirmou romaneio.
8. Validou baixa fisica: saldo fisico 4, reserva 0 e saldo disponivel 4.
9. Validou pedido `fulfilled`.
10. Estornou romaneio.
11. Validou saldo restaurado para 10 e pedido reaberto como `open`.
12. Tentou reservar 11 unidades com saldo disponivel 10.
13. Validou falha esperada: `insufficient PA available balance`.
14. Tentou confirmar romaneio com lote apenas textual e sem reserva real.
15. Validou falha esperada: reserva PA ativa obrigatoria antes da confirmacao.
16. Tentou editar diretamente `est_movimentos_pa`.
17. Validou falha esperada: livro de movimentos PA append-only.
18. Cancelou romaneio com reserva ativa.
19. Validou reserva `liberada` e saldo disponivel restaurado.
20. Registrou ajuste manual negativo e positivo.
21. Validou saldo PA apos ajustes auditados.

Resultado: passou.

## Limites desta etapa

- Ainda nao ha tela operacional estetica para estoque PA.
- O modelo atual considera um lote PA por item de romaneio. Se for necessario dividir o mesmo item entre varios lotes, a proxima evolucao deve permitir multiplos itens/lotes no mesmo romaneio.
- A integracao fiscal e faturamento ainda consumira o romaneio confirmado em etapa futura.
