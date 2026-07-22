import pathlib
import unittest


ROOT = pathlib.Path(__file__).resolve().parents[1]
REPORTS_PAGE = ROOT / "apps" / "web" / "app" / "relatorios" / "page.tsx"


class ReportsFamilyFilterContractTests(unittest.TestCase):
    def test_reports_offer_explicit_pi_and_pa_filters(self) -> None:
        source = REPORTS_PAGE.read_text(encoding="utf-8")

        self.assertIn('["TODOS", "PI", "PA", "MP"]', source)
        self.assertIn("filterByFamily(dashboard.validityRows, family)", source)
        self.assertIn("filterByFamily(dashboard.reprocessamentoRows, family)", source)
        self.assertIn('aria-label="Filtrar relatórios por família de estoque"', source)
        self.assertIn('`/relatorios?familia=${option}`', source)

    def test_filter_is_applied_to_metrics_and_rows(self) -> None:
        source = REPORTS_PAGE.read_text(encoding="utf-8")

        self.assertIn("validityRows.filter", source)
        self.assertIn("reprocessamentoRows.filter", source)
        self.assertIn("validityRows.slice", source)
        self.assertIn("reprocessamentoRows.slice", source)

    def test_date_query_preserves_family_and_hides_unrelated_pa_position(self) -> None:
        source = REPORTS_PAGE.read_text(encoding="utf-8")

        self.assertIn('family !== "TODOS" ? <input type="hidden" name="familia"', source)
        self.assertIn('family === "TODOS" || family === "PA"', source)
        self.assertIn('family === "PI"', source)
        self.assertIn("A posição retroativa por data ainda não faz parte do contrato histórico de PI.", source)

    def test_internal_statuses_are_translated(self) -> None:
        source = REPORTS_PAGE.read_text(encoding="utf-8")

        self.assertIn("catalogStatusLabel(item.status)", source)
        self.assertIn("priorityLabel(row.prioridadeReprocessamento)", source)
        self.assertIn("stockStatusLabel(row.status)", source)


if __name__ == "__main__":
    unittest.main()
