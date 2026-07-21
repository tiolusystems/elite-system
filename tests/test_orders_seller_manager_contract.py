from pathlib import Path
import unittest

ROOT = Path(__file__).resolve().parents[1]


class OrdersSellerManagerContractTest(unittest.TestCase):
    def test_database_contract_is_scoped_and_audited(self):
        sql = (ROOT / "supabase/migrations/0078_orders_seller_manager_credit_scope.sql").read_text(encoding="utf-8")
        self.assertIn("current_user_manages_seller", sql)
        self.assertIn("can_current_user_view_order", sql)
        self.assertIn("scoped authenticated read com_pedidos", sql)
        self.assertIn("create_com_pedido_vendedor", sql)
        self.assertIn("registrar_com_pedido_decisao_gerencial", sql)
        self.assertIn("cad_limite_credito_eventos", sql)
        self.assertIn("char_length(trim(coalesce(p_justificativa, ''))) < 10", sql)
        self.assertNotIn('for select to authenticated using (public.current_actor_id() is not null);\n\ncreate policy "scoped authenticated read com_pedido_itens"', sql)

    def test_seller_ui_does_not_accept_spoofed_seller_or_status(self):
        page = (ROOT / "apps/web/app/pedidos/page.tsx").read_text(encoding="utf-8")
        self.assertNotIn('name="vendedor_id"', page)
        self.assertNotIn('name="status"', page)
        self.assertIn("Enviar para liberação", page)
        self.assertIn("Liberações gerenciais", page)
        self.assertIn("Ajustar limite do cliente", page)
        self.assertNotIn("pendente_aprovacao</option>", page)

    def test_manual_exists(self):
        manual = ROOT / "docs/manuais/pedidos/PEDIDOS_E_APROVACAO.md"
        self.assertTrue(manual.exists())
        text = manual.read_text(encoding="utf-8")
        self.assertIn("## Vendedor", text)
        self.assertIn("## Gerente", text)


if __name__ == "__main__":
    unittest.main()
