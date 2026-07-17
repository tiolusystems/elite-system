from __future__ import annotations

from pathlib import Path
import unittest


ROOT = Path(__file__).resolve().parents[1]
PAGE = ROOT / "apps" / "web" / "app" / "cadastros" / "page.tsx"
CLIENTS = ROOT / "apps" / "web" / "app" / "cadastros" / "clientes-section.tsx"
ACTIONS = ROOT / "apps" / "web" / "app" / "cadastros" / "actions.ts"
GOVERNANCE = ROOT / "apps" / "web" / "lib" / "master-data-governance.ts"
MASTER_DATA = ROOT / "apps" / "web" / "lib" / "master-data.ts"
CSS = ROOT / "apps" / "web" / "app" / "globals.css"


class ClientsPropertiesUxContractTests(unittest.TestCase):
    def test_client_area_uses_existing_audited_actions(self) -> None:
        text = CLIENTS.read_text(encoding="utf-8")
        for action in ("createClienteAction", "updateClienteAction", "deactivateClienteAction"):
            self.assertIn(action, text)
        self.assertIn("action={editing ? updateClienteAction : createClienteAction}", text)
        self.assertIn("action={deactivateClienteAction}", text)
        self.assertNotIn(".rpc(", text)
        self.assertNotIn("service_role", text)

    def test_status_and_uf_are_governed_in_one_source(self) -> None:
        client_text = CLIENTS.read_text(encoding="utf-8")
        governance_text = GOVERNANCE.read_text(encoding="utf-8")
        self.assertIn("UF_OPTIONS.map", client_text)
        self.assertIn("cadastroStatusLabel", client_text)
        self.assertIn('{ value: "active", label: "Ativo" }', governance_text)
        self.assertIn('{ value: "pending_review", label: "Em revisão" }', governance_text)
        self.assertNotIn('<option value="active">active</option>', client_text)
        self.assertNotIn("action_logs", client_text)
        self.assertNotIn("PostgreSQL", client_text)

    def test_client_property_relationship_is_read_from_relational_tables(self) -> None:
        text = MASTER_DATA.read_text(encoding="utf-8")
        self.assertIn('.from("cad_clientes")', text)
        self.assertIn('.from("cad_cliente_propriedades")', text)
        self.assertIn('.from("cad_cliente_vendedores")', text)
        self.assertIn("clienteId", text)
        self.assertIn("propriedadeId", text)

    def test_layout_has_desktop_and_mobile_workbench_contracts(self) -> None:
        page = PAGE.read_text(encoding="utf-8")
        clients = CLIENTS.read_text(encoding="utf-8")
        css = CSS.read_text(encoding="utf-8")
        self.assertIn("<ClientesSection", page)
        self.assertIn("clients-workbench", clients)
        self.assertIn("client-form-grid", clients)
        self.assertIn("@media (max-width: 820px)", css)
        self.assertIn("@media (max-width: 520px)", css)
        self.assertIn(".clients-workbench { grid-template-columns: 1fr; }", css)

    def test_client_area_hides_technical_errors_and_has_one_primary_flow(self) -> None:
        page = PAGE.read_text(encoding="utf-8")
        self.assertNotIn("{dashboard.error}", page)
        self.assertNotIn('id="credito"', page)
        self.assertIn("grupo=clientes&modo=novo#cadastro-cliente", page)

    def test_client_actions_return_to_the_client_workbench(self) -> None:
        actions = ACTIONS.read_text(encoding="utf-8")
        self.assertIn('redirect("/cadastros?grupo=clientes&result=cliente_created")', actions)
        self.assertIn("grupo=clientes&cliente=${clienteId}&result=cliente_updated", actions)
        self.assertIn("grupo=clientes&cliente=${clienteId}&result=cliente_deactivated", actions)


if __name__ == "__main__":
    unittest.main()
