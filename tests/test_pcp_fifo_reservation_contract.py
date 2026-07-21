from pathlib import Path
import unittest

ROOT = Path(__file__).resolve().parents[1]
MIGRATION = ROOT / "supabase/migrations/0076_pcp_fifo_component_reservation.sql"
ORDERS = ROOT / "apps/web/app/producao/ordens/orders-workbench.tsx"
ACTIONS = ROOT / "apps/web/app/pcp/actions.ts"
MANUAL = ROOT / "docs/manuais/producao/FORMULAS_GARANTIAS.md"

class PcpFifoReservationTests(unittest.TestCase):
    def test_fifo_is_deterministic_and_can_span_lots(self):
        sql = MIGRATION.read_text(encoding="utf-8")
        self.assertIn("order by entered_at, lot_id", sql)
        self.assertIn("least(v_remaining, v_lot.saldo_disponivel)", sql)
        self.assertIn("insufficient stock available for full FIFO reservation", sql)
        self.assertEqual(sql.count("pg_advisory_xact_lock"), 2)

    def test_override_requires_separate_permission_reason_and_audit(self):
        sql = MIGRATION.read_text(encoding="utf-8")
        self.assertIn("pcp.op.reserve_override_fifo", sql)
        self.assertIn("FIFO override requires justification", sql)
        self.assertIn("pcp.op_fifo_override", sql)
        self.assertIn("fifo_justificativa", sql)

    def test_ui_recommends_fifo_and_uses_audited_action(self):
        orders = ORDERS.read_text(encoding="utf-8")
        actions = ACTIONS.read_text(encoding="utf-8")
        self.assertIn("Reservar automaticamente por FIFO", orders)
        self.assertIn("FIFO recomendado", orders)
        self.assertIn("reservePcpComponentFifoAction", orders)
        self.assertIn('auditedRpc(supabase, "reservar_pcp_op_componente_fifo"', actions)

    def test_manual_explains_override(self):
        manual = MANUAL.read_text(encoding="utf-8")
        self.assertIn("Reserva FIFO", manual)
        self.assertIn("alçada específica", manual)

if __name__ == "__main__": unittest.main()
