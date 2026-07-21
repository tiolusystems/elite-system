from pathlib import Path
import unittest


ROOT = Path(__file__).resolve().parents[1]


class ProductionPtBrLabelsContractTest(unittest.TestCase):
    def test_shared_labels_cover_internal_unit_and_status_codes(self) -> None:
        labels = (ROOT / "apps/web/lib/production-labels.ts").read_text(encoding="utf-8")

        for internal_code in ("deg_c", '"kg/l"', "one", "nao_conforme", "sem_referencia"):
            self.assertIn(internal_code, labels)

        self.assertIn('"Matéria-prima"', labels)
        self.assertIn('"Produto acabado"', labels)
        self.assertIn('"Produto intermediário"', labels)

    def test_operational_surfaces_use_shared_labels(self) -> None:
        paths = (
            "apps/web/app/pcp/production-editors.tsx",
            "apps/web/app/producao/formulas/formula-workbench.tsx",
            "apps/web/app/producao/garantias/guarantee-workbench.tsx",
            "apps/web/app/producao/ordens/orders-workbench.tsx",
            "apps/web/app/producao/qualidade/quality-workbench.tsx",
        )

        for relative_path in paths:
            content = (ROOT / relative_path).read_text(encoding="utf-8")
            self.assertIn("@/lib/production-labels", content, relative_path)

        editor = (ROOT / paths[0]).read_text(encoding="utf-8")
        self.assertNotIn('<option value="">ignorar</option>', editor)

        guarantees = (ROOT / paths[2]).read_text(encoding="utf-8")
        self.assertEqual(guarantees.count("{option.label} - {option.detail}"), 1)
        self.assertGreaterEqual(guarantees.count("unitOptionLabel(option)"), 2)


if __name__ == "__main__":
    unittest.main()
