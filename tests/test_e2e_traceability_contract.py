import pathlib
import unittest


ROOT = pathlib.Path(__file__).resolve().parents[1]


class E2ETraceabilityContractTests(unittest.TestCase):
    def test_external_reference_contract_does_not_claim_issuance(self):
        migration = (ROOT / "supabase/migrations/0105_operational_stock_entry_external_fiscal_refs.sql").read_text(encoding="utf-8")
        page = (ROOT / "apps/web/app/romaneios/page.tsx").read_text(encoding="utf-8")
        self.assertIn("Nao emite NF, nao baixa estoque e nao libera comissao", migration)
        self.assertIn("Registrar referência de remessa", page)
        self.assertNotIn("Emita e vincule a NF", page)
        self.assertNotIn("Confirmar NF e baixar estoque", page)

    def test_stock_entry_is_transactional_and_uses_existing_atomic_permissions(self):
        migration = (ROOT / "supabase/migrations/0105_operational_stock_entry_external_fiscal_refs.sql").read_text(encoding="utf-8")
        self.assertIn("require_current_user_permission('estoque.mp.lots.create')", migration)
        self.assertIn("require_current_user_permission('estoque.mp.acquisition_value.register')", migration)
        self.assertIn("insert into public.est_movimentos_mp_valores", migration)
        self.assertIn("idempotency key reused with different stock entry request", migration)

    def test_traceability_is_derived_read_only_and_deny_by_default(self):
        migration = (ROOT / "supabase/migrations/0106_total_lot_traceability.sql").read_text(encoding="utf-8")
        for action in (
            "qualidade.rastreabilidade.view",
            "qualidade.rastreabilidade.recall_simulate",
            "qualidade.rastreabilidade.export",
        ):
            self.assertIn(action, migration)
        self.assertIn("default_allowed, sort_order", migration)
        self.assertIn("revoke all on public.rel_rastreabilidade_arestas from public, anon, authenticated", migration)
        self.assertNotIn("create table public.rel_rastreabilidade", migration.lower())
        self.assertIn("('/qualidade/rastreabilidade', 'relatorios', true)", migration)
        self.assertIn("pcp_op_consumos_componentes", migration)
        self.assertIn("pcp_ordem_envase_reservas", migration)
        self.assertIn("exp_romaneio_movimentos_pa", migration)
        self.assertIn("cad_cliente_contatos", migration)
        self.assertIn("divergencia_origem", migration)
        self.assertIn("current_system_environment()::text", migration)

    def test_canonical_traceability_route_and_manual_exist(self):
        page = (ROOT / "apps/web/app/qualidade/rastreabilidade/page.tsx").read_text(encoding="utf-8")
        manuals = (ROOT / "apps/web/lib/manuals.ts").read_text(encoding="utf-8")
        navigation = (ROOT / "apps/web/lib/app-navigation.ts").read_text(encoding="utf-8")
        self.assertIn("Rastreabilidade total", page)
        self.assertIn("Simular recolhimento", page)
        self.assertNotIn('placeholder="Código interno"', page)
        self.assertNotIn("defaultValue={filters.customerId}", page)
        self.assertIn('manual("/qualidade/rastreabilidade"', manuals)
        self.assertIn('href: "/qualidade/rastreabilidade"', navigation)

    def test_disposable_browser_bootstrap_separates_auth_from_database_bootstrap(self):
        bootstrap = (ROOT / "apps/web/e2e/bootstrap-synthetic-users.mjs").read_text(encoding="utf-8")
        browser = (ROOT / "apps/web/e2e/operational-routes.spec.mjs").read_text(encoding="utf-8")
        workflow = (ROOT / ".github/workflows/operational-e2e.yml").read_text(encoding="utf-8")
        self.assertIn("auth.admin.createUser", bootstrap)
        self.assertIn("E2E_BOOTSTRAP_SQL_PATH", bootstrap)
        self.assertIn("perform public.set_system_runtime_environment", bootstrap)
        self.assertNotIn('.from("permission_actions")', bootstrap)
        self.assertIn('psql "$DB_URL" -v ON_ERROR_STOP=1 -f "$E2E_BOOTSTRAP_SQL_PATH"', workflow)
        self.assertIn('material registration and valued stock entry cross the real application boundary', browser)
        self.assertIn('input[name="codigo_lote_fornecedor"]', browser)
        self.assertIn('result=stock_entry_created', browser)


if __name__ == "__main__":
    unittest.main()
