from pathlib import Path
import unittest


ROOT = Path(__file__).resolve().parents[1]
MIGRATION = ROOT / "supabase" / "migrations" / "0075_pcp_formula_per_liter_op_scaling.sql"
ACTIONS = ROOT / "apps" / "web" / "app" / "pcp" / "actions.ts"
EDITOR = ROOT / "apps" / "web" / "app" / "pcp" / "production-editors.tsx"
ORDERS = ROOT / "apps" / "web" / "app" / "producao" / "ordens" / "orders-workbench.tsx"
MANUAL = ROOT / "docs" / "manuais" / "producao" / "FORMULAS_GARANTIAS.md"


class PcpFormulaPerLiterContractTests(unittest.TestCase):
    def test_legacy_formulas_are_not_silently_reinterpreted(self) -> None:
        sql = MIGRATION.read_text(encoding="utf-8")
        self.assertIn("legado_nao_comprovado", sql)
        self.assertIn("legacy formula requires a reviewed per-liter version", sql)
        self.assertIn("set_config('elite.formula_basis', '', true)", sql)
        self.assertNotIn("set base_calculo = 'por_litro'", sql.split("create or replace function public.set_pcp_formula_basis_on_insert", 1)[0])

    def test_op_freezes_and_scales_formula_by_planned_liters(self) -> None:
        sql = MIGRATION.read_text(encoding="utf-8")
        self.assertIn("quantidade_formula_por_litro", sql)
        self.assertIn("volume_planejado_l", sql)
        self.assertIn("quantidade_planejada = item.quantidade * p_quantidade_planejada", sql)
        self.assertIn("unidade_formula_id", sql)

    def test_only_governed_per_liter_units_are_accepted(self) -> None:
        sql = MIGRATION.read_text(encoding="utf-8")
        editor = EDITOR.read_text(encoding="utf-8")
        actions = ACTIONS.read_text(encoding="utf-8")
        for code in ("kg_l_produzido", "l_l_produzido", "un_l_produzido"):
            self.assertIn(code, sql)
            self.assertIn(code, editor)
        self.assertIn('name={`component_${index}_unidade_id`}', editor)
        self.assertIn("payload.unidade_id = unidadeId", actions)

    def test_orders_require_liters_and_explain_the_calculation(self) -> None:
        orders = ORDERS.read_text(encoding="utf-8")
        self.assertIn("Volume planejado (L)", orders)
        self.assertIn("multiplica cada quantidade por litro", orders)
        self.assertNotIn("Nao escala a formula", orders)

    def test_manual_teaches_formula_and_op_scaling(self) -> None:
        manual = MANUAL.read_text(encoding="utf-8")
        self.assertIn("base de 1 L", manual)
        self.assertIn("volume planejado", manual)


if __name__ == "__main__":
    unittest.main()
