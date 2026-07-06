from __future__ import annotations

import re
import unittest
from pathlib import Path


REPO_ROOT = Path(__file__).resolve().parents[1]
MIGRATION_0033 = REPO_ROOT / "supabase" / "migrations" / "0033_metas_coupling_legacy_skip.sql"
COMMISSIONS_DOC = REPO_ROOT / "docs" / "escopo_comissoes_recebimentos_credito.md"
RECIPE_DOC = REPO_ROOT / "docs" / "receita_rls_rpc_auditada.md"
SECURITY_MATRIX_DOC = REPO_ROOT / "docs" / "matriz_seguranca_alcadas.md"
VALIDATION_DOC = REPO_ROOT / "docs" / "validacao_metas_coupling_legacy_skip.md"


class MetasCouplingLegacySkipContractTests(unittest.TestCase):
    def test_docs_make_cancel_quality_rule_explicit(self) -> None:
        docs = "\n".join(
            (
                COMMISSIONS_DOC.read_text(encoding="utf-8"),
                RECIPE_DOC.read_text(encoding="utf-8"),
                SECURITY_MATRIX_DOC.read_text(encoding="utf-8"),
            )
        )

        self.assertIn("cancelamento sempre abate meta, sem excecao de qualidade", docs)
        self.assertIn("A excecao de qualidade existe apenas em devolucao", docs)
        self.assertIn("pedidos.cancel` + `metas.cancellations.register", docs)
        self.assertIn("pedidos.post_payment_reversal` + `metas.returns.register", docs)

    def test_meta_return_skips_legacy_items_without_aborting(self) -> None:
        body = self._function_body("registrar_com_meta_devolucao_nf")

        self.assertIn("v_itens_sem_venda_aberta jsonb := '[]'::jsonb", body)
        self.assertIn("'motivo', 'sem_venda_aberta_no_ledger'", body)
        self.assertIn("itens_sem_venda_aberta_count", body)
        self.assertNotIn("raise exception 'meta sale event not found for returned item'", body)
        self.assertIn("if v_count = 0 and jsonb_array_length(v_itens_sem_venda_aberta) = 0 then", body)
        self.assertIn("raise exception 'no target return movements were generated'", body)

    def test_cancelar_pedido_calls_meta_conditionally_after_status_update(self) -> None:
        body = self._function_body("cancelar_com_pedido")

        update_pos = body.index("update public.com_pedidos")
        call_pos = body.index("v_meta_movimentos_count := public.registrar_com_meta_cancelamento_pedido")

        self.assertGreater(call_pos, update_pos)
        self.assertIn("movimento.tipo_movimento = 'venda_aberta'", body)
        self.assertIn("'cancelamento_pedido'", body)
        self.assertIn("trim(p_motivo)", body)
        self.assertIn("v_meta_skip_reason := 'sem_venda_aberta_no_ledger'", body)
        self.assertIn("'meta_cancel_applied', v_meta_cancel_applied", body)
        self.assertIn("'correlation_id', v_target_correlation_id", body)

    def test_post_payment_reversal_calls_meta_return_after_fiscal_event(self) -> None:
        body = self._function_body("registrar_com_pedido_estorno_pos_pagamento")

        event_pos = body.index("insert into public.fat_nota_fiscal_eventos")
        call_pos = body.index("v_meta_return_movimentos_count := public.registrar_com_meta_devolucao_nf(v_nota_devolucao_id)")

        self.assertGreater(call_pos, event_pos)
        self.assertIn("v_target_correlation_id := concat('nota_fiscal:', v_nota_devolucao_id::text, ':target_return')", body)
        self.assertIn("'meta_return_movimentos_count', v_meta_return_movimentos_count", body)
        self.assertIn("'pedido_correlation_id', v_pedido_correlation_id", body)
        self.assertNotIn("registrar_com_meta_devolucao_nf(v_nota_devolucao_id, ", body)

    def test_validation_doc_records_0033_scope(self) -> None:
        text = VALIDATION_DOC.read_text(encoding="utf-8")

        self.assertIn("0033_metas_coupling_legacy_skip.sql", text)
        self.assertIn("PG_VALIDATE_0033_WITH_SMOKE_OK", text)
        self.assertIn("pedido legado sem `venda_aberta`", text)
        self.assertIn("itens_sem_venda_aberta", text)

    def _function_body(self, function_name: str) -> str:
        text = MIGRATION_0033.read_text(encoding="utf-8")
        pattern = re.compile(
            rf"create or replace function public\.{re.escape(function_name)}\b.*?\n\$\$;",
            re.DOTALL | re.IGNORECASE,
        )
        match = pattern.search(text)
        self.assertIsNotNone(match, f"Function {function_name} not found")
        return match.group(0).lower()


if __name__ == "__main__":
    unittest.main()
