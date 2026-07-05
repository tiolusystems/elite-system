from __future__ import annotations

import unittest
from pathlib import Path


REPO_ROOT = Path(__file__).resolve().parents[1]
MIGRATION_0024 = REPO_ROOT / "supabase" / "migrations" / "0024_pcp_finish_audited_contract.sql"
RPC_HELPER = REPO_ROOT / "apps" / "web" / "lib" / "supabase" / "rpc.ts"
PCP_ACTIONS = REPO_ROOT / "apps" / "web" / "app" / "pcp" / "actions.ts"


class PcpFinishAuditedContractTests(unittest.TestCase):
    def test_0024_declares_granular_stock_and_release_action_keys(self) -> None:
        text = MIGRATION_0024.read_text(encoding="utf-8")

        for action_key in (
            "estoque.mp.consume.op",
            "estoque.pa.consume.op",
            "estoque.pi.consume.op",
            "estoque.pa.entry.op",
            "estoque.pi.entry.op",
            "pcp.blocked_lot.release",
        ):
            self.assertIn(action_key, text)

        self.assertIn("pcp.experimental.release", text)

    def test_0024_finalizar_pcp_op_uses_composed_audit_contract(self) -> None:
        text = MIGRATION_0024.read_text(encoding="utf-8")

        self.assertIn("create or replace function public.finalizar_pcp_op", text)
        self.assertIn("v_correlation_id := concat('pcp_op:', p_op_id::text, ':finish')", text)
        self.assertIn("public.begin_audited_rpc(", text)
        self.assertIn("'pcp.op.finish'", text)
        self.assertIn("'pcp.cq.record'", text)
        self.assertIn("'estoque.mp.consume.op'", text)
        self.assertIn("'estoque.pa.entry.op'", text)
        self.assertIn("order by reserva.op_componente_id, reserva.id", text)
        self.assertIn("for update", text)
        self.assertIn("public.pcp_op_finish_audit_snapshot(p_op_id)", text)
        self.assertIn("perform public.log_audited_rpc_change(", text)
        self.assertIn("'pcp.op_finished'", text)
        self.assertNotIn("perform public.log_action(", text)

    def test_0024_finalizar_pcp_op_preserves_cq_blocking_and_retry_guards(self) -> None:
        text = MIGRATION_0024.read_text(encoding="utf-8")

        self.assertIn("if v_op.status not in ('planned', 'in_process')", text)
        self.assertIn("raise exception 'OP status does not allow finish'", text)
        self.assertIn("if exists (select 1 from public.pcp_op_cq_resultados where op_id = p_op_id)", text)
        self.assertIn("raise exception 'OP already has CQ result'", text)
        self.assertIn("when v_op.tipo_op in ('experimental', 'desenvolvimento') or p_cq_status <> 'aprovado' then 'bloqueado'", text)

    def test_0024_release_blocked_lot_uses_specific_permission_and_updates_generated_product(self) -> None:
        text = MIGRATION_0024.read_text(encoding="utf-8")

        self.assertIn("create or replace function public.liberar_pcp_lote_bloqueado", text)
        self.assertIn("'pcp.blocked_lot.release'", text)
        self.assertIn("update public.pcp_op_produtos_gerados", text)
        self.assertIn("set status_lote = v_status_after", text)
        self.assertIn("Libera lote PA/PI bloqueado gerado por OP", text)
        self.assertIn("grant execute on function public.liberar_pcp_lote_bloqueado", text)

    def test_0024_adds_failed_rpc_log_helper_for_business_rejections(self) -> None:
        text = MIGRATION_0024.read_text(encoding="utf-8")

        self.assertIn("create or replace function public.log_rpc_failed", text)
        self.assertIn("'failed'", text)
        self.assertIn("'decision', 'failed'", text)
        self.assertIn("grant execute on function public.log_rpc_failed", text)

    def test_web_rpc_helper_logs_failed_non_permission_errors_when_contract_metadata_exists(self) -> None:
        text = RPC_HELPER.read_text(encoding="utf-8")

        self.assertIn("logRpcFailedIfPossible", text)
        self.assertIn("log_rpc_failed", text)
        self.assertIn("permissionDeniedLogged", text)
        self.assertIn("failure_action", text)

    def test_pcp_finish_action_passes_failure_contract_metadata(self) -> None:
        text = PCP_ACTIONS.read_text(encoding="utf-8")

        self.assertIn("const correlationId = `pcp_op:${opId}:finish`", text)
        self.assertIn('action_key: "pcp.op.finish"', text)
        self.assertIn('failure_action: "pcp.op_finish_failed"', text)
        self.assertIn('origin: "apps/web/pcp.finish"', text)


if __name__ == "__main__":
    unittest.main()
