from __future__ import annotations

from pathlib import Path
import unittest


ROOT = Path(__file__).resolve().parents[1]
CONTRACT = ROOT / "apps" / "web" / "lib" / "historical-workbook-homologation.ts"
WORKSPACE = (
    ROOT
    / "apps"
    / "web"
    / "app"
    / "importacao-historica"
    / "mp"
    / "workbook-homologation.tsx"
)
ANALYSIS = (
    ROOT
    / "apps"
    / "web"
    / "app"
    / "importacao-historica"
    / "mp"
    / "workbook-analysis.tsx"
)
DOC = ROOT / "docs" / "importacao-historica" / "04_HOMOLOGACAO_FUNCIONAL_FONTES.md"
STATE = ROOT / "docs" / "01_ESTADO_ATUAL.md"
STYLES = ROOT / "apps" / "web" / "app" / "globals.css"


class HistoricalWorkbookHomologationContractTests(unittest.TestCase):
    @classmethod
    def setUpClass(cls) -> None:
        cls.contract = CONTRACT.read_text(encoding="utf-8")
        cls.workspace = WORKSPACE.read_text(encoding="utf-8")
        cls.analysis = ANALYSIS.read_text(encoding="utf-8")
        cls.doc = DOC.read_text(encoding="utf-8")
        cls.state = STATE.read_text(encoding="utf-8")
        cls.styles = STYLES.read_text(encoding="utf-8")

    def test_exact_final_decision_catalog_is_closed(self) -> None:
        expected = (
            "importar_integralmente",
            "importar_apenas_metadados",
            "usar_somente_reconciliacao",
            "nao_importar",
            "adiar",
            "revisar",
        )
        for decision in expected:
            self.assertIn(f'"{decision}"', self.contract)
        catalog = self.contract.split(
            "export const WORKBOOK_HOMOLOGATION_DECISIONS = [", 1
        )[1].split("] as const", 1)[0]
        self.assertEqual(catalog.count('"'), len(expected) * 2)

    def test_all_structured_tables_are_flattened_without_inferred_decision(self) -> None:
        self.assertIn("EXPECTED_HISTORICAL_WORKBOOK_TABLES = 269", self.contract)
        self.assertIn("analysis.sheets.flatMap", self.contract)
        self.assertIn("sheet.tables.map", self.contract)
        self.assertIn("decision: null", self.contract)
        self.assertNotIn("decision: classification", self.contract)
        self.assertIn("rows.length === EXPECTED_HISTORICAL_WORKBOOK_TABLES", self.contract)

    def test_final_export_is_gated_and_only_integral_import_reaches_i2(self) -> None:
        self.assertIn("rows.every((row) => row.decision !== null)", self.contract)
        self.assertIn('status === "homologated" && !isWorkbookHomologationReady', self.contract)
        self.assertIn('row.decision === "importar_integralmente"', self.contract)
        self.assertIn("disabled={!finalReady}", self.workspace)
        self.assertIn("I2 permanece bloqueada", self.workspace)
        self.assertIn("Adiar ou revisar bloqueia apenas a própria tabela", self.workspace)

    def test_required_technical_and_functional_fields_are_visible_and_exported(self) -> None:
        for expected in (
            "Fonte no workbook",
            "Principais colunas",
            "Classificação e destino técnicos",
            "Indícios e riscos",
            "Justificativa técnica",
            "Decisão final de Luciano",
            "Observação de Luciano",
            "quantidade_linhas",
            "presenca_formulas",
            "indicio_relatorio",
            "indicio_calculo_derivado",
            "risco_duplicidade",
            "decisao_final_luciano",
            "observacao_luciano",
        ):
            self.assertIn(expected, self.workspace + self.contract)

    def test_revision_artifact_is_bound_to_workbook_and_table_schema(self) -> None:
        for expected in (
            "revisionId",
            "parentRevisionId",
            "revisionTrail",
            "revisionHistory",
            "workbook.sha256",
            "sourceTableId",
            "schemaFingerprint",
            "profileMatchesReference",
        ):
            self.assertIn(expected, self.contract)
        self.assertIn("A revisao pertence a outro workbook", self.contract)
        self.assertIn("A estrutura da tabela", self.contract)
        self.assertIn("A classificacao tecnica da tabela", self.contract)

    def test_workspace_has_review_filters_lists_and_round_trip_exports(self) -> None:
        for expected in (
            "Aprovadas para I2",
            "Excluídas da carga",
            "Pendentes",
            "Exportar matriz CSV",
            "Exportar revisão JSON",
            "Importar revisão JSON",
            "Exportar homologação final",
            "Aplicar aos resultados visíveis",
            "Rascunho salvo somente neste navegador",
        ):
            self.assertIn(expected, self.workspace)
        self.assertIn("<WorkbookHomologationWorkspace", self.analysis)

    def test_decision_matrix_reflows_without_horizontal_scrolling(self) -> None:
        self.assertIn('data-label="Decis\u00e3o funcional"', self.workspace)
        self.assertIn("overflow-x: hidden", self.styles)
        self.assertIn('"source technical decision"', self.styles)
        self.assertIn('"source decision"', self.styles)
        self.assertNotIn("min-width: 1580px", self.styles)

    def test_csv_has_formula_injection_guard_and_all_rows(self) -> None:
        self.assertIn("rows.map((row)", self.contract)
        self.assertIn("text/csv;charset=utf-8", self.workspace)
        self.assertIn("/^[=+\\-@]/", self.contract)
        self.assertIn("URL.revokeObjectURL", self.workspace)

    def test_homologation_is_client_only_and_has_no_operational_write_path(self) -> None:
        combined = self.contract + self.workspace
        for forbidden in (
            '"use server"',
            ".rpc(",
            "auditedRpc",
            "createClient(",
            "fetch(",
            ".insert(",
            ".update(",
            ".delete(",
            "service_role",
        ):
            self.assertNotIn(forbidden, combined)
        self.assertIn("window.localStorage", self.workspace)

    def test_documentation_keeps_i2_blocked_until_luciano_homologates(self) -> None:
        self.assertIn("269", self.doc)
        self.assertIn("nenhuma decisao e inferida", self.doc.casefold())
        self.assertIn("nao escreve no", self.doc.casefold())
        self.assertIn("postgresql", self.doc.casefold())
        self.assertIn("homologacao funcional", self.state.casefold())
        self.assertIn("i2", self.state.casefold())


if __name__ == "__main__":
    unittest.main()
