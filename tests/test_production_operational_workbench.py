from __future__ import annotations

import unittest
from pathlib import Path


ROOT = Path(__file__).resolve().parents[1]
PRODUCTION = ROOT / "apps" / "web" / "app" / "producao"
OVERVIEW = PRODUCTION / "page.tsx"
SHELL = PRODUCTION / "production-shell.tsx"
FORMULAS_PAGE = PRODUCTION / "formulas" / "page.tsx"
FORMULAS_COMPONENT = PRODUCTION / "formulas" / "formula-workbench.tsx"
FORMULAS_EDITOR = PRODUCTION / "formulas" / "formula-creation-form.tsx"
GUARANTEES_PAGE = PRODUCTION / "garantias" / "page.tsx"
GUARANTEES_COMPONENT = PRODUCTION / "garantias" / "guarantee-workbench.tsx"
ORDERS_PAGE = PRODUCTION / "ordens" / "page.tsx"
ORDERS_COMPONENT = PRODUCTION / "ordens" / "orders-workbench.tsx"
QUALITY_PAGE = PRODUCTION / "qualidade" / "page.tsx"
QUALITY_COMPONENT = PRODUCTION / "qualidade" / "quality-workbench.tsx"
STOCK_PAGE = PRODUCTION / "estoque" / "page.tsx"
STOCK_COMPONENT = PRODUCTION / "estoque" / "stock-workbench.tsx"
TRANSFORMATIONS_PAGE = PRODUCTION / "transformacoes" / "page.tsx"
TRANSFORMATIONS_COMPONENT = PRODUCTION / "transformacoes" / "transformation-workbench.tsx"
PCP_PAGE = ROOT / "apps" / "web" / "app" / "pcp" / "page.tsx"
PCP_ACTIONS = ROOT / "apps" / "web" / "app" / "pcp" / "actions.ts"
STYLES = ROOT / "apps" / "web" / "app" / "globals.css"


class ProductionOperationalWorkbenchTests(unittest.TestCase):
    def test_production_has_a_single_shell_and_operational_routes(self) -> None:
        shell = SHELL.read_text(encoding="utf-8")
        overview = OVERVIEW.read_text(encoding="utf-8")

        for route in (
            "/producao",
            "/producao/formulas",
            "/producao/garantias",
            "/producao/ordens",
            "/producao/qualidade",
            "/producao/envase",
            "/producao/estoque",
            "/producao/transformacoes",
        ):
            self.assertIn(route, shell if route != "/producao" else overview + shell)

        self.assertIn("ProductionShell", overview)
        self.assertIn("Sequencia da producao", overview)
        self.assertIn('href="/producao/ordens"', overview)
        self.assertIn('href="/producao/qualidade"', overview)
        self.assertIn('href="/producao/envase"', overview)
        self.assertIn('href="/producao/estoque"', overview)
        self.assertIn('href="/producao/transformacoes"', overview)
        self.assertIn("8 etapas", overview)

    def test_formula_and_guarantee_pages_reuse_shared_business_components(self) -> None:
        formulas_page = FORMULAS_PAGE.read_text(encoding="utf-8")
        guarantees_page = GUARANTEES_PAGE.read_text(encoding="utf-8")
        pcp_page = PCP_PAGE.read_text(encoding="utf-8")

        self.assertIn("<FormulaWorkbench", formulas_page)
        self.assertIn("<GuaranteeWorkbench", guarantees_page)
        self.assertIn("<FormulaWorkbench", pcp_page)
        self.assertIn("<GuaranteeWorkbench", pcp_page)
        self.assertIn("<QualityFinishForm", pcp_page)

    def test_orders_route_filters_queue_and_uses_relational_lot_ids(self) -> None:
        page = ORDERS_PAGE.read_text(encoding="utf-8")
        component = ORDERS_COMPONENT.read_text(encoding="utf-8")

        self.assertIn('active="ordens"', page)
        self.assertIn('name="status"', page)
        self.assertIn('name="tipo"', page)
        self.assertIn("dashboard.recentOps.filter", page)
        self.assertIn("<OrdersWorkbench", page)
        self.assertIn('name="op_componente_id"', component)
        self.assertIn('name="lote_id"', component)
        self.assertIn('value={lot.id}', component)
        self.assertNotIn("<datalist", component)

    def test_quality_route_uses_only_started_ops_for_finalization(self) -> None:
        page = QUALITY_PAGE.read_text(encoding="utf-8")
        component = QUALITY_COMPONENT.read_text(encoding="utf-8")

        self.assertIn('active="qualidade"', page)
        self.assertIn('op.status === "in_process"', page)
        self.assertIn('op.status === "completed"', page)
        self.assertIn("<QualityWorkbench", page)
        self.assertIn("finishPcpOpAction", component)
        self.assertIn("calculateOpGuaranteesAction", component)
        self.assertIn('name="cq_status"', component)
        self.assertIn('name="separador_pessoa_id"', component)
        self.assertIn('name="conferente_pessoa_id"', component)
        self.assertIn("<OutputRows", component)
        self.assertNotIn(".rpc(", component)

    def test_quality_output_is_fixed_to_formula_product_and_real_volume(self) -> None:
        component = QUALITY_COMPONENT.read_text(encoding="utf-8")
        editor = (ROOT / "apps/web/app/pcp/production-editors.tsx").read_text(encoding="utf-8")
        actions = PCP_ACTIONS.read_text(encoding="utf-8")
        self.assertIn("fixedProduct={{ id: op.produtoId, label: op.produtoLabel }}", component)
        self.assertIn("Igual ao volume real do CQ", editor)
        self.assertIn("quantidade: volume", actions)
        self.assertIn("opTypeLabel(op.tipoOp)", component)
        self.assertIn("cqStatusLabel(op.cqStatus)", component)

    def test_stock_route_uses_derived_balances_and_audited_release(self) -> None:
        page = STOCK_PAGE.read_text(encoding="utf-8")
        component = STOCK_COMPONENT.read_text(encoding="utf-8")

        self.assertIn('active="estoque"', page)
        self.assertIn('name="familia"', page)
        self.assertIn('name="q"', page)
        self.assertIn("getStockProducts", page)
        self.assertIn("getTargetStockLots", page)
        self.assertIn("Os lotes serao exibidos somente depois", page)
        for balance in ("saldoFisico", "quantidadeReservada", "saldoDisponivel"):
            self.assertIn(balance, component)
        self.assertIn("releaseBlockedLotAction", component)
        self.assertIn('name="lote_id"', component)
        self.assertIn('href={`/producao/transformacoes?', component)
        self.assertNotIn(".rpc(", page + component)

    def test_transformations_reuse_reprocessing_op_contract(self) -> None:
        page = TRANSFORMATIONS_PAGE.read_text(encoding="utf-8")
        component = TRANSFORMATIONS_COMPONENT.read_text(encoding="utf-8")
        orders = ORDERS_COMPONENT.read_text(encoding="utf-8")

        self.assertIn('active="transformacoes"', page)
        self.assertIn('op.tipoOp === "reprocessamento"', page)
        self.assertIn("createPcpOpAction", component)
        self.assertIn('name="tipo_op" value="reprocessamento"', component)
        self.assertIn('name="return_to" value="transformacoes"', component)
        self.assertIn('name="quantidade_planejada"', component)
        self.assertIn("Volume planejado (L)", component)
        self.assertIn("PlanningOrderCard", component)
        self.assertIn("export function PlanningOrderCard", orders)
        self.assertIn('returnTo="transformacoes"', component)
        self.assertNotIn(".rpc(", page + component)

    def test_writes_stay_in_existing_audited_server_actions(self) -> None:
        formulas = FORMULAS_COMPONENT.read_text(encoding="utf-8") + FORMULAS_EDITOR.read_text(encoding="utf-8")
        guarantees = GUARANTEES_COMPONENT.read_text(encoding="utf-8")
        actions = PCP_ACTIONS.read_text(encoding="utf-8")

        for action in (
            "createPcpFormulaAction",
            "activatePcpFormulaAction",
            "registerProductGuaranteeAction",
            "registerMpLotGuaranteeAction",
        ):
            self.assertIn(action, formulas + guarantees)

        for rpc in (
            "create_pcp_formula_versao_idempotente",
            "activate_pcp_formula_versao",
            "registrar_pcp_garantia_produto",
            "registrar_pcp_garantia_lote_mp",
        ):
            self.assertIn(f'auditedRpc(supabase, "{rpc}"', actions)

        self.assertNotIn(".rpc(", formulas + guarantees)

        orders = ORDERS_COMPONENT.read_text(encoding="utf-8")
        for action in (
            "createPcpOpAction",
            "reservePcpComponentAction",
            "startPcpOpAction",
            "cancelPcpOpAction",
        ):
            self.assertIn(action, orders)
        self.assertNotIn(".rpc(", orders)

        quality = QUALITY_COMPONENT.read_text(encoding="utf-8")
        self.assertIn("finishPcpOpAction", quality)
        self.assertIn("calculateOpGuaranteesAction", quality)
        self.assertNotIn(".rpc(", quality)

    def test_actions_return_to_the_new_operational_routes(self) -> None:
        actions = PCP_ACTIONS.read_text(encoding="utf-8")

        self.assertIn('/producao/formulas?result=formula_created', actions)
        self.assertIn('/producao/formulas?result=formula_activated', actions)
        self.assertIn('/producao/garantias?result=product_guarantee_registered', actions)
        self.assertIn('/producao/garantias?result=mp_lot_guarantee_registered', actions)
        self.assertNotIn('/pcp?result=formula_', actions)
        self.assertNotIn('/producao?result=product_guarantee_', actions)
        self.assertIn('path: "/producao/ordens"', actions)
        self.assertIn('path: "/producao/transformacoes"', actions)
        self.assertIn('redirectWithResult(returnTarget.path, "op_created"', actions)
        self.assertIn('redirectWithResult(returnTarget.path, "component_reserved"', actions)
        self.assertIn('redirectWithResult(returnTarget.path, "op_started"', actions)
        self.assertIn('redirectWithResult(returnTarget.path, "op_cancelled"', actions)
        self.assertIn('/producao/qualidade?result=op_finished', actions)
        self.assertIn('/producao/qualidade?result=guarantees_calculated', actions)
        self.assertIn('/producao/estoque?result=blocked_lot_released', actions)
        self.assertNotIn('/pcp?result=op_finished', actions)

    def test_layout_has_explicit_responsive_contract(self) -> None:
        styles = STYLES.read_text(encoding="utf-8")

        self.assertIn(".production-workspace", styles)
        self.assertIn(".operation-card-grid", styles)
        self.assertIn("grid-template-columns: repeat(3, minmax(0, 1fr))", styles)
        self.assertIn("grid-template-columns: 1fr", styles)
        self.assertIn(".production-tabs", styles)
        self.assertIn(".inventory-lot-grid", styles)
        self.assertIn(".inventory-filter", styles)
        self.assertIn(".transformation-steps", styles)


if __name__ == "__main__":
    unittest.main()
