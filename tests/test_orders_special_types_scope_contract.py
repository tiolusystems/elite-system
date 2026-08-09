from pathlib import Path
import unittest

ROOT = Path(__file__).resolve().parents[1]
MIGRATION = ROOT / "supabase/migrations/0085_orders_special_types_portfolio_scope.sql"
ACTIONS = ROOT / "apps/web/app/pedidos/actions.ts"
ENTRY = ROOT / "apps/web/app/pedidos/order-entry-editor.tsx"


class OrdersSpecialTypesScopeContractTest(unittest.TestCase):
    def test_special_orders_are_scoped_blocked_and_audited(self):
        sql = MIGRATION.read_text(encoding="utf-8").lower()
        self.assertIn("create or replace function public.create_com_pedido_vendedor_especial", sql)
        self.assertIn("client is outside seller portfolio", sql)
        self.assertIn("p_tipo_pedido not in ('bonificacao', 'mostruario')", sql)
        self.assertIn("bonus justification must have at least 10 characters", sql)
        self.assertIn("p_tipo_pedido, 'blocked'", sql)
        self.assertIn("'pendente_aprovacao', 'blocked', 'blocked'", sql)
        self.assertIn("public.log_audited_rpc_change", sql)
        self.assertNotIn("grant execute on function public.create_com_pedido_vendedor_especial(bigint, bigint, numeric, text, date, text) to anon", sql)

    def test_exchange_is_scoped_and_cannot_start_open(self):
        sql = MIGRATION.read_text(encoding="utf-8").lower()
        self.assertIn("rename to create_com_pedido_troca_impl_0085", sql)
        self.assertIn("perform public.require_current_user_permission('pedidos.exchange.create')", sql)
        self.assertIn("p_status <> 'blocked'", sql)
        self.assertIn("public.current_user_manages_seller(v_origin_seller)", sql)
        self.assertIn("order is outside commercial scope", sql)
        self.assertIn("from public, anon, authenticated", sql)

    def test_single_order_form_exposes_governed_types(self):
        actions = ACTIONS.read_text(encoding="utf-8")
        entry = ENTRY.read_text(encoding="utf-8")
        self.assertIn('"create_com_pedido_vendedor_especial_idempotente"', actions)
        for label in ("Venda", "Bonificação", "Mostruário", "Troca"):
            self.assertIn(label, entry)
        self.assertIn("Bonificação não gera comissão e exige liberação de superior.", entry)


if __name__ == "__main__":
    unittest.main()
