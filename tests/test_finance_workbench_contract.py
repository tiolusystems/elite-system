from pathlib import Path
import unittest

ROOT = Path(__file__).resolve().parents[1]


class FinanceWorkbenchContractTests(unittest.TestCase):
    def test_finance_route_uses_governed_rpcs(self):
        actions = (ROOT / "apps/web/app/pedidos/financeiro/actions.ts").read_text(encoding="utf-8")
        for rpc in (
            "definir_com_pedido_comissao_idempotente",
            "registrar_com_recebimento_idempotente",
            "registrar_fin_comissao_pagamento_idempotente",
            "registrar_fin_comissao_ajuste_idempotente",
        ):
            self.assertIn(f'await auditedRpc(supabase, "{rpc}"', actions)
        self.assertNotIn('.from("com_recebimentos").insert', actions)
        self.assertNotIn('.from("fin_comissao_movimentos").insert', actions)

    def test_finance_route_is_navigable_and_documented(self):
        navigation = (ROOT / "apps/web/lib/app-navigation.ts").read_text(encoding="utf-8")
        manuals = (ROOT / "apps/web/lib/manuals.ts").read_text(encoding="utf-8")
        page = (ROOT / "apps/web/app/pedidos/financeiro/page.tsx").read_text(encoding="utf-8")
        self.assertIn('{ href: "/pedidos/financeiro", label: "Financeiro", moduleKey: "financeiro" }', navigation)
        self.assertIn('manual("/pedidos/financeiro"', manuals)
        self.assertIn("Registrar recebimento", page)
        self.assertIn("Definir comissionados da venda", page)
        self.assertIn("Conta corrente de comissoes", page)
        self.assertIn("Ajuste manual de comissao", page)

    def test_user_facing_finance_statuses_are_translated(self):
        page = (ROOT / "apps/web/app/pedidos/financeiro/page.tsx").read_text(encoding="utf-8")
        for internal in ("credito_liberacao", "debito_pagamento", "debito_estorno", "compensacao_futura", "ajuste_manual"):
            self.assertIn(f"{internal}:", page)
        self.assertIn("Comissao liberada", page)
        self.assertIn("Compensacao futura", page)


if __name__ == "__main__":
    unittest.main()
