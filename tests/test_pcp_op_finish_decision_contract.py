from __future__ import annotations

import unittest
from pathlib import Path


REPO_ROOT = Path(__file__).resolve().parents[1]
DECISION_DOC = REPO_ROOT / "docs" / "decisao_finalizacao_pcp_op.md"
PCP_SCOPE_DOC = REPO_ROOT / "docs" / "escopo_pcp_op.md"
MIGRATION_0009 = REPO_ROOT / "supabase" / "migrations" / "0009_pcp_op_foundation.sql"


class PcpOpFinishDecisionContractTests(unittest.TestCase):
    def test_decision_doc_fixes_transaction_and_lock_order(self) -> None:
        text = DECISION_DOC.read_text(encoding="utf-8")

        self.assertIn("Transacao unica", text)
        self.assertIn("Nao deve existir finalizacao parcial persistida", text)
        self.assertIn("validar todos os outputs PA/PI antes de qualquer movimento de estoque", text)
        self.assertIn("op_componente_id, id", text)
        self.assertIn("MP -> PA -> PI", text)

    def test_decision_doc_fixes_cq_rejection_behavior(self) -> None:
        text = DECISION_DOC.read_text(encoding="utf-8")

        self.assertIn("cq_status = reprovado", text)
        self.assertIn("gera lote `bloqueado`", text)
        self.assertIn("Reprovar CQ nao deve apagar o fato fisico da producao", text)
        self.assertIn("OP `experimental` ou `desenvolvimento` gera lote `bloqueado`", text)

    def test_decision_doc_fixes_retry_behavior_and_correlation_id(self) -> None:
        text = DECISION_DOC.read_text(encoding="utf-8")

        self.assertIn("segunda chamada para a mesma OP deve falhar", text)
        self.assertIn("nenhum movimento de estoque deve ser duplicado", text)
        self.assertIn("pcp_op:' || p_op_id || ':finish", text)
        self.assertIn("duas tentativas de finalizar a mesma OP nao duplicam estoque", text)

    def test_scope_links_to_finish_decision(self) -> None:
        text = PCP_SCOPE_DOC.read_text(encoding="utf-8")

        self.assertIn("docs/decisao_finalizacao_pcp_op.md", text)
        self.assertIn("CQ reprovado ou bloqueado gera lote bloqueado", text)
        self.assertIn("segunda finalizacao da mesma OP deve falhar", text)
        self.assertIn("correlation_id = 'pcp_op:' || p_op_id || ':finish'", text)

    def test_current_foundation_already_has_core_safety_checks(self) -> None:
        text = MIGRATION_0009.read_text(encoding="utf-8")

        self.assertIn("create or replace function public.finalizar_pcp_op", text)
        self.assertIn("from public.pcp_ordens_producao", text)
        self.assertIn("for update", text)
        self.assertIn("if v_op.status not in ('planned', 'in_process')", text)
        self.assertIn("raise exception 'OP status does not allow finish'", text)
        self.assertIn("if exists (select 1 from public.pcp_op_cq_resultados where op_id = p_op_id)", text)
        self.assertIn("raise exception 'OP already has CQ result'", text)
        self.assertIn("when v_op.tipo_op in ('experimental', 'desenvolvimento') or p_cq_status <> 'aprovado' then 'bloqueado'", text)


if __name__ == "__main__":
    unittest.main()
