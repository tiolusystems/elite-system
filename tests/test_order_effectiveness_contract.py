from pathlib import Path
import unittest


ROOT = Path(__file__).resolve().parents[1]
MIGRATION = ROOT / "supabase/migrations/0135_govern_order_effectiveness.sql"
SMOKE = ROOT / "tests/sql/order_effectiveness.sql"


class OrderEffectivenessContractTests(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        cls.migration = MIGRATION.read_text(encoding="utf-8")
        cls.smoke = SMOKE.read_text(encoding="utf-8")

    def test_effectiveness_is_sale_only_and_immutable(self):
        for phrase in (
            "pedido_efetivado_em",
            "v_order.tipo_pedido <> 'venda'",
            "clock_timestamp()",
            "data de efetivacao do pedido e imutavel",
            "old.status = 'blocked' and new.status = 'open'",
        ):
            self.assertIn(phrase, self.migration)

    def test_all_current_version_gates_are_present(self):
        for phrase in (
            "current_f2b_version",
            "v_confirmation.comparacao_sha256",
            "v_credit.confirmacao_comercial_id = v_confirmation.id",
            "v_credit.documento_comercial_sha256 = v_confirmation.documento_canonico_sha256",
            "decision.decisao = 'ACCEPTED'",
            "decision.decisao = 'APPROVED'",
            "v_has_below",
            "effectiveness_recognized",
        ):
            self.assertIn(phrase, self.migration)

    def test_evaluator_is_private_and_query_is_scoped(self):
        self.assertIn("revoke all on function public.avaliar_com_pedido_efetividade(bigint)", self.migration)
        self.assertIn("public.can_current_user_view_order(p_pedido_id)", self.migration)
        self.assertIn("grant execute on function public.consultar_com_pedido_efetividade(bigint) to authenticated", self.migration)

    def test_effectiveness_state_and_audit_bind_exact_gate_facts(self):
        for phrase in (
            "credit_decision_id",
            "signature_evidence_id",
            "signature_decision_id",
            "discount_decision_id",
            "current_f2b_confirmation_id",
            "current_f2b_document_sha256",
            "last_condition_actor_id",
            "pedidos.pedido_efetivado",
            "v_previous_effectiveness_context",
            "coalesce(v_previous_effectiveness_context, '')",
        ):
            self.assertIn(phrase, self.migration)

    def test_governed_gate_rpcs_call_one_evaluator_without_after_insert_triggers(self):
        for wrapper in (
            "registrar_com_pedido_decisao_credito_impl_0135",
            "registrar_com_pedido_decisao_desconto_idempotente_impl_0135",
            "decidir_com_pedido_assinatura_idempotente_impl_0135",
        ):
            self.assertIn(wrapper, self.migration)
        self.assertEqual(self.migration.count("perform public.avaliar_com_pedido_efetividade("), 3)
        self.assertNotIn("after insert on public.com_pedido_credito_decisoes", self.migration)
        self.assertNotIn("after insert on public.com_pedido_decisoes_desconto", self.migration)
        self.assertNotIn("after insert on public.com_pedido_assinatura_decisoes", self.migration)

    def test_credit_path_preserves_authenticated_access_and_only_evaluator_opens_sale(self):
        self.assertIn(
            "grant execute on function public.registrar_com_pedido_decisao_credito(bigint, text, text, numeric, numeric, text)\n  to authenticated",
            self.migration,
        )
        wrapper_start = self.migration.index(
            "create or replace function public.registrar_com_pedido_decisao_credito("
        )
        wrapper_end = self.migration.index(
            "alter function public.registrar_com_pedido_decisao_desconto_idempotente(",
            wrapper_start,
        )
        wrapper = self.migration[wrapper_start:wrapper_end]
        self.assertNotIn("update public.com_pedidos", wrapper)
        self.assertLess(
            wrapper.index("v_decisao_id :="),
            wrapper.index("perform public.avaliar_com_pedido_efetividade(p_pedido_id)"),
        )

    def test_smoke_covers_order_independence_retry_and_bypasses(self):
        for phrase in (
            "fixture governada de F2B",
            "assinatura aceita sem credito",
            "Credito sem aprovacao F2C",
            "credito primeiro",
            "F2C rejeitado",
            "F2C + credito + assinatura nao abriu pedido",
            "Retry",
            "blocked -> open",
            "pedido_efetivado_em",
            "IDs exatos dos gates",
        ):
            self.assertIn(phrase, self.smoke)
        self.assertNotIn("session_replication_role", self.smoke)
        self.assertNotIn("insert into public.com_pedido_credito_decisoes", self.smoke)


if __name__ == "__main__":
    unittest.main()
