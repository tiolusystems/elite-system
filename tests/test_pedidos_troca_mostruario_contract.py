from __future__ import annotations

import re
import unittest
from pathlib import Path


REPO_ROOT = Path(__file__).resolve().parents[1]
MIGRATION_0030 = REPO_ROOT / "supabase" / "migrations" / "0030_pedidos_troca_mostruario_contract.sql"
PEDIDOS_ACTIONS = REPO_ROOT / "apps" / "web" / "app" / "pedidos" / "actions.ts"
PEDIDOS_PAGE = REPO_ROOT / "apps" / "web" / "app" / "pedidos" / "page.tsx"
ORDERS_LIB = REPO_ROOT / "apps" / "web" / "lib" / "orders.ts"
COMMISSIONS_DOC = REPO_ROOT / "docs" / "escopo_comissoes_recebimentos_credito.md"
VALIDATION_DOC = REPO_ROOT / "docs" / "validacao_pedidos_lifecycle_audit_contract.md"


class PedidosTrocaMostruarioContractTests(unittest.TestCase):
    def test_0030_extends_order_types_and_origin_links(self) -> None:
        text = MIGRATION_0030.read_text(encoding="utf-8")

        self.assertIn("'troca'", text)
        self.assertIn("'mostruario'", text)
        self.assertIn("pedido_origem_id bigint references public.com_pedidos(id)", text)
        self.assertIn("pedido_item_origem_id bigint references public.com_pedido_itens(id)", text)
        self.assertIn("com_pedidos_troca_origem_check", text)
        self.assertIn("com_pedido_itens_troca_origem_check", text)

    def test_generic_create_allows_mostruario_but_not_troca(self) -> None:
        body = self._function_body("create_com_pedido_operacional")

        self.assertIn("p_tipo_pedido = 'troca'", body)
        self.assertIn("use create_com_pedido_troca for exchange orders", body)
        self.assertIn("'mostruario'", body)
        self.assertIn("p_tipo_pedido in ('bonificacao', 'mostruario')", body)
        self.assertIn("p_tipo_pedido = 'venda'", body)
        self.assertNotIn("p_tipo_pedido <> 'bonificacao'", body)

    def test_exchange_rpc_uses_audited_contract_and_locks_origin(self) -> None:
        body = self._function_body("create_com_pedido_troca")

        self.assertIn("pedidos.exchange.create", body)
        self.assertIn("public.begin_audited_rpc(", body)
        self.assertIn("perform public.log_audited_rpc_change(", body)
        self.assertIn("'change_type'", body)
        self.assertIn("from public.com_pedidos", body)
        self.assertIn("from public.com_pedido_itens", body)
        self.assertIn("for update", body)
        self.assertIn("exchange quantity exceeds original item quantity", body)
        self.assertIn("pedido_origem_id", body)
        self.assertIn("pedido_item_origem_id", body)
        self.assertIn("motivo_troca", body)
        self.assertNotIn("insert into public.com_pedido_comissionados", body)

    def test_web_layer_exposes_mostruario_and_exchange_action(self) -> None:
        actions = PEDIDOS_ACTIONS.read_text(encoding="utf-8")
        page = PEDIDOS_PAGE.read_text(encoding="utf-8")
        orders = ORDERS_LIB.read_text(encoding="utf-8")

        self.assertIn('"mostruario"', actions)
        self.assertIn("criarTrocaPedidoAction", actions)
        self.assertIn('action_key: "pedidos.exchange.create"', actions)
        self.assertIn('axis: "change_type"', actions)
        self.assertIn('failure_action: "pedidos.exchange_create_failed"', actions)
        self.assertIn('<option value="mostruario">mostruario</option>', page)
        self.assertIn('id="troca-pedido"', page)
        self.assertIn("pedidoItens", orders)
        self.assertIn("com_pedido_itens", orders)

    def test_docs_record_0030_scope(self) -> None:
        commissions_doc = COMMISSIONS_DOC.read_text(encoding="utf-8")
        validation_doc = VALIDATION_DOC.read_text(encoding="utf-8")

        self.assertIn("Troca e mostruario", commissions_doc)
        self.assertIn("mostruario nao gera comissao", commissions_doc)
        self.assertIn("troca exige pedido e item de origem", commissions_doc)
        self.assertIn("0030_pedidos_troca_mostruario_contract.sql", validation_doc)
        self.assertIn("PG_VALIDATE_0030_WITH_SMOKE_OK", validation_doc)

    def _function_body(self, function_name: str) -> str:
        text = MIGRATION_0030.read_text(encoding="utf-8")
        pattern = re.compile(
            rf"create or replace function public\.{re.escape(function_name)}\b.*?\n\$\$;",
            re.DOTALL | re.IGNORECASE,
        )
        match = pattern.search(text)
        self.assertIsNotNone(match, f"Function {function_name} not found")
        return match.group(0).lower()


if __name__ == "__main__":
    unittest.main()
