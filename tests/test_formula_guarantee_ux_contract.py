from pathlib import Path
import unittest


ROOT = Path(__file__).resolve().parents[1]
PCP = ROOT / "apps" / "web" / "lib" / "pcp.ts"
EDITOR = ROOT / "apps" / "web" / "app" / "producao" / "formulas" / "formula-creation-form.tsx"
GUARANTEES = ROOT / "apps" / "web" / "app" / "producao" / "garantias" / "guarantee-workbench.tsx"
MANUAL = ROOT / "docs" / "manuais" / "producao" / "FORMULAS_GARANTIAS.md"


class FormulaGuaranteeUxContractTests(unittest.TestCase):
    def test_dashboard_reads_governed_nutrients_and_units(self) -> None:
        text = PCP.read_text(encoding="utf-8")
        self.assertIn('.from("cad_nutrientes")', text)
        self.assertIn('.from("cad_unidades_medida")', text)
        self.assertIn('nutrientes: nutrientRows.map', text)
        self.assertIn('unidades: unitRows.map', text)

    def test_guarantees_do_not_accept_free_text_catalog_values(self) -> None:
        text = GUARANTEES.read_text(encoding="utf-8")
        self.assertNotIn('<input name="nutriente"', text)
        self.assertNotIn('<input name="unidade"', text)
        self.assertIn('dashboard.lookups.nutrientes.map', text)
        self.assertIn('dashboard.lookups.unidades.map', text)

    def test_op_guarantee_results_are_visible_without_inventing_missing_values(self) -> None:
        text = GUARANTEES.read_text(encoding="utf-8")
        self.assertIn("Resultados calculados por OP", text)
        self.assertIn("dashboard.opGuaranteeResults.map", text)
        self.assertIn('result.valorCalculado === null ? "Não calculado"', text)
        self.assertIn('sem_dados_lote: "Faltam dados do lote"', text)
        self.assertIn('base_incompleta: "Base física incompleta"', text)
        self.assertIn('sem_referencia_mapa: "Sem referência MAPA"', text)

    def test_production_and_mapa_recipes_are_visibly_separated(self) -> None:
        text = EDITOR.read_text(encoding="utf-8")
        self.assertIn('Produção operacional', text)
        self.assertIn('Documentação MAPA', text)
        self.assertIn('nunca movimentam estoque', text)
        self.assertIn('Composição documental para o MAPA', text)

    def test_formula_component_unit_comes_from_catalog(self) -> None:
        text = (ROOT / "apps" / "web" / "app" / "pcp" / "production-editors.tsx").read_text(encoding="utf-8")
        self.assertIn('targets.unidades.map', text)
        self.assertNotIn('placeholder="KG, L, UN"', text)

    def test_formula_version_can_be_prefilled_without_editing_history(self) -> None:
        workbench = (ROOT / "apps/web/app/producao/formulas/formula-workbench.tsx").read_text(encoding="utf-8")
        form = EDITOR.read_text(encoding="utf-8")
        editors = (ROOT / "apps/web/app/pcp/production-editors.tsx").read_text(encoding="utf-8")
        manual = MANUAL.read_text(encoding="utf-8")
        self.assertIn("Criar nova versão a partir desta", workbench)
        self.assertIn("initialFormula", form)
        self.assertIn("initialComponents", editors)
        self.assertIn("A versão anterior não é editada nem apagada", manual)

    def test_manual_explains_stock_boundary_and_lot_calculation(self) -> None:
        text = MANUAL.read_text(encoding="utf-8")
        self.assertIn("a baixa ocorre somente na finalização da OP", text)
        self.assertIn("vários lotes", text)
        self.assertIn("proporcionalmente", text)
        self.assertIn("A fórmula MAPA não é cópia", text)
        self.assertIn("emissão da OP MAPA gera simultaneamente uma Ordem de Envase", text)
        self.assertIn("Ordem de Envase gera um único lote PA", text)
        self.assertIn("assinaturas físicas dos operadores", text)
        self.assertIn("filtro gerencial por família", text)
        self.assertIn("controle global de sessões", text)


if __name__ == "__main__":
    unittest.main()
