from pathlib import Path
import unittest


ROOT = Path(__file__).resolve().parents[1]
MIGRATION = ROOT / "supabase" / "migrations" / "0069_pcp_mapa_packaging_order_foundation.sql"
COMPLETION_MIGRATION = ROOT / "supabase" / "migrations" / "0070_pcp_packaging_reservation_completion.sql"
ADR = ROOT / "docs" / "decisoes-arquiteturais" / "ADR-014-fluxo-pi-cq-pa-op-mapa.md"
WEB = ROOT / "apps" / "web"


class PcpMapaPackagingOrderContractTests(unittest.TestCase):
    def test_mapa_op_and_packaging_order_are_distinct_and_atomic(self) -> None:
        text = MIGRATION.read_text(encoding="utf-8")

        self.assertIn("create table public.pcp_ordens_envase", text)
        self.assertIn("op_mapa_id bigint not null unique", text)
        self.assertIn("public.create_pcp_op(", text)
        self.assertIn("'mapa_documental'", text)
        self.assertIn("insert into public.pcp_ordens_envase", text)

    def test_generic_op_creation_rejects_orphan_mapa_document(self) -> None:
        text = MIGRATION.read_text(encoding="utf-8")
        self.assertIn("MAPA documentary OP must be emitted with its packaging order", text)
        self.assertIn("rename to create_pcp_op_operational_impl_0069", text)
        self.assertIn("public.create_pcp_op_operational_impl_0069", text)

    def test_emission_requires_released_pi_and_matching_product(self) -> None:
        text = MIGRATION.read_text(encoding="utf-8")

        self.assertIn("PI lot is not released by CQ", text)
        self.assertIn("insufficient available PI balance after issued packaging orders", text)
        self.assertIn("pcp_envase_volume_pi_disponivel", text)
        self.assertIn("MAPA formula, PI lot and product presentation must reference the same product", text)
        self.assertIn("active MAPA formula version not found", text)

    def test_packaging_bom_is_governed_and_snapshotted(self) -> None:
        text = MIGRATION.read_text(encoding="utf-8")

        self.assertIn("cad_embalagem_configuracoes_atuais", text)
        self.assertIn("cad_embalagem_componentes_atuais", text)
        self.assertIn("quantidade_un_l * p_volume_planejado_l", text)
        self.assertIn("whole number of finished packages", text)

    def test_direct_writes_and_anonymous_access_are_denied(self) -> None:
        text = MIGRATION.read_text(encoding="utf-8")

        for table in ("pcp_ordens_envase", "pcp_ordem_envase_embalagens"):
            self.assertIn(f"revoke all on public.{table} from public, anon;", text)
            self.assertIn(
                f"revoke insert, update, delete, truncate on public.{table} from authenticated;",
                text,
            )
        self.assertIn("public.begin_audited_rpc", text)
        self.assertIn("public.log_audited_rpc_change", text)

    def test_physical_signatures_and_global_session_ownership_are_explicit(self) -> None:
        text = ADR.read_text(encoding="utf-8")

        self.assertIn("assinatura física dos operadores", text)
        self.assertIn("um único usuário autenticado", text)
        self.assertIn("Segurança/Sessões", text)
        self.assertNotIn("cada aprovador utiliza sua própria conta", text)

    def test_foundation_does_not_move_stock_prematurely(self) -> None:
        text = MIGRATION.read_text(encoding="utf-8")

        self.assertNotIn("insert into public.est_movimentos_mp", text)
        self.assertNotIn("insert into public.est_movimentos_pi", text)
        self.assertNotIn("insert into public.est_movimentos_pa", text)

    def test_completion_requires_full_reservations_and_generates_pa(self) -> None:
        text = COMPLETION_MIGRATION.read_text(encoding="utf-8")

        self.assertIn("create table public.pcp_ordem_envase_reservas", text)
        self.assertIn("packaging reservations must match every planned component", text)
        self.assertIn("'transformacao_saida'", text)
        self.assertIn("public.create_est_lote_pa_auto", text)
        self.assertIn("PA lot quantities must match planned finished packages", text)

    def test_completion_governs_pi_and_packaging_balances(self) -> None:
        text = COMPLETION_MIGRATION.read_text(encoding="utf-8")

        self.assertIn("create or replace view public.est_lotes_mp_saldos", text)
        self.assertIn("create or replace view public.est_lotes_pi_saldos", text)
        self.assertIn("create or replace function public.pcp_envase_volume_pi_disponivel", text)
        self.assertIn("pcp_ordem_envase_reservas", text)
        self.assertIn("insufficient packaging material balance", text)

    def test_completion_rpcs_are_audited_and_not_public(self) -> None:
        text = COMPLETION_MIGRATION.read_text(encoding="utf-8")

        for function_name in (
            "reservar_pcp_ordem_envase_embalagem",
            "iniciar_pcp_ordem_envase",
            "finalizar_pcp_ordem_envase",
        ):
            start = text.index(f"create or replace function public.{function_name}")
            end = text.find("create or replace function public.", start + 1)
            body = text[start : end if end >= 0 else len(text)]
            self.assertIn("public.begin_audited_rpc", body, function_name)
            self.assertIn("public.log_audited_rpc_change", body, function_name)
        self.assertIn("from public, anon;", text)

    def test_web_flow_is_governed_and_printable(self) -> None:
        actions = (WEB / "app" / "producao" / "envase" / "actions.ts").read_text(encoding="utf-8")
        workbench = (WEB / "app" / "producao" / "envase" / "packaging-workbench.tsx").read_text(encoding="utf-8")
        printable = (WEB / "app" / "producao" / "envase" / "[id]" / "imprimir" / "page.tsx").read_text(encoding="utf-8")
        pcp_actions = (WEB / "app" / "pcp" / "actions.ts").read_text(encoding="utf-8")
        for rpc in ("emitir_pcp_op_mapa_com_envase", "reservar_pcp_ordem_envase_embalagem", "iniciar_pcp_ordem_envase", "finalizar_pcp_ordem_envase"):
            self.assertIn(f'auditedRpc(supabase, "{rpc}"', actions)
        self.assertNotIn('.rpc(', actions)
        self.assertNotIn('"mapa_documental"', pcp_actions.split("const ALLOWED_OP_TYPES", 1)[1].split(";", 1)[0])
        self.assertIn("Lote PI liberado", workbench)
        self.assertIn("Lote PA gerado", workbench)
        self.assertIn("lote_pa_quantidade", actions)
        self.assertNotIn("[1, 2, 3]", actions)
        self.assertIn("const reservationsComplete", workbench)
        self.assertIn("component.reservedQuantity >= component.plannedQuantity", workbench)
        self.assertIn("Conclua a separação das embalagens", workbench)
        self.assertIn("canPrepare && reservationsComplete", workbench)
        self.assertIn("assinaturas dos operadores são físicas", printable)
        self.assertIn("Terminal:", printable)

    def test_packaging_order_generates_exactly_one_pa_lot(self) -> None:
        migration = (ROOT / "supabase" / "migrations" / "0087_packaging_single_pa_lot.sql").read_text(encoding="utf-8")
        self.assertIn("jsonb_array_length(p_lotes_pa_jsonb) <> 1", migration)
        self.assertIn("packaging order must generate exactly one PA lot", migration)
        self.assertIn("finalizar_pcp_ordem_envase_impl_0077", migration)
        self.assertIn("materialize_pcp_envase_pa_cost", migration)


if __name__ == "__main__":
    unittest.main()
