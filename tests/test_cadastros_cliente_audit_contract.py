from __future__ import annotations

import unittest
from pathlib import Path


REPO_ROOT = Path(__file__).resolve().parents[1]
MIGRATION_0015 = REPO_ROOT / "supabase" / "migrations" / "0015_cadastros_cliente_update_soft_delete.sql"
CADASTROS_ACTIONS = REPO_ROOT / "apps" / "web" / "app" / "cadastros" / "actions.ts"


class CadastrosClienteAuditContractTests(unittest.TestCase):
    def test_cliente_soft_delete_does_not_hard_delete_master_data(self) -> None:
        text = MIGRATION_0015.read_text(encoding="utf-8").lower()

        self.assertIn("create or replace function public.deactivate_cad_cliente", text)
        self.assertIn("set status = 'inactive'", text)
        self.assertNotIn("delete from public.cad_clientes", text)

    def test_cliente_update_and_deactivate_log_before_after(self) -> None:
        text = MIGRATION_0015.read_text(encoding="utf-8")

        for function_name in ("update_cad_cliente", "deactivate_cad_cliente"):
            self.assertIn(f"jsonb_build_object('source', '{function_name}'", text)

        self.assertIn("'cadastros.cliente_updated'", text)
        self.assertIn("'cadastros.cliente_deactivated'", text)
        self.assertGreaterEqual(text.count("v_before"), 4)
        self.assertGreaterEqual(text.count("v_after"), 4)
        self.assertIn("'cadastros.clientes.update.own'", text)
        self.assertIn("'cadastros.clientes.update.any'", text)
        self.assertIn("'cadastros.clientes.deactivate.own'", text)
        self.assertIn("'cadastros.clientes.deactivate.any'", text)

    def test_web_actions_expose_cliente_update_and_deactivate_via_audited_rpc(self) -> None:
        text = CADASTROS_ACTIONS.read_text(encoding="utf-8")

        self.assertIn("export async function updateClienteAction", text)
        self.assertIn("export async function deactivateClienteAction", text)
        self.assertIn('auditedRpc(supabase, "update_cad_cliente"', text)
        self.assertIn('auditedRpc(supabase, "deactivate_cad_cliente"', text)


if __name__ == "__main__":
    unittest.main()
