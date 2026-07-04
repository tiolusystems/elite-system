from __future__ import annotations

import unittest
from pathlib import Path


REPO_ROOT = Path(__file__).resolve().parents[1]
MIGRATION_0016 = REPO_ROOT / "supabase" / "migrations" / "0016_cadastros_pessoas_role_axis.sql"
CADASTROS_ACTIONS = REPO_ROOT / "apps" / "web" / "app" / "cadastros" / "actions.ts"


class CadastrosPessoasAuditContractTests(unittest.TestCase):
    def test_pessoas_soft_delete_does_not_hard_delete_master_data(self) -> None:
        text = MIGRATION_0016.read_text(encoding="utf-8").lower()

        self.assertIn("create or replace function public.deactivate_cad_pessoa_comercial", text)
        self.assertIn("set status = 'inactive'", text)
        self.assertNotIn("delete from public.cad_pessoas_comerciais", text)

    def test_role_update_is_business_role_not_auth_role(self) -> None:
        text = MIGRATION_0016.read_text(encoding="utf-8")

        self.assertIn("Nao altera user_profiles.role", text)
        self.assertIn("comment on function public.update_cad_pessoa_comercial_role", text)
        self.assertNotIn("update public.user_profiles", text)
        self.assertNotIn("set role =", text.lower())

    def test_role_update_logs_standard_reason_and_papeis_diff(self) -> None:
        text = MIGRATION_0016.read_text(encoding="utf-8")

        self.assertIn("validate_cad_pessoa_role_reason", text)
        self.assertIn("'promocao'", text)
        self.assertIn("'correcao_cadastro'", text)
        self.assertIn("'transferencia_carteira'", text)
        self.assertIn("'desligamento_funcao'", text)
        self.assertIn("'mudanca_comissao'", text)
        self.assertIn("'outro'", text)
        self.assertIn("'papeis_adicionados'", text)
        self.assertIn("'papeis_removidos'", text)
        self.assertIn("'tipo_comercial_before'", text)
        self.assertIn("'tipo_comercial_after'", text)

    def test_web_actions_expose_pessoas_updates_via_audited_rpc(self) -> None:
        text = CADASTROS_ACTIONS.read_text(encoding="utf-8")

        self.assertIn("export async function updatePessoaComercialIdentityAction", text)
        self.assertIn("export async function updatePessoaComercialRoleAction", text)
        self.assertIn("export async function deactivatePessoaComercialAction", text)
        self.assertIn('auditedRpc(supabase, "update_cad_pessoa_comercial_identity"', text)
        self.assertIn('auditedRpc(supabase, "update_cad_pessoa_comercial_role"', text)
        self.assertIn('auditedRpc(supabase, "deactivate_cad_pessoa_comercial"', text)


if __name__ == "__main__":
    unittest.main()
