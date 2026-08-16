from pathlib import Path
import unittest

ROOT = Path(__file__).resolve().parents[1]
LEGACY_ENTRYPOINT = "public.create_com_pedido_operacional(bigint,bigint,numeric,numeric,bigint,text,text,date,bigint,numeric,text)"


class LegacyOrdersRpcGuardTest(unittest.TestCase):
    def test_legacy_entry_points_are_scoped(self):
        sql = (ROOT / "supabase/migrations/0079_orders_legacy_rpc_scope_guard.sql").read_text(encoding="utf-8")
        self.assertIn("seller identity is derived from current session", sql)
        self.assertIn("client is outside seller portfolio", sql)
        self.assertIn("order is outside manager team", sql)
        self.assertIn("create_com_pedido_vendedor_core_0079", sql)
        self.assertIn("'venda', 'blocked'", sql)
        self.assertNotIn("grant execute on function public.create_com_pedido_vendedor_core_0079", sql)

    def test_legacy_public_entrypoint_is_fail_closed(self):
        sql = (ROOT / "supabase/migrations/0123_deprecate_legacy_order_creation_entrypoint.sql").read_text(encoding="utf-8")
        actions = (ROOT / "apps/web/app/pedidos/actions.ts").read_text(encoding="utf-8")

        self.assertIn("to_regprocedure", sql)
        self.assertIn(LEGACY_ENTRYPOINT, sql)
        self.assertIn("expected exactly public.create_com_pedido_operacional", sql)
        self.assertIn("from public, anon, authenticated", sql)
        self.assertIn("comment on function public.create_com_pedido_operacional", sql)
        self.assertIn("LEGADO ORD-01 Fase 0", sql)
        self.assertIn("Deixou de ser API operacional publica", sql)
        self.assertIn("fluxos canonicos governados", sql)
        self.assertNotIn("grant execute on function public.create_com_pedido_operacional", sql.lower())
        self.assertNotIn("createPedidoRascunhoAction", actions)
        self.assertNotIn('"create_com_pedido_operacional"', actions)
        self.assertIn('"create_com_pedido_vendedor_programado_idempotente"', actions)


if __name__ == "__main__":
    unittest.main()
