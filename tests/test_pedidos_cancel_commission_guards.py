from __future__ import annotations

import re
import unittest
from pathlib import Path


REPO_ROOT = Path(__file__).resolve().parents[1]
MIGRATION_0029 = REPO_ROOT / "supabase" / "migrations" / "0029_pedidos_cancel_commission_guards.sql"
COMMISSIONS_DOC = REPO_ROOT / "docs" / "escopo_comissoes_recebimentos_credito.md"
VALIDATION_DOC = REPO_ROOT / "docs" / "validacao_pedidos_lifecycle_audit_contract.md"


class PedidosCancelCommissionGuardsTests(unittest.TestCase):
    def test_0029_adds_cancelled_commission_status(self) -> None:
        text = MIGRATION_0029.read_text(encoding="utf-8")

        self.assertIn("drop constraint if exists com_pedido_comissionados_status_check", text)
        self.assertIn("'cancelada'", text)
        self.assertIn("bloqueada = temporaria; cancelada = definitiva", text)

    def test_order_creation_commissions_only_for_sales(self) -> None:
        body = self._function_body("create_com_pedido_operacional")

        self.assertIn("p_tipo_pedido = 'venda'", body)
        self.assertNotIn("p_tipo_pedido <> 'bonificacao'", body)

    def test_cancel_blocks_paid_commission_and_active_op(self) -> None:
        body = self._function_body("cancelar_com_pedido")

        self.assertIn("from public.com_pedido_comissionados", body)
        self.assertIn("comissionado.status = 'paga'", body)
        self.assertIn("from public.fin_comissao_movimentos", body)
        self.assertIn("movimento.tipo_movimento = 'debito_pagamento'", body)
        self.assertIn("pedido has paid commission; use post-payment reversal flow", body)
        self.assertIn("from public.pcp_ordens_producao op", body)
        self.assertIn("op.status in ('draft', 'planned', 'in_process')", body)
        self.assertIn("pedido has active op; cancel op first", body)

    def test_cancel_moves_predicted_or_blocked_commission_to_cancelled(self) -> None:
        body = self._function_body("cancelar_com_pedido")

        self.assertIn("set status = 'cancelada'", body)
        self.assertIn("status in ('prevista', 'bloqueada')", body)
        self.assertNotIn("set status = 'bloqueada'", body)

    def test_pcp_orders_can_be_linked_to_order_for_cancel_guard(self) -> None:
        text = MIGRATION_0029.read_text(encoding="utf-8")

        self.assertIn("add column if not exists pedido_id bigint references public.com_pedidos(id)", text)
        self.assertIn("idx_pcp_ordens_pedido_status", text)

    def test_commissions_doc_records_meta_and_tier_decisions(self) -> None:
        text = COMMISSIONS_DOC.read_text(encoding="utf-8")

        self.assertIn("pedido so entra na meta quando estiver `open`", text)
        self.assertIn("periodo customizado", text)
        self.assertIn("data do pedido", text)
        self.assertIn("ledger append-only", text)
        self.assertIn("motivo_devolucao", text)
        self.assertIn("qualidade", text)
        self.assertIn("fracionamento por volume acumulado", text)
        self.assertIn("taxa congelada no momento da criacao do pedido", text)
        self.assertIn("lock por vendedor + periodo", text)

    def test_validation_doc_records_0029_scope(self) -> None:
        text = VALIDATION_DOC.read_text(encoding="utf-8")

        self.assertIn("0029_pedidos_cancel_commission_guards.sql", text)
        self.assertIn("devolucao nao gera comissionado", text)
        self.assertIn("comissao `paga` bloqueia cancelamento", text)
        self.assertIn("OP ativa vinculada bloqueia cancelamento", text)

    def _function_body(self, function_name: str) -> str:
        text = MIGRATION_0029.read_text(encoding="utf-8")
        pattern = re.compile(
            rf"create or replace function public\.{re.escape(function_name)}\b.*?\n\$\$;",
            re.DOTALL | re.IGNORECASE,
        )
        match = pattern.search(text)
        self.assertIsNotNone(match, f"Function {function_name} not found")
        return match.group(0).lower()


if __name__ == "__main__":
    unittest.main()
