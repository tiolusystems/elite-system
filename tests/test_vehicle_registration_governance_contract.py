from __future__ import annotations

from pathlib import Path
import unittest


ROOT = Path(__file__).resolve().parents[1]
MIGRATION = ROOT / "supabase" / "migrations" / "0109_govern_vehicle_registration.sql"
ACTIONS = ROOT / "apps" / "web" / "app" / "cadastros" / "actions.ts"
PAGE = ROOT / "apps" / "web" / "app" / "cadastros" / "page.tsx"
VEHICLES = ROOT / "apps" / "web" / "app" / "cadastros" / "vehicles-section.tsx"
MASTER_DATA = ROOT / "apps" / "web" / "lib" / "master-data.ts"
CI = ROOT / ".github" / "workflows" / "ci.yml"


class VehicleRegistrationGovernanceContractTests(unittest.TestCase):
    def test_migration_keeps_vehicle_writes_atomic_and_default_denied(self) -> None:
        text = MIGRATION.read_text(encoding="utf-8")
        for contract in (
            "'cadastros.veiculos.create'",
            "'cadastros.veiculos.status.manage'",
            "default_allowed = false",
            "create_cad_veiculo_governado",
            "set_cad_veiculo_active_state",
            "pg_advisory_xact_lock",
            "begin_audited_rpc",
            "log_audited_rpc_change",
            "revoke insert, update, delete, truncate",
        ):
            self.assertIn(contract, text)
        self.assertNotIn("delete from public.cad_veiculos", text.lower())

    def test_web_uses_only_governed_vehicle_rpcs(self) -> None:
        actions = ACTIONS.read_text(encoding="utf-8")
        page = PAGE.read_text(encoding="utf-8")
        vehicles = VEHICLES.read_text(encoding="utf-8")
        master_data = MASTER_DATA.read_text(encoding="utf-8")
        self.assertIn('"create_cad_veiculo_governado"', actions)
        self.assertIn('"set_cad_veiculo_active_state"', actions)
        self.assertIn("<VehiclesSection", page)
        self.assertIn('name="placa"', vehicles)
        self.assertIn('name="motivo"', vehicles)
        self.assertIn("cadastroStatusLabel", vehicles)
        self.assertIn('"cadastros.veiculos.create"', master_data)
        self.assertIn('"cadastros.veiculos.status.manage"', master_data)
        self.assertNotIn(".from(\"cad_veiculos\").insert", actions)

    def test_ci_executes_vehicle_sql_smoke(self) -> None:
        workflow = CI.read_text(encoding="utf-8")
        self.assertIn("tests/sql/vehicle_registration_governance.sql", workflow)


if __name__ == "__main__":
    unittest.main()
