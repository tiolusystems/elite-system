from pathlib import Path
import unittest


ROOT = Path(__file__).resolve().parents[1]
SQL = (ROOT / "supabase/migrations/0131_govern_seller_commercial_confirmation.sql").read_text(encoding="utf-8")
ACTIONS = (ROOT / "apps/web/app/pedidos/actions.ts").read_text(encoding="utf-8")
ENTRY = (ROOT / "apps/web/app/pedidos/order-entry-editor.tsx").read_text(encoding="utf-8")
REVIEW = (ROOT / "apps/web/app/pedidos/order-commercial-review.tsx").read_text(encoding="utf-8")
CSS = (ROOT / "apps/web/app/globals.css").read_text(encoding="utf-8")
E2E_BOOTSTRAP = (ROOT / "apps/web/e2e/bootstrap-synthetic-users.mjs").read_text(encoding="utf-8")
E2E_SPEC = (ROOT / "apps/web/e2e/order-commercial-review.spec.mjs").read_text(encoding="utf-8")


class OrderSellerCommercialConfirmationContractTests(unittest.TestCase):
    def test_confirmation_anchor_is_append_only_default_deny_and_signature_ready(self) -> None:
        self.assertIn("com_pedido_confirmacoes_comerciais", SQL)
        self.assertIn("com_pedido_confirmacao_comercial_requisicoes", SQL)
        self.assertIn("pedidos.commercial_review.preview", SQL)
        self.assertIn("pedidos.commercial_review.confirm", SQL)
        self.assertIn("default_allowed", SQL)
        self.assertIn("prevent_dec009_fact_changes", SQL)
        self.assertIn("revoke all on public.com_pedido_confirmacoes_comerciais", SQL)
        self.assertIn("documento_canonico_sha256", SQL)
        self.assertIn("Futuras aprovacoes e assinaturas devem referenciar este hash e a confirmacao", SQL)

    def test_preview_is_non_persistent_and_final_confirmation_is_atomic(self) -> None:
        preview_body = SQL.split("create or replace function public.com_revisao_comercial_venda_calcular", 1)[1].split(
            "create or replace function public.prever_com_revisao_comercial_venda", 1
        )[0]
        self.assertNotIn("insert into public.com_pedidos", preview_body)
        self.assertNotIn("insert into public.com_pedido_confirmacoes_comerciais", preview_body)
        self.assertIn("preview_hash", preview_body)
        final_body = SQL.split("create or replace function public.confirmar_com_revisao_comercial_venda_idempotente", 1)[1].split(
            "create or replace function public.consultar_com_confirmacao_comercial_pedido", 1
        )[0]
        self.assertIn("create_com_pedido_vendedor_programado_idempotente", final_body)
        self.assertIn("replace_com_pedido_condicao_financeira_idempotente", final_body)
        self.assertIn("resolver_com_referencias_comerciais_pedido_idempotente", final_body)
        self.assertIn("registrar_com_precos_praticados_pedido_idempotente", final_body)
        self.assertIn("com_revisao_comercial_venda_comparacao_esperada", final_body)
        self.assertIn("com_revisao_comercial_venda_comparacao_persistida", final_body)
        self.assertIn("v_comparacao_esperada_hash is distinct from v_comparacao_persistida_hash", final_body)
        self.assertLess(
            final_body.index("v_comparacao_esperada_hash is distinct from v_comparacao_persistida_hash"),
            final_body.index("insert into public.com_pedido_confirmacoes_comerciais"),
        )
        self.assertIn("insert into public.com_pedido_confirmacoes_comerciais", final_body)
        self.assertIn("previsualizacao comercial desatualizada", final_body)

    def test_manager_credit_path_cannot_open_a_sale(self) -> None:
        manager_body = SQL.split("create or replace function public.registrar_com_pedido_decisao_credito", 1)[1]
        self.assertIn("v_pedido.status <> 'blocked'", manager_body)
        self.assertIn("venda exige revisao comercial confirmada", manager_body)
        self.assertIn("'blocked', 'blocked'", manager_body)
        self.assertIn("pedido_permanece_bloqueado", manager_body)
        self.assertNotIn("update public.com_pedidos set status = 'open'", manager_body)

    def test_web_uses_database_preview_and_confirmation_without_legacy_price_source(self) -> None:
        self.assertIn('"prever_com_revisao_comercial_venda"', ACTIONS)
        self.assertIn('"confirmar_com_revisao_comercial_venda_idempotente"', ACTIONS)
        self.assertNotIn('"create_com_pedido_vendedor_programado_idempotente"', ACTIONS)
        self.assertIn("previewFingerprint !== proposalFingerprint", ENTRY)
        self.assertIn("parseCommercialReviewPreview", ENTRY)
        self.assertIn("Confirmar condições comerciais", ENTRY)
        self.assertNotIn("valor_unitario", ENTRY)

    def test_discount_stays_visible_with_separate_order_totals_and_mobile_layout(self) -> None:
        self.assertIn("Este pedido contém item abaixo da referência", REVIEW)
        self.assertIn("resultado líquido total é positivo", REVIEW)
        self.assertIn("Descontos brutos", REVIEW)
        self.assertIn("Acima da referência", REVIEW)
        self.assertIn("Percentual líquido ponderado", REVIEW)
        self.assertIn("confirmo que estou solicitando os descontos apresentados", REVIEW.lower())
        self.assertIn(".commercial-review-items", CSS)
        self.assertIn("@media (max-width: 560px)", CSS)
        self.assertIn(
            ".commercial-review-items dl, .commercial-item-result, .commercial-order-summary { grid-template-columns: 1fr; }",
            CSS,
        )
        self.assertIn(".commercial-participant-options { grid-template-columns: 1fr; }", CSS)

    def test_directed_browser_fixture_uses_atomic_permissions_and_five_viewports(self) -> None:
        self.assertIn('"pedidos.commercial_review."', E2E_BOOTSTRAP)
        self.assertIn('"pedidos.practiced_price.record"', E2E_BOOTSTRAP)
        self.assertIn("Cliente Revisao Comercial E2E", E2E_BOOTSTRAP)
        self.assertIn("Este pedido contém item abaixo da referência", E2E_SPEC)
        self.assertIn('testInfo.project.name === "desktop-1920"', E2E_SPEC)
        self.assertIn("assertNoHorizontalOverflow", E2E_SPEC)


if __name__ == "__main__":
    unittest.main()
