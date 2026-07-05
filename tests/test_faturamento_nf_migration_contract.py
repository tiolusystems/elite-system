from __future__ import annotations

import unittest
from pathlib import Path


REPO_ROOT = Path(__file__).resolve().parents[1]
MIGRATION_0025 = REPO_ROOT / "supabase" / "migrations" / "0025_faturamento_nf_contract.sql"
DECISION_DOC = REPO_ROOT / "docs" / "decisao_faturamento_notas_fiscais.md"
RECIPE_DOC = REPO_ROOT / "docs" / "receita_rls_rpc_auditada.md"


class FaturamentoNfMigrationContractTests(unittest.TestCase):
    def test_0025_adds_fiscal_event_axis_to_audit_helpers(self) -> None:
        text = MIGRATION_0025.read_text(encoding="utf-8")

        self.assertIn("alter type public.audit_axis add value if not exists 'fiscal_event'", text)
        self.assertIn("'fiscal_event'", text)
        self.assertIn("create or replace function public.normalize_audit_axis", text)

    def test_0025_creates_fiscal_tables_with_explicit_references(self) -> None:
        text = MIGRATION_0025.read_text(encoding="utf-8")

        self.assertIn("create table if not exists public.fat_notas_fiscais", text)
        self.assertIn("create table if not exists public.fat_nota_fiscal_itens", text)
        self.assertIn("create table if not exists public.fat_nota_fiscal_eventos", text)
        self.assertIn("nota_pai_id bigint references public.fat_notas_fiscais", text)
        self.assertIn("nota_complementada_id bigint references public.fat_notas_fiscais", text)
        self.assertIn("romaneio_item_id bigint references public.exp_romaneio_itens", text)
        self.assertNotIn("nota_referenciada_id", text)

    def test_0025_type_checks_distinguish_modalities(self) -> None:
        text = MIGRATION_0025.read_text(encoding="utf-8")

        for fiscal_type in ("remessa_total", "simples_faturamento", "remessa_vinculada", "complementar"):
            self.assertIn(fiscal_type, text)

        self.assertIn("tipo = 'remessa_total'", text)
        self.assertIn("tipo = 'simples_faturamento'", text)
        self.assertIn("tipo = 'remessa_vinculada'", text)
        self.assertIn("tipo = 'complementar'", text)
        self.assertIn("nota_pai_id is null", text)
        self.assertIn("nota_complementada_id is not null", text)

    def test_0025_emission_rpc_uses_audited_contract_and_quantity_guards(self) -> None:
        text = MIGRATION_0025.read_text(encoding="utf-8")

        self.assertIn("create or replace function public.emitir_fat_nota_fiscal", text)
        self.assertIn("public.begin_audited_rpc(", text)
        self.assertIn("'faturamento.nf.issue'", text)
        self.assertIn("'fiscal_event'", text)
        self.assertIn("fiscal commercial quantity exceeds order item quantity", text)
        self.assertIn("linked remittance quantity exceeds parent simple invoice quantity", text)
        self.assertIn("romaneio_item_id is required for fiscal invoice from cargo", text)
        self.assertIn("fiscal item quantity must match confirmed romaneio item quantity", text)
        self.assertIn("romaneio item already has active fiscal document", text)
        self.assertIn("perform public.log_audited_rpc_change(", text)

    def test_0025_event_rpc_validates_payload_contract(self) -> None:
        text = MIGRATION_0025.read_text(encoding="utf-8")

        self.assertIn("create or replace function public.fat_validate_event_payload", text)
        self.assertIn("payload_json for emitida requires protocolo_autorizacao and ambiente", text)
        self.assertIn("payload_json for cancelada requires protocolo_cancelamento and justificativa", text)
        self.assertIn("payload_json for carta_correcao requires sequencia_cce and texto_correcao", text)
        self.assertIn("create or replace function public.registrar_fat_nota_fiscal_evento", text)
        self.assertIn("'faturamento.nf.cancel'", text)
        self.assertIn("'faturamento.nf.correct'", text)
        self.assertIn("'faturamento.nf.substitute'", text)
        self.assertIn("'faturamento.nf.complement'", text)

    def test_0025_exposes_dossier_and_coverage_views(self) -> None:
        text = MIGRATION_0025.read_text(encoding="utf-8")

        self.assertIn("create or replace view public.fat_pedido_item_cobertura_fiscal", text)
        self.assertIn("with (security_invoker = true)", text)
        self.assertIn("quantidade_faturada", text)
        self.assertIn("quantidade_remetida_fiscal", text)
        self.assertIn("nf.tipo in ('remessa_total', 'simples_faturamento', 'complementar')", text)
        self.assertIn("nf.tipo in ('remessa_total', 'remessa_vinculada')", text)
        self.assertIn("create or replace view public.fat_pedido_dossie_fiscal", text)

    def test_0025_blocks_direct_writes_and_uses_rls_read_policies(self) -> None:
        text = MIGRATION_0025.read_text(encoding="utf-8")

        self.assertIn("alter table public.fat_notas_fiscais enable row level security", text)
        self.assertIn("public.current_actor_id() is not null", text)
        self.assertIn("revoke insert, update, delete on", text)
        self.assertIn("grant execute on function public.emitir_fat_nota_fiscal", text)
        self.assertIn("grant execute on function public.registrar_fat_nota_fiscal_evento", text)

    def test_docs_match_migration_integrity_contract(self) -> None:
        decision = DECISION_DOC.read_text(encoding="utf-8")
        recipe = RECIPE_DOC.read_text(encoding="utf-8")
        combined = f"{decision}\n{recipe}"

        self.assertIn("quantidade faturada comercialmente", combined)
        self.assertIn("quantidade remetida fisicamente", combined)
        self.assertIn("RPC deve bloquear excesso", combined)
        self.assertIn("romaneio_item_id", combined)


if __name__ == "__main__":
    unittest.main()
