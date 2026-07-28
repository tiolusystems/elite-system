from pathlib import Path
import unittest


ROOT = Path(__file__).resolve().parents[1]
WEB = ROOT / "apps" / "web"
PRINT_PAGE = WEB / "app" / "producao" / "ordens" / "[id]" / "imprimir" / "page.tsx"
QUALITY = WEB / "app" / "producao" / "qualidade" / "quality-workbench.tsx"
ACTIONS = WEB / "app" / "pcp" / "actions.ts"
PCP = WEB / "lib" / "pcp.ts"
MANUALS = WEB / "lib" / "manuals.ts"
MIGRATION = ROOT / "supabase" / "migrations" / "0114_govern_pcp_cq_participants.sql"


class PcpOrderPrintAndCqParticipantsContractTests(unittest.TestCase):
    def setUp(self) -> None:
        self.print_page = PRINT_PAGE.read_text(encoding="utf-8")
        self.quality = QUALITY.read_text(encoding="utf-8")
        self.actions = ACTIONS.read_text(encoding="utf-8")
        self.pcp = PCP.read_text(encoding="utf-8")
        self.manuals = MANUALS.read_text(encoding="utf-8")
        self.migration = MIGRATION.read_text(encoding="utf-8")

    def test_print_uses_total_order_quantities_and_separate_lot_rows(self) -> None:
        for expected in (
            "Matérias-primas e lotes separados",
            "Total previsto",
            "Lote separado",
            "Quantidade separada",
            "Quantidade utilizada",
            "Desvio",
            "Rubrica",
            "component.quantidadePlanejada",
            "component.reservations",
        ):
            self.assertIn(expected, self.print_page)

        self.assertNotIn("dose por litro", self.print_page.lower())
        self.assertNotIn("por litro", self.print_page.lower())
        self.assertNotIn("kg/L", self.print_page)
        self.assertNotIn("L/L", self.print_page)
        self.assertNotIn("UN/L", self.print_page)
        self.assertNotIn("validade", self.print_page.lower())

    def test_print_preserves_physical_signatures_without_replacing_digital_links(self) -> None:
        for expected in (
            "Assinaturas físicas",
            "A definir no sistema",
            "Responsável pelo CQ",
            "Responsável pela liberação",
            "não substitui o participante registrado no sistema",
            "participant?.nome",
        ):
            self.assertIn(expected, self.print_page)

    def test_print_loads_the_requested_order_instead_of_recent_dashboard_limit(self) -> None:
        self.assertIn("getPcpOrderPrintData(orderId)", self.print_page)
        self.assertNotIn("getPcpDashboard()", self.print_page)
        self.assertIn("export async function getPcpOrderPrintData", self.pcp)
        self.assertIn('.eq("id", orderId)', self.pcp)
        self.assertIn('.eq("op_id", orderId)', self.pcp)

    def test_quality_form_submits_only_person_ids(self) -> None:
        for expected in (
            'name="separador_pessoa_id"',
            'name="conferente_pessoa_id"',
            'name="formulador_1_pessoa_id"',
            'name="responsavel_cq_pessoa_id"',
            'name="responsavel_liberacao_pessoa_id"',
        ):
            self.assertIn(expected, self.quality)

        self.assertIn('"finalizar_pcp_op_relacional_com_pops"', self.actions)
        self.assertIn("p_formulador_pessoa_ids: formuladorIds", self.actions)
        self.assertNotIn("p_separador_mp:", self.actions)
        self.assertNotIn("p_conferente_mp:", self.actions)
        self.assertNotIn("p_formuladores_jsonb:", self.actions)

    def test_relational_rpc_rejects_inactive_people_and_preserves_snapshots(self) -> None:
        for expected in (
            "p_separador_pessoa_id bigint",
            "p_conferente_pessoa_id bigint",
            "p_formulador_pessoa_ids bigint[]",
            "p_responsavel_cq_pessoa_id bigint",
            "p_responsavel_liberacao_pessoa_id bigint",
            "person.status = 'active'",
            "pessoa_comercial_id",
            "nome_snapshot",
            "'responsavel_cq'",
            "'responsavel_liberacao'",
            "pcp.cq_participants_registered",
        ):
            self.assertIn(expected, self.migration)

        self.assertIn(
            "from authenticated;",
            self.migration.split("revoke all on function public.finalizar_pcp_op(", 1)[1],
        )
        self.assertIn("grant execute on function public.finalizar_pcp_op_relacional", self.migration)

    def test_dashboard_reads_consumption_and_historical_participants(self) -> None:
        for expected in (
            '.from("pcp_op_consumos_componentes")',
            '.from("pcp_op_cq_participantes")',
            "quantidadeUtilizada",
            "participants: participantsByOp.get(id) ?? []",
        ):
            self.assertIn(expected, self.pcp)

    def test_manual_explains_print_and_digital_participant_contracts(self) -> None:
        for expected in (
            "quantidades totais e separação por lote",
            "responsável pelo CQ",
            "responsável pela liberação ou bloqueio",
            "Assinatura física não substitui o vínculo digital",
        ):
            self.assertIn(expected, self.manuals)


if __name__ == "__main__":
    unittest.main()
