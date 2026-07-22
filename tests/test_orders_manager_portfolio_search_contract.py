from pathlib import Path
import unittest


ROOT = Path(__file__).resolve().parents[1]


class OrdersManagerPortfolioSearchContractTest(unittest.TestCase):
    def test_manager_search_uses_team_scope_and_requires_query(self):
        sql = (ROOT / "supabase/migrations/0083_orders_manager_portfolio_search.sql").read_text(encoding="utf-8")
        self.assertIn("public.current_user_manages_seller(relation.pessoa_id)", sql)
        self.assertIn("char_length(trim(coalesce(p_busca, ''))) >= 2", sql)
        self.assertIn("revoke all on function public.consultar_com_carteira_clientes(text) from public, anon", sql)
        self.assertIn("grant execute on function public.consultar_com_carteira_clientes(text) to authenticated", sql)

    def test_page_does_not_preload_portfolio_and_filters_client_history(self):
        library = (ROOT / "apps/web/lib/orders.ts").read_text(encoding="utf-8")
        page = (ROOT / "apps/web/app/pedidos/page.tsx").read_text(encoding="utf-8")
        self.assertIn("normalizedSearch.length >= 2", library)
        self.assertIn("Digite pelo menos 2 letras", page)
        self.assertIn("order.clientId === selected.clientId", page)
        self.assertIn("clientes próprios e da equipe", page)


if __name__ == "__main__":
    unittest.main()
