from pathlib import Path
import unittest

ROOT = Path(__file__).resolve().parents[1]


class StockServerPaginationContractTest(unittest.TestCase):
    def test_database_query_is_paginated_and_permission_scoped(self):
        sql = (ROOT / "supabase/migrations/0081_stock_server_search_pagination.sql").read_text(encoding="utf-8")
        self.assertIn("p_limite integer default 24", sql)
        self.assertIn("limit v_limite offset v_offset", sql)
        self.assertIn("count(*) over ()", sql)
        for action in ("estoque.mp.view", "estoque.pa.view", "estoque.pi.view"):
            self.assertIn(action, sql)
        self.assertIn("from public, anon", sql)

    def test_screen_uses_server_workspace_not_full_pcp_dashboard(self):
        page = (ROOT / "apps/web/app/producao/estoque/page.tsx").read_text(encoding="utf-8")
        service = (ROOT / "apps/web/lib/stock.ts").read_text(encoding="utf-8")
        self.assertIn("getTargetStockLots", page)
        self.assertNotIn("getPcpDashboard", page)
        self.assertIn("p_limite: pageSize", service)
        self.assertIn("if (!query.search.trim())", service)
        self.assertIn("Pesquise primeiro o produto", page)
        self.assertIn("required", page)
        self.assertIn("Anterior", page)
        self.assertIn("Proxima", page)

    def test_product_packaging_lot_drilldown(self):
        sql = (ROOT / "supabase/migrations/0082_stock_product_packaging_drilldown.sql").read_text(encoding="utf-8")
        page = (ROOT / "apps/web/app/producao/estoque/page.tsx").read_text(encoding="utf-8")
        for function in ("consultar_est_estoque_produtos", "consultar_est_estoque_apresentacoes", "consultar_est_estoque_lotes_alvo"):
            self.assertIn(function, sql)
        self.assertIn("inventory-product-card", page)
        self.assertIn("Apresentacoes do produto", page)
        self.assertIn("effectiveTarget", page)


if __name__ == "__main__":
    unittest.main()
