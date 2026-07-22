from __future__ import annotations

import unittest
from pathlib import Path


REPO_ROOT = Path(__file__).resolve().parents[1]
MIGRATION_0027 = REPO_ROOT / "supabase" / "migrations" / "0027_finance_commission_idempotency_contract.sql"
PEDIDOS_ACTIONS = REPO_ROOT / "apps" / "web" / "app" / "pedidos" / "financeiro" / "actions.ts"
COMMISSIONS_DOC = REPO_ROOT / "docs" / "escopo_comissoes_recebimentos_credito.md"


class FinanceCommissionIdempotencyContractTests(unittest.TestCase):
    def test_0027_adds_database_idempotency_for_allocation_commission_release(self) -> None:
        text = MIGRATION_0027.read_text(encoding="utf-8")

        self.assertIn("idx_com_comissao_liberacoes_alocacao_comissionado_once", text)
        self.assertIn("on public.com_comissao_liberacoes(alocacao_id, comissionado_id)", text)
        self.assertIn("where status = 'liberada' and alocacao_id is not null", text)
        self.assertIn("idx_fin_comissao_movimentos_liberacao_credit_once", text)
        self.assertIn("comissao_ja_liberada_para_este_recebimento", text)

    def test_0027_release_function_locks_receipt_and_allocation_not_order(self) -> None:
        text = MIGRATION_0027.read_text(encoding="utf-8")

        self.assertIn("create or replace function public.liberar_fin_comissoes_recebimento", text)
        self.assertIn("where id = p_recebimento_id\n   for update", text)
        self.assertIn("for update of alocacao", text)
        self.assertNotIn("for update of pedido", text)
        self.assertIn("'financeiro.commissions.release'", text)
        self.assertIn("'financial_event'", text)

    def test_0027_uses_incremental_event_calculation_not_accumulated_recalculation(self) -> None:
        text = MIGRATION_0027.read_text(encoding="utf-8")

        self.assertIn("v_percentual_recebido := least(v_alocacao.valor_alocado / v_alocacao.pedido_valor_total, 1);", text)
        self.assertIn("v_valor_liberar := v_comissionado.valor_previsto * v_percentual_recebido;", text)
        self.assertIn("'modelo_calculo', 'incremental_por_evento'", text)
        self.assertNotIn("v_valor_ja_liberado", text)
        self.assertNotIn("v_valor_alvo_liberado", text)

    def test_0027_standardizes_manual_adjustment_reason(self) -> None:
        text = MIGRATION_0027.read_text(encoding="utf-8")
        doc = COMMISSIONS_DOC.read_text(encoding="utf-8")

        for reason in ("correcao_calculo", "estorno_devolucao", "acordo_comercial", "compensacao_futura", "outro"):
            self.assertIn(reason, text)
            self.assertIn(reason, doc)

        self.assertIn("motivo_detalhe is required when motivo_codigo is outro", text)
        self.assertIn("invalid motivo_codigo", text)
        self.assertIn("motivo_codigo", text)

    def test_receipt_server_action_supplies_failure_contract_metadata(self) -> None:
        text = PEDIDOS_ACTIONS.read_text(encoding="utf-8")

        self.assertIn('action_key: "financeiro.receipts.register"', text)
        self.assertIn('axis: "financial_event"', text)
        self.assertIn('domain: "financeiro"', text)
        self.assertIn('entity: "com_recebimentos"', text)
        self.assertIn('failure_action: "financeiro.recebimento_failed"', text)


if __name__ == "__main__":
    unittest.main()
