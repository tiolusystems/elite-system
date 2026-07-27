from __future__ import annotations

from pathlib import Path
import unittest


ROOT = Path(__file__).resolve().parents[1]
MIGRATION = ROOT / "supabase" / "migrations" / "0110_govern_identity_and_client_commercial_links.sql"
SECURITY_ACTIONS = ROOT / "apps" / "web" / "app" / "seguranca" / "actions.ts"
SECURITY_PAGE = ROOT / "apps" / "web" / "app" / "seguranca" / "page.tsx"
CLIENT_ACTIONS = ROOT / "apps" / "web" / "app" / "cadastros" / "actions.ts"
CLIENT_PAGE = ROOT / "apps" / "web" / "app" / "cadastros" / "clientes-section.tsx"
MASTER_DATA = ROOT / "apps" / "web" / "lib" / "master-data.ts"
CI = ROOT / ".github" / "workflows" / "ci.yml"


class IdentityClientLinkGovernanceContractTests(unittest.TestCase):
    def test_permissions_are_atomic_and_default_denied(self) -> None:
        text = MIGRATION.read_text(encoding="utf-8")
        for contract in (
            "'security.identity.person.link'",
            "'cadastros.clientes.commercial_links.manage'",
            "default_allowed = false",
            "link_security_user_commercial_person",
            "link_cad_cliente_commercial_person",
            "close_cad_cliente_commercial_person",
            "pg_advisory_xact_lock",
            "begin_audited_rpc",
            "log_audited_rpc_change",
            "revoke insert, update, delete, truncate",
        ):
            self.assertIn(contract, text)
        self.assertNotIn("delete from public.cad_cliente_vendedores", text.lower())
        self.assertNotIn("role =", text.lower())

    def test_web_uses_governed_relational_rpcs(self) -> None:
        security_actions = SECURITY_ACTIONS.read_text(encoding="utf-8")
        security_page = SECURITY_PAGE.read_text(encoding="utf-8")
        client_actions = CLIENT_ACTIONS.read_text(encoding="utf-8")
        client_page = CLIENT_PAGE.read_text(encoding="utf-8")
        master_data = MASTER_DATA.read_text(encoding="utf-8")

        self.assertIn('"link_security_user_commercial_person"', security_actions)
        self.assertIn("linkSecurityUserCommercialPersonAction", security_page)
        self.assertIn('name="pessoa_id"', security_page)
        self.assertIn('"link_cad_cliente_commercial_person"', client_actions)
        self.assertIn('"close_cad_cliente_commercial_person"', client_actions)
        self.assertIn("linkClienteCommercialPersonAction", client_page)
        self.assertIn("closeClienteCommercialPersonAction", client_page)
        self.assertIn('name="papel_vinculo_id"', client_page)
        self.assertIn('name="propriedade_id"', client_page)
        self.assertIn("count={vinculos.length}", client_page)
        self.assertIn("showRows={false}", client_page)
        self.assertIn('"cadastros.clientes.commercial_links.manage"', master_data)
        self.assertNotIn('.from("cad_cliente_vendedores").insert', client_actions)

    def test_ci_executes_relational_link_smoke(self) -> None:
        workflow = CI.read_text(encoding="utf-8")
        self.assertIn("tests/sql/identity_client_link_governance.sql", workflow)


if __name__ == "__main__":
    unittest.main()
