from pathlib import Path
import unittest


ROOT = Path(__file__).resolve().parents[1]
FINANCE = ROOT / "apps/web/app/pedidos/financeiro"
MIGRATION = ROOT / "supabase/migrations/0118_organize_finance_workbench.sql"


class FinanceOpsGate01BContractTests(unittest.TestCase):
    def test_root_is_read_only_and_routes_are_separate(self):
        root_page = (FINANCE / "page.tsx").read_text(encoding="utf-8")
        self.assertNotIn("<ReceiptForm", root_page)
        self.assertNotIn("<CommissionAssignmentForm", root_page)
        self.assertNotIn("<CommissionPaymentForm", root_page)
        self.assertNotIn("<CommissionAdjustmentForm", root_page)
        for relative in (
            "comissionamento/page.tsx",
            "recebimentos/page.tsx",
            "comissoes/page.tsx",
            "comissoes/relatorio/page.tsx",
            "comissoes/relatorio/export/route.ts",
            "comissoes/relatorio/csv/route.ts",
        ):
            self.assertTrue((FINANCE / relative).is_file(), relative)

    def test_kpis_are_integral_and_not_derived_from_limited_lists(self):
        finance = (ROOT / "apps/web/lib/finance.ts").read_text(encoding="utf-8")
        migration = MIGRATION.read_text(encoding="utf-8")
        self.assertIn('"consultar_fin_dashboard"', finance)
        self.assertIn("create or replace function public.consultar_fin_dashboard", migration)
        dashboard_section = finance[finance.index("export async function getFinanceOverview"):finance.index("export async function searchReceiptOrders")]
        for old_limit in (".limit(80)", ".limit(200)", ".limit(300)"):
            self.assertNotIn(old_limit, dashboard_section)

    def test_atomic_access_controls_navigation_and_server_routes(self):
        access = (ROOT / "apps/web/lib/finance.ts").read_text(encoding="utf-8")
        workspace = (FINANCE / "finance-workspace.tsx").read_text(encoding="utf-8")
        shell = (ROOT / "apps/web/app/authenticated-app-shell.tsx").read_text(encoding="utf-8")
        for action in (
            "pedidos.commissions.assign",
            "financeiro.receipts.view",
            "financeiro.receipts.register",
            "financeiro.commissions.view",
            "financeiro.commissions.pay",
            "financeiro.commissions.adjust",
            "financeiro.commissions.export",
        ):
            self.assertIn(action, access)
        self.assertIn("item.href === \"/pedidos/financeiro\"", shell)
        self.assertIn("!financeAccess?.any", shell)
        self.assertIn("visible: access.commissionAssign", workspace)
        self.assertIn("visible: access.receiptsView || access.receiptsRegister", workspace)
        self.assertIn("visible: access.commissionsView || access.commissionsPay || access.commissionsAdjust", workspace)
        for page in ("comissionamento/page.tsx", "recebimentos/page.tsx", "comissoes/page.tsx", "comissoes/relatorio/page.tsx"):
            self.assertIn("redirect(\"/modulo-indisponivel?module=financeiro&reason=permission\")", (FINANCE / page).read_text(encoding="utf-8"))

    def test_receipt_reference_and_structured_errors_are_mandatory(self):
        migration = MIGRATION.read_text(encoding="utf-8")
        actions = (FINANCE / "actions.ts").read_text(encoding="utf-8")
        forms = (FINANCE / "finance-forms.tsx").read_text(encoding="utf-8")
        finance = (ROOT / "apps/web/lib/finance.ts").read_text(encoding="utf-8")
        self.assertIn("add column if not exists referencia_documental text", migration)
        self.assertIn("receipt document reference is required", migration)
        self.assertIn("p_referencia_documental: documentReference", actions)
        self.assertIn('fieldErrors.referencia_documental', actions)
        self.assertIn('name="referencia_documental"', forms)
        self.assertIn("useActionState", forms)
        self.assertIn("useFocusFirstError", forms)
        self.assertIn("FinanceQueryResult", finance)
        self.assertIn("Não foi possível consultar os pedidos agora.", finance)
        self.assertIn("O registro foi alterado durante esta operação.", actions)

    def test_search_and_commission_report_cover_operational_fields(self):
        migration = MIGRATION.read_text(encoding="utf-8")
        for fragment in (
            "identification.razao_social",
            "identification.nome_fantasia",
            "cad_cliente_documentos",
            "fat_notas_fiscais",
            "cad_cliente_propriedades",
            "cad_cliente_estabelecimentos",
            "cad_cliente_enderecos",
        ):
            self.assertIn(fragment, migration)
        smoke = (ROOT / "tests/sql/finance_ops_gate_01b.sql").read_text(encoding="utf-8")
        self.assertIn("NF-SIMP-FIN-0118", smoke)
        self.assertIn("NF-REM-FIN-0118", smoke)
        self.assertIn("jsonb_array_length(referencias_fiscais) = 2", smoke)
        report = (FINANCE / "comissoes/relatorio/page.tsx").read_text(encoding="utf-8")
        export = (FINANCE / "comissoes/relatorio/export/route.ts").read_text(encoding="utf-8")
        csv_compat = (FINANCE / "comissoes/relatorio/csv/route.ts").read_text(encoding="utf-8")
        for label in ("Previsto", "Liberado", "Pagamentos", "Estornos", "Ajustes", "Total a pagar"):
            self.assertIn(label, report)
        self.assertIn("access.commissionsView && access.commissionsExport", export)
        self.assertIn('url.pathname.replace(/\\/csv$/, "/export")', csv_compat)
        self.assertIn('url.searchParams.set("formato", "csv")', csv_compat)
        assignment_page = (FINANCE / "comissionamento/page.tsx").read_text(encoding="utf-8")
        assignment_form = (FINANCE / "finance-forms.tsx").read_text(encoding="utf-8")
        self.assertIn('entity="pessoas"', assignment_form)
        self.assertIn('entity="pedidos-comissionamento"', assignment_page)
        self.assertNotIn("getCommissionPeople(personQuery)", assignment_page)
        for metadata in ("Ambiente", "Emitido por", "Gerado em", "Versão"):
            self.assertIn(metadata, export)
        self.assertIn('"xlsx"', export)
        self.assertIn("XLSX_MIME_TYPE", export)
        self.assertIn("assignment.created_at::date <= p_data_corte", migration)

    def test_manuals_are_specific_to_each_finance_route(self):
        manuals = (ROOT / "apps/web/lib/manuals.ts").read_text(encoding="utf-8")
        for route in (
            "/pedidos/financeiro",
            "/pedidos/financeiro/comissionamento",
            "/pedidos/financeiro/recebimentos",
            "/pedidos/financeiro/comissoes",
            "/pedidos/financeiro/comissoes/relatorio",
        ):
            self.assertIn(f'manual("{route}"', manuals)
        self.assertTrue((ROOT / "docs/manuais/financeiro/AJUSTE_MANUAL.md").is_file())

    def test_contextual_finance_help_reuses_the_governed_route_manuals(self):
        workspace = (FINANCE / "finance-workspace.tsx").read_text(encoding="utf-8")
        manual_page = (FINANCE / "manual/page.tsx").read_text(encoding="utf-8")
        report = (FINANCE / "comissoes/relatorio/page.tsx").read_text(encoding="utf-8")

        self.assertIn('href: "/pedidos/financeiro/manual"', workspace)
        self.assertIn("❓ Ajuda desta tela", workspace)
        for key, anchor in (
            ("overview", "visao-geral"),
            ("assignment", "comissionamento"),
            ("receipts", "recebimentos"),
            ("commissions", "comissoes"),
            ("report", "relatorio"),
        ):
            self.assertIn(f'{key}: "{anchor}"', workspace)

        self.assertIn('current="manual"', manual_page)
        self.assertIn("manualForPath", manual_page)
        self.assertIn("Da venda liberada ao pagamento da comissão", manual_page)
        self.assertIn("Comissão prevista não é saldo disponível", manual_page)
        self.assertIn("Excel (.xlsx)", manual_page)
        for route in (
            "/pedidos/financeiro",
            "/pedidos/financeiro/comissionamento",
            "/pedidos/financeiro/recebimentos",
            "/pedidos/financeiro/comissoes",
            "/pedidos/financeiro/comissoes/relatorio",
        ):
            self.assertIn(route, manual_page)

        self.assertIn('redirect("/modulo-indisponivel?module=financeiro&reason=permission")', manual_page)
        self.assertNotIn('<div className="finance-page-actions">', report)

    def test_e2e_covers_atomic_accounts_and_navigation_overflow(self):
        bootstrap = (ROOT / "apps/web/e2e/bootstrap-synthetic-users.mjs").read_text(encoding="utf-8")
        e2e = (ROOT / "apps/web/e2e/finance-workbench.spec.mjs").read_text(encoding="utf-8")
        for account in ("commission-assign", "finance-receipts", "finance-commissions"):
            self.assertIn(account, bootstrap)
            self.assertIn(account, e2e)
        self.assertIn("navigation.scrollWidth > navigation.clientWidth", e2e)


if __name__ == "__main__":
    unittest.main()
