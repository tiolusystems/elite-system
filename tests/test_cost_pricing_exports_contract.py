from pathlib import Path
import unittest

ROOT = Path(__file__).parents[1]


class CostPricingExportsContract(unittest.TestCase):
    def test_governed_approved_snapshot_contract(self):
        sql = (ROOT / "supabase/migrations/0146_expose_approved_prc_snapshot.sql").read_text(encoding="utf-8")
        for value in ("APPROVED", "prc_sha256(v_snapshot)", "intermediarios_json", "revoke all", "precificacao.view"):
            self.assertIn(value, sql)

    def test_exports_are_snapshot_only_and_complete(self):
        source = (ROOT / "apps/web/lib/cost-pricing-export.ts").read_text(encoding="utf-8")
        for value in ("snapshot_json", "c.length!==11", "t.length!==18", "result_sha256", "buildXlsxBytes", "%PDF-1.4"):
            self.assertIn(value, source)
        self.assertNotIn(".from(", source)

    def test_routes_are_protected_attachments(self):
        for path in (ROOT / "apps/web/app/custos-precos/export/[calculoId]/xlsx/route.ts", ROOT / "apps/web/app/custos-precos/export/[calculoId]/pdf/route.ts"):
            source = path.read_text(encoding="utf-8")
            for value in ("getApprovedPricingSnapshot", "Content-Disposition", "private, no-store", "nosniff"):
                self.assertIn(value, source)
            self.assertNotIn(".from(", source)

    def test_ui_exports_only_approved(self):
        source = (ROOT / "apps/web/app/custos-precos/page.tsx").read_text(encoding="utf-8")
        self.assertIn('c.status==="APPROVED"', source)
        self.assertIn("Baixar XLSX", source)
        self.assertIn("Baixar PDF", source)


if __name__ == "__main__":
    unittest.main()
