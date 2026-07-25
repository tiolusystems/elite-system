import unittest
from pathlib import Path


ROOT = Path(__file__).resolve().parents[1]
PAGE = ROOT / "apps/web/app/producao/ordens/page.tsx"
WORKBENCH = ROOT / "apps/web/app/producao/ordens/orders-workbench.tsx"
TRANSFORMATIONS = ROOT / "apps/web/app/producao/transformacoes/page.tsx"
TRANSFORMATION_WORKBENCH = ROOT / "apps/web/app/producao/transformacoes/transformation-workbench.tsx"
PCP = ROOT / "apps/web/lib/pcp.ts"
LABELS = ROOT / "apps/web/lib/production-labels.ts"
MANUALS = ROOT / "apps/web/lib/manuals.ts"
STYLES = ROOT / "apps/web/app/globals.css"
E2E_BOOTSTRAP = ROOT / "apps/web/e2e/bootstrap-synthetic-users.mjs"


class OrdersReservationsUxContractTests(unittest.TestCase):
    def test_atomic_capabilities_are_resolved_from_action_keys(self) -> None:
        text = PCP.read_text(encoding="utf-8")

        self.assertIn("export type PcpOrderCapabilities", text)
        self.assertIn("export async function getPcpOrderCapabilities", text)
        for action_key in (
            "pcp.op.create",
            "pcp.op.reserve_components",
            "pcp.op.reserve_override_fifo",
            "pcp.op.start",
            "pcp.op.cancel",
        ):
            self.assertIn(action_key, text)
        self.assertIn('supabase.rpc("can_current_user"', text)
        self.assertNotIn("role ===", text)

    def test_page_separates_query_from_creation_and_hides_unauthorized_actions(self) -> None:
        page = PAGE.read_text(encoding="utf-8")
        workbench = WORKBENCH.read_text(encoding="utf-8")

        self.assertIn("const startCreating = capabilities.canCreate", page)
        self.assertIn("!startCreating", page)
        self.assertIn("capabilities.canCreate", page)
        self.assertIn('href="/producao/formulas"', page)
        self.assertIn("Consulta disponível em modo somente leitura", workbench)
        self.assertIn("order-create-workflow", workbench)
        self.assertNotIn("module-card-meta", workbench)
        self.assertNotIn("formula.formulaVersionId", workbench)

    def test_order_queue_is_operational_and_ptbr(self) -> None:
        page = PAGE.read_text(encoding="utf-8")
        workbench = WORKBENCH.read_text(encoding="utf-8")
        labels = LABELS.read_text(encoding="utf-8")

        for label in ("Rascunho", "Planejada", "Em processo", "Finalizada", "Cancelada"):
            self.assertIn(label, page + labels)
        for field in ("Necessário", "Reservado", "Pendente", "Disponível"):
            self.assertIn(field, workbench)
        self.assertIn("orderStatusLabel(op.status)", workbench)
        self.assertIn("orderTypeLabel(op.tipoOp)", workbench)
        self.assertIn("componentStatusLabel(component.status)", workbench)
        self.assertIn('?? "Situação não reconhecida"', labels)

    def test_lots_are_scoped_to_component_and_fifo_is_clear(self) -> None:
        text = WORKBENCH.read_text(encoding="utf-8")

        self.assertIn("Consultar lotes deste componente", text)
        self.assertIn("const targetLots = availableLots.filter", text)
        self.assertIn("const totalAvailable", text)
        self.assertIn("const shortage", text)
        self.assertIn("Saldo insuficiente", text)
        self.assertIn("Reservar automaticamente por FIFO", text)
        self.assertIn("Fora do FIFO", text)
        self.assertIn("canOverrideFifo", text)
        self.assertIn("minLength={10}", text)
        self.assertIn("disabled={index > 0 && !canOverrideFifo}", text)
        self.assertIn('name="lote_id"', text)
        self.assertIn('value={lot.id}', text)

    def test_reservation_and_state_actions_respect_independent_capabilities(self) -> None:
        text = WORKBENCH.read_text(encoding="utf-8")

        self.assertIn("capabilities.canReserve", text)
        self.assertIn("capabilities.canStart", text)
        self.assertIn("capabilities.canCancel", text)
        self.assertIn("capabilities.canOverrideFifo", text)
        self.assertIn("reservationComplete", text)
        self.assertIn("reservePcpComponentFifoAction", text)
        self.assertIn("reservePcpComponentAction", text)
        self.assertIn("startPcpOpAction", text)
        self.assertIn("cancelPcpOpAction", text)
        self.assertNotIn(".rpc(", text)

    def test_shared_order_card_never_receives_implicit_permissions(self) -> None:
        page = TRANSFORMATIONS.read_text(encoding="utf-8")
        workbench = TRANSFORMATION_WORKBENCH.read_text(encoding="utf-8")
        orders = WORKBENCH.read_text(encoding="utf-8")

        self.assertIn("getPcpOrderCapabilities", page)
        self.assertIn("capabilities={capabilities}", page)
        self.assertIn("capabilities={capabilities}", workbench)
        self.assertIn("capabilities: PcpOrderCapabilities", orders)
        self.assertNotIn("FALLBACK_CAPABILITIES", orders)

    def test_contextual_manual_documents_fifo_and_audited_states(self) -> None:
        text = MANUALS.read_text(encoding="utf-8")
        start = text.index('manual("/producao/ordens"')
        excerpt = text[start : start + 2600]

        for expected in (
            "quantidades necessárias, reservadas e pendentes",
            "alçadas independentes",
            "sem baixar o saldo físico",
            "justificativa com pelo menos 10 caracteres",
            "Cada reserva registra lote",
        ):
            self.assertIn(expected, excerpt)

    def test_responsive_contract_has_no_wide_fixed_order_layout(self) -> None:
        text = STYLES.read_text(encoding="utf-8")

        self.assertIn(".order-status-navigation", text)
        self.assertIn(".order-record-summary", text)
        self.assertIn(".order-lot-table", text)
        self.assertIn("@media (max-width: 900px)", text)
        self.assertIn("grid-template-columns: repeat(2, minmax(0, 1fr))", text)
        self.assertNotIn("min-width: 1040px;\n}\n\n.order-status", text)

    def test_read_only_e2e_actor_has_explicit_atomic_denials(self) -> None:
        text = E2E_BOOTSTRAP.read_text(encoding="utf-8")

        self.assertIn('account.name === "order-reviewer"', text)
        self.assertIn("orderReadOnlyDenials", text)
        self.assertIn("do update set allowed = false", text)
        for action_key in (
            "pcp.op.create",
            "pcp.op.reserve_components",
            "pcp.op.reserve_override_fifo",
            "pcp.op.start",
            "pcp.op.cancel",
        ):
            self.assertIn(action_key, text)


if __name__ == "__main__":
    unittest.main()
