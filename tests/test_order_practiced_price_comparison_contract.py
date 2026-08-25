from pathlib import Path
import unittest


ROOT = Path(__file__).resolve().parents[1]
SQL = (ROOT / "supabase/migrations/0130_govern_order_practiced_price_facts.sql").read_text(encoding="utf-8")


class OrderPracticedPriceComparisonContractTests(unittest.TestCase):
    def test_practiced_price_facts_are_generic_append_only_and_default_deny(self) -> None:
        self.assertIn("com_pedido_item_precos_praticados", SQL)
        self.assertIn("com_pedido_preco_praticado_requisicoes", SQL)
        self.assertIn("pedidos.practiced_price.record", SQL)
        self.assertIn("pedidos.commercial_comparison.view", SQL)
        self.assertIn("default_allowed", SQL)
        self.assertIn("prevent_dec009_fact_changes", SQL)
        self.assertIn("revoke all on table public.com_pedido_item_precos_praticados", SQL)
        self.assertIn("grant select on public.com_pedido_item_precos_praticados to authenticated", SQL)
        self.assertNotIn("grant select on public.com_pedido_preco_praticado_requisicoes to authenticated", SQL)
        self.assertNotIn('create policy "governed read practiced price requests"', SQL)
        self.assertIn("preco praticado de venda deve ser maior que zero", SQL)

    def test_rpc_uses_only_the_frozen_generic_snapshot_contract(self) -> None:
        body = SQL.split("create or replace function public.registrar_com_precos_praticados_pedido_idempotente", 1)[1]
        self.assertIn("preco_referencia_centavos_por_unidade_precificacao", body)
        self.assertIn("quantidade_unidade_precificacao_por_apresentacao", body)
        self.assertIn("todos os itens de venda exigem referencia comercial generica congelada e materialmente coerente", body)
        self.assertIn("snapshot.produto_embalagem_id is distinct from item.produto_embalagem_id", body)
        self.assertIn("snapshot.cliente_id is distinct from v_pedido.cliente_id", body)
        self.assertIn("snapshot.data_comercial is distinct from v_pedido.data_pedido", body)
        self.assertIn("snapshot.origem_comercial_id is distinct from v_pedido.origem_comercial_id", body)
        self.assertNotIn("valor_unitario", body)
        self.assertNotIn("percentual_desconto", body)
        self.assertNotIn("valor_total", body)

    def test_snapshot_identity_and_idempotency_metadata_are_fail_closed(self) -> None:
        trigger = SQL.split("create or replace function public.validate_com_pedido_item_preco_praticado", 1)[1].split(
            "create trigger trg_com_pedido_item_precos_praticados_validate", 1
        )[0]
        self.assertIn("referencia comercial congelada diverge da identidade material do pedido", trigger)
        self.assertIn("v_snapshot.produto_embalagem_id is distinct from v_item.produto_embalagem_id", trigger)
        self.assertIn("v_snapshot.cliente_id is distinct from v_pedido.cliente_id", trigger)
        self.assertIn("v_snapshot.data_comercial is distinct from v_pedido.data_pedido", trigger)
        self.assertIn("v_snapshot.origem_comercial_id is distinct from v_pedido.origem_comercial_id", trigger)
        self.assertNotIn('create policy "governed read practiced price requests"', SQL)
        self.assertNotIn("grant select on public.com_pedido_preco_praticado_requisicoes to authenticated", SQL)

    def test_comparison_preserves_item_discount_visibility_and_reconcilable_totals(self) -> None:
        self.assertIn("classificacao in ('BELOW_REFERENCE', 'AT_REFERENCE', 'ABOVE_REFERENCE')", SQL)
        self.assertIn("sum(abs(impacto_financeiro_centavos)) filter (where impacto_financeiro_centavos < 0)", SQL)
        self.assertIn("sum(impacto_financeiro_centavos) filter (where impacto_financeiro_centavos > 0)", SQL)
        self.assertIn("sum(impacto_financeiro_centavos)", SQL)
        self.assertIn("round(", SQL)
        self.assertIn("percentual_resultado_liquido", SQL)

    def test_public_api_is_idempotent_and_sale_only(self) -> None:
        body = SQL.split("create or replace function public.registrar_com_precos_praticados_pedido_idempotente", 1)[1]
        self.assertIn("pg_advisory_xact_lock", body)
        self.assertIn("chave de idempotencia reutilizada com conteudo diferente", body)
        self.assertIn("pedido ja possui preco praticado imutavel", body)
        self.assertIn("preco praticado exige pedido de venda bloqueado", body)
