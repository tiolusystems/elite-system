from pathlib import Path
import unittest

ROOT = Path(__file__).resolve().parents[1]


class OrdersInventoryClarityContractTest(unittest.TestCase):
    def test_orders_do_not_show_global_lot_inventory(self):
        orders = (ROOT / "apps/web/app/pedidos/page.tsx").read_text(encoding="utf-8")
        for forbidden in ("Lotes com saldo", "Com reserva", "Disponibilidade comprometida", "Candidatos"):
            self.assertNotIn(forbidden, orders)

    def test_inventory_starts_with_contextual_filters_not_global_counters(self):
        inventory = (ROOT / "apps/web/app/producao/estoque/page.tsx").read_text(encoding="utf-8")
        self.assertNotIn('aria-label="Resumo dos lotes"', inventory)
        self.assertIn("Produto ou materia-prima", inventory)
        self.assertIn("Pesquise primeiro o produto", inventory)
        self.assertIn("Familia", inventory)
        self.assertIn("Apresentacoes do produto", inventory)


if __name__ == "__main__":
    unittest.main()
