from pathlib import Path
import unittest


ROOT = Path(__file__).resolve().parents[1]
MIGRATION = ROOT / "supabase/migrations/0133_govern_buyer_signature_evidence.sql"
MIGRATION_0134 = ROOT / "supabase/migrations/0134_freeze_sig01_canonical_terms.sql"
SMOKE = ROOT / "tests/sql/order_buyer_signature_evidence.sql"
PAGE = ROOT / "apps/web/app/pedidos/[id]/contrato/page.tsx"
PANEL = ROOT / "apps/web/app/pedidos/[id]/contrato/signature-evidence-panel.tsx"
ACTIONS = ROOT / "apps/web/app/pedidos/actions.ts"
ORDERS = ROOT / "apps/web/lib/orders.ts"
E2E = ROOT / "apps/web/e2e/buyer-signature-evidence.spec.mjs"


class OrderBuyerSignatureEvidenceContractTests(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        cls.migration = MIGRATION.read_text(encoding="utf-8")
        cls.migration_0134 = MIGRATION_0134.read_text(encoding="utf-8")
        cls.smoke = SMOKE.read_text(encoding="utf-8")
        cls.page = PAGE.read_text(encoding="utf-8")
        cls.panel = PANEL.read_text(encoding="utf-8")
        cls.actions = ACTIONS.read_text(encoding="utf-8")
        cls.orders = ORDERS.read_text(encoding="utf-8")
        cls.e2e = E2E.read_text(encoding="utf-8")

    def test_permissions_are_default_deny_and_artifacts_are_private(self):
        for key in ("pedidos.buyer_signature.view", "pedidos.buyer_signature.submit", "pedidos.buyer_signature.review"):
            self.assertIn(key, self.migration)
        self.assertIn("default_allowed, sort_order", self.migration)
        self.assertIn("values\n  ('pedidos.buyer_signature.view'", self.migration)
        self.assertIn("public = false", self.migration)
        self.assertIn("revoke all on public.com_pedido_assinatura_evidencias", self.migration)

    def test_evidence_and_decision_are_append_only_idempotent_and_bound(self):
        for phrase in ("prevent_dec009_fact_changes", "com_pedido_assinatura_evidencia_requisicoes", "com_pedido_assinatura_decisao_requisicoes", "documento_canonico_sha256", "versao comercial vigente", "pedido permanece bloqueado"):
            self.assertIn(phrase, self.migration)
        self.assertIn("chave de idempotencia reutilizada com payload divergente", self.migration)

    def test_email_is_not_acceptance_and_only_accepted_evidence_counts(self):
        self.assertIn("O e-mail corporativo cadastrado é canal de comunicação", self.page)
        self.assertIn("accepted", self.migration.lower())
        self.assertIn("PENDING", self.panel)
        self.assertIn("Aceitar evidência", self.panel)
        self.assertIn("pedido continua bloqueado", self.panel)

    def test_document_comes_from_f2b_without_credit_dependency(self):
        self.assertIn('consultar_com_pedido_documento_assinavel', self.orders)
        self.assertIn('pedidos.buyer_signature.view', self.migration)
        self.assertNotIn("com_pedido_credito_decisoes", self.migration.split("create or replace function public.consultar_com_pedido_documento_assinavel", 1)[1].split("create or replace function public.consultar_com_pedido_assinaturas", 1)[0])
        self.assertIn("documento comercial congelado", self.migration)
        workspace = self.orders.split("export async function getOrderSignatureWorkspace", 1)[1].split("export async function getOrderWorkspace", 1)[0]
        self.assertIn("canonicalClientName", workspace)
        self.assertNotIn('from("cad_clientes")', workspace)
        self.assertNotIn('from("cad_cliente_documentos")', workspace)
        self.assertIn('from("cad_cliente_contatos")', workspace)

    def test_smoke_covers_no_opening_direct_writes_and_retry(self):
        for phrase in ("documento SIG01 nao esta vinculado a F2B", "retry identico de evidencia", "aceite SIG01 abriu o pedido", "UPDATE", "TRUNCATE"):
            self.assertIn(phrase, self.smoke)

    def test_web_uses_server_mediated_upload_and_governed_rpcs(self):
        self.assertIn("createSupabaseAdminClient", self.actions)
        self.assertIn("order-signature-evidence", self.actions)
        self.assertIn("autorizar_com_pedido_assinatura_evidencia", self.actions)
        self.assertIn("registrar_com_pedido_assinatura_evidencia_idempotente", self.actions)
        self.assertIn("decidir_com_pedido_assinatura_idempotente", self.actions)
        self.assertIn("multipart/form-data", self.panel)
        self.assertIn("consultar_com_pedido_assinatura_artefato", self.orders)
        self.assertIn("createSignedUrl", self.orders)
        self.assertNotIn('value="integrated_api"', self.panel)
        self.assertNotIn('value="gov_br"', self.panel)
        self.assertNotIn("SHA-256:", self.panel)

    def test_manual_sources_and_review_justification_are_fail_closed(self):
        self.assertIn("p_fonte not in ('external_digital', 'physical_digitized')", self.migration)
        self.assertIn("p_decisao = 'REJECTED' and length", self.migration)

    def test_terms_are_frozen_and_upload_identity_is_deterministic(self):
        self.assertIn("'{schema_version}', '2'::jsonb", self.migration_0134)
        self.assertIn("'{termos}'", self.migration_0134)
        self.assertIn("documento comercial legado nao e assinavel", self.migration_0134)
        self.assertIn("pending/${actorId}/${idempotencyKey}/${artifactHash}", self.actions)
        self.assertNotIn("randomUUID", self.actions)
        self.assertIn("!storagePath", self.actions)

    def test_retry_cleanup_does_not_remove_preexisting_object(self):
        self.assertIn("objectCreatedByAttempt = false", self.actions)
        self.assertIn("objectCreatedByAttempt = true", self.actions)
        self.assertIn("if (objectCreatedByAttempt && storagePath", self.actions)
        self.assertIn("download(storagePath)", self.actions)

    def test_directed_browser_contract_checks_locked_document_and_overflow(self):
        self.assertIn("E2E_SIGNATURE_ORDER_ID", self.e2e)
        self.assertIn("Pedido permanece bloqueado", self.e2e)
        self.assertIn("scrollWidth", self.e2e)


if __name__ == "__main__":
    unittest.main()
