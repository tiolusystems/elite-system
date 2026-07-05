from __future__ import annotations

import re
import unittest
from pathlib import Path


REPO_ROOT = Path(__file__).resolve().parents[1]
MIGRATION_0031 = REPO_ROOT / "supabase" / "migrations" / "0031_pedidos_post_payment_reversal_contract.sql"
COMMISSIONS_DOC = REPO_ROOT / "docs" / "escopo_comissoes_recebimentos_credito.md"
VALIDATION_DOC = REPO_ROOT / "docs" / "validacao_pedidos_lifecycle_audit_contract.md"


class PedidosPostPaymentReversalContractTests(unittest.TestCase):
    def test_0031_extends_fiscal_return_schema(self) -> None:
        text = MIGRATION_0031.read_text(encoding="utf-8")

        self.assertIn("'pedidos.post_payment_reversal'", text)
        self.assertIn("nota_devolvida_id bigint references public.fat_notas_fiscais(id)", text)
        self.assertIn("nota_item_devolvido_id bigint references public.fat_nota_fiscal_itens(id)", text)
        self.assertIn("'devolucao'", text)
        self.assertIn("tipo = 'devolucao'", text)
        self.assertIn("nota_devolvida_id is not null", text)
        self.assertIn("idx_fat_nf_devolvida", text)
        self.assertIn("idx_fat_nf_itens_devolvidos", text)

    def test_rpc_uses_audited_contract_and_requires_paid_fulfilled_order(self) -> None:
        body = self._function_body("registrar_com_pedido_estorno_pos_pagamento")

        self.assertIn("public.begin_audited_rpc(", body)
        self.assertIn("perform public.log_audited_rpc_change(", body)
        self.assertIn("pedidos.post_payment_reversal", body)
        self.assertIn("'fiscal_event'", body)
        self.assertIn("v_pedido.status <> 'fulfilled'", body)
        self.assertIn("pedido must remain fulfilled", body)
        self.assertIn("comissionado.status = 'paga'", body)
        self.assertIn("movimento.tipo_movimento = 'debito_pagamento'", body)
        self.assertIn("pedido has no paid commission", body)
        self.assertIn("for update", body)

    def test_rpc_creates_return_nf_and_pa_append_only_movement(self) -> None:
        body = self._function_body("registrar_com_pedido_estorno_pos_pagamento")

        self.assertIn("insert into public.fat_notas_fiscais", body)
        self.assertIn("nota_devolvida_id", body)
        self.assertIn("'devolucao'", body)
        self.assertIn("insert into public.fat_nota_fiscal_itens", body)
        self.assertIn("nota_item_devolvido_id", body)
        self.assertIn("insert into public.est_movimentos_pa", body)
        self.assertIn("'estorno_saida'", body)
        self.assertIn("'devolucao_pedido'", body)
        self.assertIn("return quantity exceeds original fiscal item quantity", body)
        self.assertIn("public.sync_est_lote_pa_status", body)

    def test_rpc_preserves_order_and_commission_state(self) -> None:
        body = self._function_body("registrar_com_pedido_estorno_pos_pagamento")

        self.assertNotIn("update public.com_pedidos", body)
        self.assertNotIn("update public.com_pedido_comissionados", body)
        self.assertNotIn("insert into public.fin_comissao_movimentos", body)
        self.assertIn("'pedido_status_preserved', true", body)
        self.assertIn("'commission_status_preserved', true", body)

    def test_docs_record_0031_scope(self) -> None:
        commissions_doc = COMMISSIONS_DOC.read_text(encoding="utf-8")
        validation_doc = VALIDATION_DOC.read_text(encoding="utf-8")

        self.assertIn("Estorno pos-pagamento", commissions_doc)
        self.assertIn("pedido permanece `fulfilled`", commissions_doc)
        self.assertIn("sem alterar comissao paga", commissions_doc)
        self.assertIn("0031_pedidos_post_payment_reversal_contract.sql", validation_doc)
        self.assertIn("PG_VALIDATE_0031_WITH_SMOKE_OK", validation_doc)

    def _function_body(self, function_name: str) -> str:
        text = MIGRATION_0031.read_text(encoding="utf-8")
        pattern = re.compile(
            rf"create or replace function public\.{re.escape(function_name)}\b.*?\n\$\$;",
            re.DOTALL | re.IGNORECASE,
        )
        match = pattern.search(text)
        self.assertIsNotNone(match, f"Function {function_name} not found")
        return match.group(0).lower()


if __name__ == "__main__":
    unittest.main()
