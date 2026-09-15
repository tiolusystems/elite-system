from __future__ import annotations

from pathlib import Path
import unittest


ROOT = Path(__file__).resolve().parents[1]
MIGRATION = ROOT / "supabase" / "migrations" / "0140_harden_order_gate_rpc_wrappers.sql"
SMOKE = ROOT / "tests" / "sql" / "order_gate_rpc_wrapper_security.sql"


class OrderGateRpcWrapperSecurityContractTests(unittest.TestCase):
    def test_migration_hardens_both_authenticated_wrappers(self) -> None:
        text = MIGRATION.read_text(encoding="utf-8")
        for function in (
            "registrar_com_pedido_decisao_desconto_idempotente",
            "decidir_com_pedido_assinatura_idempotente",
        ):
            start = text.index(f"create or replace function public.{function}")
            end = text.index("revoke all on function", start)
            body = text[start:end]
            self.assertIn("security definer", body)
            self.assertIn("set search_path = public", body)
            self.assertIn("require_current_user_permission", body)
            self.assertLess(body.index("require_current_user_permission"), body.index("_impl_0135"))

    def test_helpers_are_private_and_wrappers_remain_application_entrypoints(self) -> None:
        text = MIGRATION.read_text(encoding="utf-8")
        for helper in (
            "registrar_com_pedido_decisao_desconto_idempotente_impl_0135(uuid,bigint,bigint,text,text,text)",
            "decidir_com_pedido_assinatura_idempotente_impl_0135(uuid,bigint,text,text)",
        ):
            self.assertIn(f"revoke all on function public.{helper}", text)
            self.assertIn("from public, anon, authenticated", text)
        self.assertEqual(2, text.count("to authenticated;"))

    def test_signature_wrapper_does_not_read_evidence_before_authorization(self) -> None:
        text = MIGRATION.read_text(encoding="utf-8")
        body = text[text.index("create or replace function public.decidir_com_pedido_assinatura_idempotente"):]
        self.assertNotIn("com_pedido_assinatura_evidencias evidencia", body)
        self.assertIn("select decisao.pedido_id", body)

    def test_smoke_proves_acl_and_ordering_contract(self) -> None:
        text = SMOKE.read_text(encoding="utf-8")
        for helper in (
            "registrar_com_pedido_decisao_desconto_idempotente_impl_0135",
            "decidir_com_pedido_assinatura_idempotente_impl_0135",
        ):
            self.assertIn(f"has_function_privilege('authenticated', v_", text)
            self.assertIn(helper, text)
        self.assertIn("when insufficient_privilege", text)
        self.assertIn("require_current_user_permission", text)


if __name__ == "__main__":
    unittest.main()
