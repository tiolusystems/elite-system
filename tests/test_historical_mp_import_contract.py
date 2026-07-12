from __future__ import annotations

from pathlib import Path
import re
import unittest


ROOT = Path(__file__).resolve().parents[1]
MIGRATION = ROOT / "supabase" / "migrations" / "0045_historical_mp_import_foundation.sql"
DECISION = ROOT / "docs" / "decisao_migracao_historica_materias_primas.md"
ANALYZER = ROOT / "elite_system" / "services" / "historical_mp.py"
CLI = ROOT / "elite_system" / "cli.py"
SMOKE = ROOT / "tests" / "sql" / "historical_mp_import_foundation.sql"
CI = ROOT / ".github" / "workflows" / "ci.yml"
WEB_DATA = ROOT / "apps" / "web" / "lib" / "historical-mp.ts"
WEB_PAGE = ROOT / "apps" / "web" / "app" / "importacao-historica" / "mp" / "page.tsx"
HOME_PAGE = ROOT / "apps" / "web" / "app" / "page.tsx"
SYSTEM_MAP = ROOT / "apps" / "web" / "lib" / "system-map.ts"


class HistoricalMpImportContractTests(unittest.TestCase):
    def test_foundation_has_staging_mapping_alias_and_value_facts(self) -> None:
        sql = MIGRATION.read_text(encoding="utf-8").lower()

        for table in (
            "migration_mp_staging_items",
            "migration_mp_mapping_events",
            "cad_materia_prima_aliases",
            "est_movimentos_mp_valores",
        ):
            with self.subTest(table=table):
                self.assertIn(f"create table if not exists public.{table}", sql)

        for view in (
            "migration_mp_mapping_dashboard",
            "migration_mp_batch_summary",
            "est_mp_historico_precos",
        ):
            with self.subTest(view=view):
                self.assertIn(f"create or replace view public.{view}", sql)
                self.assertIn("security_invoker = true", sql)

    def test_history_is_append_only_and_source_lineage_is_mandatory(self) -> None:
        sql = MIGRATION.read_text(encoding="utf-8").lower()

        self.assertIn("prevent_historical_mp_fact_changes", sql)
        self.assertIn("before update or delete", sql)
        self.assertIn("before truncate", sql)
        self.assertIn("excel_legado requires source_batch_id and source_row_id", sql)
        self.assertIn("source_row_id does not belong to source_batch_id workbook", sql)
        self.assertIn("source lineage is reserved for origem_dados excel_legado", sql)
        self.assertIn("enforce_historical_mp_batch_row_consistency", sql)
        self.assertIn("source_row_id does not belong to historical batch workbook", sql)

    def test_acquisition_cost_keeps_difal_and_other_components_separate(self) -> None:
        sql = MIGRATION.read_text(encoding="utf-8").lower()

        self.assertIn("valor_materia_prima + frete + difal_icms + outras_despesas", sql)
        self.assertIn("custo_aquisicao_total numeric generated always as", sql)
        self.assertIn("custo_unitario_base numeric generated always as", sql)
        self.assertIn("uf_emitente is distinct from 'sp' or difal_icms = 0", sql)
        self.assertIn("difal_status in ('informed', 'not_applicable', 'pending_review')", sql)
        self.assertIn("uf, isoladamente, nao autoriza", DECISION.read_text(encoding="utf-8").lower())

    def test_writes_use_audited_rpcs_and_union_of_domain_permissions(self) -> None:
        sql = MIGRATION.read_text(encoding="utf-8").lower()

        for function in (
            "stage_migration_mp_items",
            "approve_migration_mp_mapping",
            "register_migration_mp_acquisition_value",
        ):
            start = sql.index(f"create or replace function public.{function}")
            end = sql.index("$$;", start)
            body = sql[start:end]
            self.assertIn("public.begin_audited_rpc(", body)
            self.assertIn("public.log_audited_rpc_change(", body)
            self.assertIn("security definer", body)

        self.assertIn("'migration.mp.map'", sql)
        self.assertIn("'cadastros.materias_primas.update.identity'", sql)
        self.assertIn("'migration.mp.import'", sql)
        self.assertIn("'estoque.mp.acquisition_value.register'", sql)
        self.assertIn("historical acquisition source must be an entradas_mp row", sql)

    def test_authenticated_roles_have_read_only_table_grants(self) -> None:
        sql = MIGRATION.read_text(encoding="utf-8").lower()
        for table in (
            "migration_mp_staging_items",
            "migration_mp_mapping_events",
            "cad_materia_prima_aliases",
            "est_movimentos_mp_valores",
        ):
            with self.subTest(table=table):
                self.assertIn(f"revoke all on public.{table} from anon, authenticated", sql)
                self.assertIn(f"grant select on public.{table} to authenticated", sql)
                self.assertNotRegex(sql, rf"grant\s+(?:insert|update|delete|all).*{table}.*authenticated")

        self.assertGreaterEqual(sql.count("using (public.can_current_user('migration.mp.view'))"), 4)

    def test_dry_run_analyzer_does_not_write_or_open_excel(self) -> None:
        analyzer = ANALYZER.read_text(encoding="utf-8")
        cli = CLI.read_text(encoding="utf-8")

        self.assertIn("PRAGMA query_only = ON", analyzer)
        self.assertIn("mode=ro", analyzer)
        self.assertNotRegex(analyzer.lower(), r"\b(insert|update|delete|replace)\s+(?:into|from)?\s*[a-z_]")
        self.assertNotIn("openpyxl", analyzer.lower())
        self.assertIn('"analyze-mp-history"', cli)
        self.assertIn("analyze_historical_mp", cli)

    def test_no_operational_data_is_embedded(self) -> None:
        sql = MIGRATION.read_text(encoding="utf-8").lower()
        forbidden = (".xlsx", ".xlsm", "tio lu system", "copy public.", "lo_import(")
        for value in forbidden:
            with self.subTest(value=value):
                self.assertNotIn(value, sql)

    def test_database_smoke_is_part_of_ci(self) -> None:
        smoke = SMOKE.read_text(encoding="utf-8")
        ci = CI.read_text(encoding="utf-8")

        self.assertIn("PG_HISTORICAL_MP_IMPORT_FOUNDATION_OK", smoke)
        self.assertIn("rollback;", smoke.lower())
        self.assertIn("historical_mp_import_foundation.sql", ci)

    def test_read_only_reconciliation_screen_is_routed_and_visible(self) -> None:
        sql = MIGRATION.read_text(encoding="utf-8")
        data = WEB_DATA.read_text(encoding="utf-8")
        page = WEB_PAGE.read_text(encoding="utf-8")
        home = HOME_PAGE.read_text(encoding="utf-8")
        system_map = SYSTEM_MAP.read_text(encoding="utf-8")

        self.assertIn("('/importacao-historica', 'auditoria', true)", sql)
        self.assertIn("('/importacao-historica/mp', 'auditoria', true)", sql)
        self.assertIn('p_action_key: "migration.mp.view"', data)
        self.assertIn('.from("migration_mp_mapping_dashboard")', data)
        self.assertIn('.from("est_mp_historico_precos")', data)
        self.assertNotIn("auditedRpc(", data + page)
        self.assertNotIn("actions.ts", data + page)
        self.assertIn("Nenhum cadastro, lote ou saldo e criado automaticamente", page)
        self.assertIn('href="/importacao-historica/mp"', home)
        self.assertIn('primaryRoute: "/importacao-historica/mp"', system_map)


if __name__ == "__main__":
    unittest.main()
