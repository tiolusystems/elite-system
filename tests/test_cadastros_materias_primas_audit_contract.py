from __future__ import annotations

import unittest
from pathlib import Path


REPO_ROOT = Path(__file__).resolve().parents[1]
MIGRATION_0017 = REPO_ROOT / "supabase" / "migrations" / "0017_cadastros_materias_primas_axes.sql"
CADASTROS_ACTIONS = REPO_ROOT / "apps" / "web" / "app" / "cadastros" / "actions.ts"


class CadastrosMateriasPrimasAuditContractTests(unittest.TestCase):
    def test_mp_has_axis_specific_rpcs_not_generic_update(self) -> None:
        text = MIGRATION_0017.read_text(encoding="utf-8")

        self.assertIn("update_cad_materia_prima_identity", text)
        self.assertIn("update_cad_materia_prima_sku", text)
        self.assertIn("update_cad_materia_prima_technical", text)
        self.assertIn("update_cad_materia_prima_stock_policy", text)
        self.assertIn("update_cad_materia_prima_regulatory", text)
        self.assertNotIn("create or replace function public.update_cad_materia_prima(", text)

    def test_mp_soft_delete_does_not_hard_delete_master_data(self) -> None:
        text = MIGRATION_0017.read_text(encoding="utf-8").lower()

        self.assertIn("create or replace function public.deactivate_cad_materia_prima", text)
        self.assertIn("set status = 'inactive'", text)
        self.assertNotIn("delete from public.cad_materias_primas", text)

    def test_mp_domain_validations_live_in_sql(self) -> None:
        text = MIGRATION_0017.read_text(encoding="utf-8")

        self.assertIn("ncm must have exactly 8 digits", text)
        self.assertIn("sku_corrigido cannot contain whitespace", text)
        self.assertIn("densidade must be greater than zero", text)
        self.assertIn("estoque_minimo must be greater than or equal to zero", text)
        self.assertIn("'cadastros.materias_primas.update.regulatory'", text)
        self.assertIn("'cadastros.materias_primas.update.technical'", text)

    def test_web_actions_expose_mp_axes_via_audited_rpc(self) -> None:
        text = CADASTROS_ACTIONS.read_text(encoding="utf-8")

        for function_name in (
            "update_cad_materia_prima_identity",
            "update_cad_materia_prima_sku",
            "update_cad_materia_prima_technical_governada",
            "update_cad_materia_prima_stock_policy",
            "update_cad_materia_prima_regulatory",
            "deactivate_cad_materia_prima",
        ):
            self.assertIn(f'auditedRpc(supabase, "{function_name}"', text)


if __name__ == "__main__":
    unittest.main()
