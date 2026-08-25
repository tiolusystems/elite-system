from pathlib import Path
import unittest


ROOT = Path(__file__).resolve().parents[1]


class OrdersDeliveryScheduleContractTest(unittest.TestCase):
    def test_database_contract_is_relational_scoped_and_atomic(self):
        sql = (ROOT / "supabase/migrations/0116_govern_order_delivery_schedules.sql").read_text(encoding="utf-8")
        self.assertIn("create table public.com_pedido_entregas", sql)
        self.assertIn("create table public.com_pedido_entrega_itens", sql)
        self.assertIn("num_nonnulls(propriedade_id, estabelecimento_id, endereco_id) = 1", sql)
        self.assertIn("references public.cad_cliente_propriedades(id, cliente_id) on delete restrict", sql)
        self.assertIn("references public.com_pedido_itens(id, pedido_id) on delete restrict", sql)
        self.assertIn("public.can_current_user_view_order(pedido_id)", sql)
        self.assertIn("revoke insert, update, delete, truncate", sql)
        self.assertIn("create_com_pedido_vendedor_programado_idempotente", sql)
        self.assertIn("delivery schedule does not cover order quantities", sql)
        self.assertIn("duplicate sale presentation is not allowed", sql)
        self.assertIn("pg_advisory_xact_lock", sql)
        self.assertIn("'pedidos.programacao_entrega_criada'", sql)
        self.assertNotIn("on delete cascade", sql.lower())

    def test_portfolio_and_locations_are_governed(self):
        sql = (ROOT / "supabase/migrations/0116_govern_order_delivery_schedules.sql").read_text(encoding="utf-8")
        library = (ROOT / "apps/web/lib/orders.ts").read_text(encoding="utf-8")
        self.assertIn("consultar_com_carteira_clientes_paginada", sql)
        self.assertIn("consultar_com_locais_entrega_cliente", sql)
        self.assertIn("public.current_user_manages_seller", sql)
        self.assertIn("public.can_current_user_view_client", sql)
        self.assertIn("consultar_com_carteira_clientes_paginada", library)
        self.assertIn("consultar_com_locais_entrega_cliente", library)

    def test_interface_separates_client_location_product_and_presentation(self):
        page = (ROOT / "apps/web/app/pedidos/page.tsx").read_text(encoding="utf-8")
        entry = (ROOT / "apps/web/app/pedidos/order-entry-editor.tsx").read_text(encoding="utf-8")
        items = (ROOT / "apps/web/app/pedidos/order-items-editor.tsx").read_text(encoding="utf-8")
        deliveries = (ROOT / "apps/web/app/pedidos/delivery-schedule-editor.tsx").read_text(encoding="utf-8")
        action = (ROOT / "apps/web/app/pedidos/actions.ts").read_text(encoding="utf-8")
        css = (ROOT / "apps/web/app/globals.css").read_text(encoding="utf-8")
        self.assertIn("Sua carteira", page)
        self.assertIn("2. Local de entrega", page)
        self.assertIn("4. Entregas", page)
        self.assertIn("6. Confirmação", page)
        self.assertIn("DeliveryLocationSelector", deliveries)
        self.assertIn("4. Programação das entregas", deliveries)
        self.assertIn("Adicionar outra entrega", deliveries)
        self.assertIn("Selecione o produto", items)
        self.assertIn("Selecione a apresentação", items)
        self.assertIn("Distribua integralmente", entry)
        self.assertIn("Antes de confirmar as condições comerciais", entry)
        self.assertIn("submissionIssues", entry)
        self.assertIn("Volume físico conhecido", entry)
        self.assertIn("Pedido:", deliveries)
        self.assertIn("Nesta entrega:", deliveries)
        self.assertIn("Volume programado:", deliveries)
        self.assertIn("volumeLiters", deliveries)
        self.assertIn("hasVolumeInput", items)
        self.assertNotIn("Litros pendentes de configuração", items)
        self.assertIn("const validRows = rows.filter(isValidOrderItem)", entry)
        self.assertIn("{hasValidItem ? (", entry)
        self.assertLess(
            entry.index("          <DeliveryLocationSelector"),
            entry.index("          <OrderItemsEditor")
        )
        self.assertLess(
            entry.index("          <OrderItemsEditor"),
            entry.index("{hasValidItem ? <DeliveryScheduleEditor")
        )
        self.assertIn("@media (max-width: 1100px)", css)
        self.assertIn(".order-item-head { display: none; }", css)
        self.assertIn("repeat(2, minmax(0, 1fr)) 40px", css)
        self.assertIn('name="proposta_json"', entry)
        self.assertIn("sessionStorage", entry)
        self.assertIn("Os dados foram preservados", page)
        self.assertIn('name="return_page"', page)
        self.assertIn('query.set("pagina"', action)
        self.assertIn("confirmar_com_revisao_comercial_venda_idempotente", action)
        self.assertNotIn("create_com_pedido_vendedor_programado_idempotente", action)
        self.assertNotIn('name="propriedade"', entry)

    def test_delivery_schedule_stays_hidden_until_an_item_is_valid(self):
        entry = (ROOT / "apps/web/app/pedidos/order-entry-editor.tsx").read_text(encoding="utf-8")
        self.assertIn("const hasValidItem = validRows.length > 0", entry)
        self.assertIn("rows={validRows}", entry)
        self.assertIn('type === "venda" && hasValidItem', entry)
        self.assertIn("{hasValidItem ? <DeliveryScheduleEditor", entry)

    def test_portfolio_visibility_does_not_imply_order_creation_identity(self):
        page = (ROOT / "apps/web/app/pedidos/page.tsx").read_text(encoding="utf-8")
        library = (ROOT / "apps/web/lib/orders.ts").read_text(encoding="utf-8")
        action = (ROOT / "apps/web/app/pedidos/actions.ts").read_text(encoding="utf-8")
        self.assertIn("canCreateForSelected", page)
        self.assertIn("Consulta disponível, criação indisponível", page)
        self.assertIn("não representa o vendedor responsável", page)
        self.assertIn('supabase.rpc("current_commercial_person_id")', library)
        self.assertIn("sellerId: Number(row.vendedor_id)", library)
        self.assertIn("commercialPersonId: nullableNumber(commercialPerson.data)", library)
        self.assertIn('normalized.includes("commercial identity not linked")', action)

    def test_manual_explains_operational_effects(self):
        manual = (ROOT / "docs/manuais/pedidos/PEDIDOS_E_APROVACAO.md").read_text(encoding="utf-8")
        self.assertIn("programação de entrega", manual)
        self.assertIn("não reserva estoque", manual)
        self.assertIn("produto e depois a apresentação", manual)
        self.assertIn("mais de uma entrega", manual)
        self.assertIn("conta está vinculada ao vendedor responsável", manual)

    def test_sql_smoke_covers_permissions_idempotency_and_allocation(self):
        smoke = (ROOT / "tests/sql/order_delivery_schedules.sql").read_text(encoding="utf-8")
        self.assertIn("scheduled order retry did not return the original order", smoke)
        self.assertIn("direct scheduled delivery write is exposed", smoke)
        self.assertIn("incomplete delivery allocation was accepted", smoke)
        self.assertIn("duplicate presentation was accepted", smoke)
        self.assertIn("user without permission created a scheduled order", smoke)


if __name__ == "__main__":
    unittest.main()
