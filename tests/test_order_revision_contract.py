from pathlib import Path
import unittest


ROOT = Path(__file__).resolve().parents[1]
MIGRATION = ROOT / "supabase/migrations/0136_govern_order_revisions_and_addenda.sql"
SMOKE = ROOT / "tests/sql/order_revision_and_addendum.sql"
STATE = ROOT / "docs/01_ESTADO_ATUAL.md"
AGENTS = ROOT / "AGENTS.md"
BOOTSTRAP = ROOT / "docs/agent-protocol/CHATGPT_PROJECT_BOOTSTRAP.md"


class OrderRevisionContractTests(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        cls.migration = MIGRATION.read_text(encoding="utf-8")
        cls.smoke = SMOKE.read_text(encoding="utf-8")
        cls.state = STATE.read_text(encoding="utf-8")
        cls.agents = AGENTS.read_text(encoding="utf-8")
        cls.bootstrap = BOOTSTRAP.read_text(encoding="utf-8")

    def test_schema_and_hash_chain(self):
        for phrase in (
            "com_pedido_contrato_geneses",
            "com_pedido_revisoes_governadas",
            "com_pedido_revisao_eventos",
            "base_contract_state_sha256",
            "delta_sha256",
            "resulting_contract_state_sha256",
            "base_sequence",
            "base_event_id",
            "contract_state_sha256",
            "cadeia contratual inconsistente",
            "after update of pedido_efetivado_em on public.com_pedidos",
            "effective_f2b_document_sha256",
            "f2a_fact_ids",
            "financial_plan_id",
        ):
            self.assertIn(phrase, self.migration)

    def test_pre_and_post_effectiveness_boundaries(self):
        self.assertIn("v_order.pedido_efetivado_em is null then 'pre_efetivacao' else 'aditivo'", self.migration)
        self.assertIn("nova versao comercial aguarda os gates vinculados a revisao", self.migration)
        self.assertIn("aditivo pos-efetivacao", self.migration)
        self.assertIn("pedido_efetivado_em", self.migration)

    def test_impact_mask_is_database_authority(self):
        for dimension in ("pricing", "discount", "financial", "buyer_signature", "commercial_resolution"):
            self.assertIn(f"'{dimension}'", self.migration)
        self.assertIn("ord01_apply_com_pedido_contract_delta(v_state->'contract_state', p_delta_json)", self.migration)
        self.assertIn("ord01_revision_impact_mask(v_state->'contract_state', v_result)", self.migration)
        self.assertIn("campo de delta contratual nao governado", self.migration)
        self.assertIn("delta de revisao sem efeito material", self.migration)
        self.assertNotIn("p_impact_mask text[]", self.migration)

    def test_active_revision_idempotency_and_scope(self):
        for phrase in (
            "pedido ja possui revisao material ativa",
            "chave de idempotencia reutilizada com conteudo diferente",
            "pg_advisory_xact_lock(hashtextextended(concat('ord01-revision:'",
            "can_current_user_view_order(p_pedido_id)",
            "for update",
        ):
            self.assertIn(phrase, self.migration)

    def test_default_deny_and_append_only(self):
        for phrase in (
            "before update or delete on public.com_pedido_contrato_geneses",
            "before update or delete on public.com_pedido_revisoes_governadas",
            "before update or delete on public.com_pedido_revisao_eventos",
            "revoke all on public.com_pedido_revisoes_governadas from public, anon, authenticated",
            "grant execute on function public.consultar_com_pedido_contrato_vigente(bigint) to authenticated",
            "grant execute on function public.encerrar_com_pedido_revisao_idempotente(uuid,bigint,text,text) to authenticated",
        ):
            self.assertIn(phrase, self.migration)

    def test_downstream_capability_fails_closed(self):
        self.assertIn("dimensao impactada sem consumidor downstream suportado", self.migration)
        self.assertIn("base contratual obsoleta; aditivo recusado", self.migration)
        self.assertIn("unsupported_dimensions", self.migration)

    def test_projection_is_read_only_and_genesis_is_write_path_only(self):
        resolver_body = self.migration.split("create or replace function public.resolver_com_pedido_contrato_vigente", 1)[1].split("create or replace function public.consultar_com_pedido_contrato_vigente", 1)[0]
        self.assertIn("stable", resolver_body)
        self.assertNotIn("materializar_com_pedido_contrato_genese", resolver_body)
        self.assertIn("UNRESOLVABLE: contrato genese nao materializado", self.migration)
        request_body = self.migration.split("create or replace function public.solicitar_com_pedido_revisao_idempotente", 1)[1]
        self.assertIn("perform public.materializar_com_pedido_contrato_genese", request_body)

    def test_lifecycle_and_versioned_fact_bindings(self):
        for phrase in (
            "evento in ('requested','pending','rejected','effective')",
            "revisao_id bigint references public.com_pedido_revisoes_governadas",
            "com_pedido_item_referencias_version_key",
            "com_pedido_item_precos_version_key",
            "com_pedido_item_precos_reference_version_key",
            "create or replace function public.encerrar_com_pedido_revisao_idempotente",
            "create or replace function public.materializar_com_pedido_revisao_pre_efetiva",
            "elite.revision_materialization",
            "com_pedido_revisao_itens",
            "com_pedido_revisao_materializacoes",
            "revisao_item_id",
            "fato de preco praticado diverge do item comercial resultante",
            "revisao_id",
            "pedido ja possui revisao material ativa",
        ):
            self.assertIn(phrase, self.migration)

    def test_terminal_retry_binds_actor_revision_and_payload(self):
        body = self.migration.split("create or replace function public.encerrar_com_pedido_revisao_idempotente", 1)[1]
        for phrase in (
            "v_existing.actor_id is distinct from v_actor",
            "v_existing.revisao_id is distinct from p_revisao_id",
            "v_existing.payload_hash is distinct from v_payload_hash",
            "perform pg_advisory_xact_lock",
            "v_existing.evento <> 'rejected'",
        ):
            self.assertIn(phrase, body)

    def test_smoke_contract(self):
        for phrase in (
            "revision RPC must be default deny for anon",
            "financial alias was not canonicalized",
            "alias conflict was accepted",
            "incomplete nested replacement was accepted",
            "unmaterializable item quantity was accepted",
            "H1 nao materializou a quantidade comercial 100",
            "H2 nao foi ancorado exatamente em H1",
        ):
            self.assertIn(phrase, self.smoke)

    def test_final_versioned_overrides_are_activated_after_compatibility(self):
        activation = self.migration.rindex("Activate the version-aware overrides")
        for phrase in (
            "ord01_revision_current_pre_effective_state_versioned_0136",
            "ord01_revision_impact_mask_versioned_0136",
            "ord01_contract_genesis_state_draft_0136",
            "materializar_com_pedido_revisao_pre_efetiva",
            "ord01_revisao_pre_efetiva_gates",
        ):
            self.assertLess(self.migration.index(phrase), activation)

    def test_obsolete_0136_implementations_are_removed_after_activation(self):
        activation = self.migration.rindex("Activate the version-aware overrides")
        cleanup = self.migration[activation:]
        for signature in (
            "ord01_revision_current_pre_effective_state_draft_0136(bigint)",
            "ord01_revision_impact_mask_draft_0136(jsonb, jsonb)",
            "ord01_contract_genesis_state_draft_legacy_0136(bigint)",
            "materializar_com_pedido_contrato_genese_draft_0136(bigint)",
            "validate_com_pedido_confirmacao_comercial_draft_0136()",
            "materializar_com_pedido_revisao_pre_efetiva_draft_0136(bigint)",
            "ord01_revision_current_contract_state_draft_0136(bigint)",
            "solicitar_com_pedido_revisao_idempotente_draft_0136(uuid, bigint, jsonb)",
            "efetivar_com_pedido_revisao_idempotente_draft_0136(uuid, bigint, jsonb)",
        ):
            self.assertIn(f"drop function public.{signature};", cleanup)
        self.assertIn("obsolete 0136 draft implementation remains in pg_proc", self.smoke)

    def test_internal_materializers_are_private_and_governed_rpc_still_materializes(self):
        for signature in (
            "materializar_com_pedido_revisao_pre_efetiva(bigint)",
            "materializar_com_pedido_contrato_genese(bigint)",
        ):
            self.assertIn(
                f"revoke all on function public.{signature} from public, anon, authenticated;",
                self.migration,
            )
            self.assertIn(f"has_function_privilege('authenticated', 'public.{signature}', 'EXECUTE')", self.smoke)
        self.assertIn("aclexplode(coalesce(proc.proacl, acldefault('f', proc.proowner)))", self.smoke)
        self.assertIn("privilege.grantee = 0", self.smoke)
        self.assertIn("privilege.privilege_type = 'EXECUTE'", self.smoke)
        self.assertNotIn("has_function_privilege('public'", self.smoke)
        self.assertIn("perform public.materializar_com_pedido_revisao_pre_efetiva(v_revision_id)", self.smoke)
        self.assertIn("exception when insufficient_privilege then null", self.smoke)
        self.assertIn("v_projection jsonb;", self.smoke)

    def test_h0_remains_the_original_base_and_post_effective_chain_includes_h1(self):
        genesis = self.migration.split(
            "create or replace function public.ord01_contract_genesis_state_draft_0136", 1
        )[1].split("create or replace function public.materializar_com_pedido_contrato_genese", 1)[0]
        self.assertIn("H0 is the immutable original commercial baseline", genesis)
        self.assertIn("ord01_revision_current_pre_effective_state(p_pedido_id)", genesis)
        post_effective = self.migration.split(
            "select * into v_genesis from public.com_pedido_contrato_geneses", 1
        )[1].split("return jsonb_build_object(", 1)[0]
        self.assertIn("revision.tipo in ('pre_efetivacao', 'aditivo')", post_effective)
        self.assertIn("cadeia contratual sem materializacao versionada", post_effective)

    def test_result_state_requires_complete_f2b_and_exact_revision_item_facts(self):
        for phrase in (
            "documento F2B resultante diverge da comparacao comercial completa",
            "parcelas resultantes nao reconciliam o valor financeiro",
            "parcelas resultantes divergem do PMP",
            "ord01_comparacao_original_persistida",
            "fato de preco praticado diverge do item comercial resultante",
            "referencia comercial versionada diverge do item comercial resultante",
        ):
            self.assertIn(phrase, self.migration)

    def test_versioned_effectuation_uses_exact_facts_not_latest_global_fact(self):
        effectuation = self.migration.split(
            "create or replace function public.efetivar_com_pedido_revisao_idempotente", 1
        )[1].split("create or replace function public.ord01_contract_genesis_state_draft_0136", 1)[0]
        for phrase in (
            "ord01_revisao_pre_efetiva_gates(p_revisao_id)",
            "v_revision.base_contract_state_sha256",
            "revision_effectuation_required",
            "elite.effectiveness_context",
            "evento_efetivo_id",
        ):
            self.assertIn(phrase, effectuation + self.migration)

    def test_handoff_contract(self):
        self.assertIn("Handoff entre conversas", self.agents)
        self.assertIn("Recuperacao de nova conversa", self.bootstrap)
        self.assertIn("Estado vigente em 2026-08-24", self.state)
        self.assertIn("o smoke comportamental `order_revision_and_addendum.sql` foram aprovados", self.state)


if __name__ == "__main__":
    unittest.main()
