from __future__ import annotations

from pathlib import Path
import unittest


ROOT = Path(__file__).resolve().parents[1]
MIGRATION = ROOT / "supabase" / "migrations" / "0058_restore_production_catalog_view_access.sql"
SMOKE = ROOT / "tests" / "sql" / "production_catalog_view_access.sql"
CI = ROOT / ".github" / "workflows" / "ci.yml"
PCP = ROOT / "apps" / "web" / "lib" / "pcp.ts"
SERVER_CLIENT = ROOT / "apps" / "web" / "lib" / "supabase" / "server.ts"


class ProductionCatalogViewAccessContractTests(unittest.TestCase):
    def test_migration_restores_select_only_for_authenticated(self) -> None:
        sql = MIGRATION.read_text(encoding="utf-8").lower()

        for view in (
            "cad_garantias_produto_mapa_atuais",
            "cad_garantias_lote_mp_atuais",
        ):
            self.assertIn(view, sql)

        self.assertIn("security_invoker=true", sql)
        self.assertIn("from public, anon, authenticated", sql)
        self.assertIn("to authenticated", sql)
        self.assertNotIn("disable row level security", sql)
        self.assertNotIn("grant all", sql)
        self.assertNotIn("to anon", sql)
        self.assertNotIn("to public", sql)
        self.assertNotIn("service_role", sql)

    def test_smoke_proves_rls_and_authenticated_read_contract(self) -> None:
        sql = SMOKE.read_text(encoding="utf-8")

        self.assertIn("has_table_privilege('authenticated'", sql)
        self.assertIn("has_table_privilege('anon'", sql)
        self.assertIn("has_table_privilege('public'", sql)
        self.assertIn("rowsecurity", sql)
        self.assertIn("current_actor_id()", sql)
        self.assertIn("set local role authenticated", sql)
        self.assertIn("PG_PRODUCTION_CATALOG_VIEW_ACCESS_OK", sql)

    def test_dashboard_keeps_session_client_and_both_protected_views(self) -> None:
        loader = PCP.read_text(encoding="utf-8")
        server_client = SERVER_CLIENT.read_text(encoding="utf-8")

        self.assertIn('.from("cad_garantias_produto_mapa_atuais")', loader)
        self.assertIn('.from("cad_garantias_lote_mp_atuais")', loader)
        self.assertIn("NEXT_PUBLIC_SUPABASE_PUBLISHABLE_KEY", server_client)
        self.assertNotIn("SUPABASE_SERVICE_ROLE_KEY", server_client)

    def test_ci_runs_production_catalog_access_smoke(self) -> None:
        workflow = CI.read_text(encoding="utf-8")
        self.assertIn("tests/sql/production_catalog_view_access.sql", workflow)


if __name__ == "__main__":
    unittest.main()
