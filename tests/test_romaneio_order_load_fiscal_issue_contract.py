import unittest
from pathlib import Path


ROOT = Path(__file__).resolve().parents[1]
MIGRATION = ROOT / "supabase/migrations/0071_romaneio_order_load_fiscal_issue_contract.sql"
PAGE = ROOT / "apps/web/app/romaneios/page.tsx"
ACTIONS = ROOT / "apps/web/app/romaneios/actions.ts"


class RomaneioOrderLoadFiscalIssueContractTest(unittest.TestCase):
    def test_order_load_is_atomic_and_explicit(self):
        sql = MIGRATION.read_text(encoding="utf-8")
        page = PAGE.read_text(encoding="utf-8")
        actions = ACTIONS.read_text(encoding="utf-8")
        self.assertIn("gravar_exp_romaneio_pedido", sql)
        self.assertIn("for update", sql.lower())
        self.assertIn("Gravar romaneio", page)
        self.assertIn('name="pedido_item_id"', page)
        self.assertIn('name={`quantidade_${item.pedidoItemId}`}', page)
        self.assertIn('"gravar_exp_romaneio_pedido"', actions)
        self.assertNotIn('name="observacao" placeholder="Opcional"', page)

    def test_stock_issue_requires_invoice_and_logistics(self):
        sql = MIGRATION.read_text(encoding="utf-8")
        actions = ACTIONS.read_text(encoding="utf-8")
        self.assertIn("driver and vehicle are required before stock issue", sql)
        self.assertIn("an emitted shipping invoice is required", sql)
        self.assertIn("invoice items must match romaneio quantities", sql)
        self.assertIn("confirmar_exp_romaneio_impl_0071", sql)
        self.assertIn("p_nota_fiscal_id", actions)
        self.assertNotIn("p_observacao: optionalField(formData, \"observacao\")", actions)

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


if __name__ == "__main__":
    unittest.main()
