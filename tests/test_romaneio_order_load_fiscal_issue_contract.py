import unittest
from pathlib import Path


ROOT = Path(__file__).resolve().parents[1]
MIGRATION = ROOT / "supabase/migrations/0071_romaneio_order_load_fiscal_issue_contract.sql"
PAGE = ROOT / "apps/web/app/romaneios/page.tsx"
ACTIONS = ROOT / "apps/web/app/romaneios/actions.ts"
PREPARATION = ROOT / "apps/web/app/romaneios/romaneio-preparation.tsx"
PRINT_PAGE = ROOT / "apps/web/app/romaneios/[id]/imprimir/page.tsx"
MANUAL_PAGE = ROOT / "apps/web/app/romaneios/manual/page.tsx"
ROMANEIO_DATA = ROOT / "apps/web/lib/romaneios.ts"
CONTEXTUAL_LOTS_ROUTE = ROOT / "apps/web/app/romaneios/api/lotes/route.ts"
OLD_LOTS_ROUTE = ROOT / "apps/web/app/api/romaneios/lotes/route.ts"


class RomaneioOrderLoadFiscalIssueContractTest(unittest.TestCase):
    def test_order_load_is_atomic_and_explicit(self):
        sql = MIGRATION.read_text(encoding="utf-8")
        page = PAGE.read_text(encoding="utf-8")
        actions = ACTIONS.read_text(encoding="utf-8")
        preparation = PREPARATION.read_text(encoding="utf-8")
        self.assertIn("gravar_exp_romaneio_pedido", sql)
        self.assertIn("for update", sql.lower())
        self.assertIn("Gravar rascunho do romaneio", preparation)
        self.assertIn('name="pedido_item_id"', preparation)
        self.assertIn('name={`quantidade_${item.pedidoItemId}`}', preparation)
        self.assertIn('"gravar_exp_romaneio_pedido_idempotente"', actions)
        self.assertNotIn('name="observacao" placeholder="Opcional"', page)

    def test_stock_issue_requires_invoice_and_logistics(self):
        sql = MIGRATION.read_text(encoding="utf-8")
        actions = ACTIONS.read_text(encoding="utf-8")
        page = PAGE.read_text(encoding="utf-8")
        self.assertIn("driver and vehicle are required before stock issue", sql)
        self.assertIn("an emitted shipping invoice is required", sql)
        self.assertIn("invoice items must match romaneio quantities", sql)
        self.assertIn("confirmar_exp_romaneio_impl_0071", sql)
        self.assertIn("p_nota_fiscal_id", actions)
        self.assertNotIn("p_observacao: optionalField(formData, \"observacao\")", actions)
        for result_key in (
            "logistics_incomplete_for_issue",
            "invoice_link_mismatch",
            "invoice_not_ready",
            "invoice_items_mismatch",
            "load_measurements_pending",
        ):
            self.assertIn(result_key, actions)
            self.assertIn(result_key, page)

    def test_missing_measurements_are_not_invented(self):
        sql = MIGRATION.read_text(encoding="utf-8")
        self.assertIn("unidades_por_volume_logistico is null", sql)
        self.assertIn("ceil(base.quantidade_romaneada / base.unidades_por_volume_logistico)", sql)
        self.assertIn("load volumes and weights must be fully configured", sql)
        self.assertIn("nenhum dado ausente e inventado", sql)
        self.assertIn("update_cad_apresentacao_logistica", sql)

    def test_stock_position_uses_append_only_reservation_events(self):
        sql = MIGRATION.read_text(encoding="utf-8")
        self.assertIn("create table public.est_reserva_pa_eventos", sql)
        self.assertIn("trg_est_reserva_pa_event", sql)
        self.assertIn("consultar_est_estoque_pa_posicao", sql)
        self.assertIn("saldo_empenhado", sql)
        self.assertIn("volumes_empenhados", sql)

    def test_operational_ui_hides_raw_status_and_requires_all_issue_prerequisites(self):
        page = PAGE.read_text(encoding="utf-8")
        actions = ACTIONS.read_text(encoding="utf-8")
        self.assertIn("romaneioStatusLabel(romaneio.status)", page)
        self.assertIn("reservationsComplete && logisticsComplete && shippingReferences.length > 0", page)
        self.assertIn("Antes da baixa de estoque", page)
        self.assertNotIn('placeholder="Observacao da atribuicao"', page)
        self.assertIn("p_motivo: null", actions)
        self.assertIn('normalized.includes("module unavailable")', actions)
        self.assertIn("Módulo responsável indisponível", page)
        self.assertIn("Dados de entrega atualizados", page)
        self.assertNotIn("Entregador e veiculo foram vinculados", page)

    def test_guided_ui_queries_stock_only_after_product_selection(self):
        page = PAGE.read_text(encoding="utf-8")
        preparation = PREPARATION.read_text(encoding="utf-8")
        self.assertIn("Escolha o pedido", preparation)
        self.assertIn("Reserve os lotes do Romaneio gravado", preparation)
        self.assertIn("/romaneios/api/lotes?produto_embalagem_id=", preparation)
        self.assertIn("Estoque ainda não consultado", preparation)
        self.assertIn("Saldo insuficiente para completar a reserva", preparation)
        self.assertIn("reservableFromSelectedLot", preparation)
        self.assertIn("Math.min(remaining, selectedLot.saldoDisponivel)", preparation)
        self.assertIn("disabled={!selectedLot}", preparation)
        self.assertIn("item.quantidadeReservada < item.quantidadeRomaneada", preparation)
        self.assertIn('value.replace(",", ".")', preparation)
        self.assertIn("Record<number, string>", preparation)
        self.assertNotIn("legacy-romaneio-ui", page)
        self.assertNotIn("Lotes PA disponiveis", page)
        self.assertNotIn("Livre para novo romaneio", page)
        self.assertIn("Prévia consultiva da carga", preparation)
        self.assertIn("Esta prévia não grava nem reserva estoque", preparation)
        self.assertIn("Planejar carga", page)
        self.assertIn("Consultar Romaneios", page)
        self.assertTrue(CONTEXTUAL_LOTS_ROUTE.exists())
        self.assertFalse(OLD_LOTS_ROUTE.exists())
        read_model = ROMANEIO_DATA.read_text(encoding="utf-8")
        route = CONTEXTUAL_LOTS_ROUTE.read_text(encoding="utf-8")
        self.assertIn('.in("lote_pa_id", referencedLotIds)', read_model)
        self.assertIn('.eq("produto_embalagem_id", productPackageId)', route)
        self.assertNotIn('.order("updated_at", { ascending: false })\n        .limit(400)', read_model)

    def test_consultation_shortcuts_open_governed_views(self):
        page = PAGE.read_text(encoding="utf-8")
        self.assertIn('href="/romaneios"', page)
        self.assertIn("?modo=consulta&status=romaneios-rascunho#romaneios-rascunho", page)
        self.assertIn("?modo=consulta&status=romaneios-separacao#romaneios-separacao", page)
        self.assertIn("open={activeGroup === group.id}", page)
        self.assertIn("Nenhum registro", page)

    def test_logistics_upgrade_gap_does_not_hide_the_dashboard(self):
        source = ROMANEIO_DATA.read_text(encoding="utf-8")
        self.assertIn('completeResult.error?.message.includes("unidades_por_volume_logistico")', source)
        self.assertIn('result.error?.message.includes("exp_romaneio_carga_resumo")', source)
        self.assertIn("configuracao logistica como pendente", source)

    def test_status_navigation_manual_and_print_traceability_are_present(self):
        page = PAGE.read_text(encoding="utf-8")
        print_page = PRINT_PAGE.read_text(encoding="utf-8")
        manual = MANUAL_PAGE.read_text(encoding="utf-8")
        self.assertIn("RomaneioStatusGroups", page)
        self.assertIn("Como fazer um Romaneio", manual)
        self.assertIn("romaneio.emissorNome", print_page)
        self.assertIn("print-document-footer", print_page)


if __name__ == "__main__":
    unittest.main()
