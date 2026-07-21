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


if __name__ == "__main__":
    unittest.main()
