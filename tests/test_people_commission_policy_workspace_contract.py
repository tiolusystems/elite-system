from pathlib import Path
import unittest

ROOT = Path(__file__).resolve().parents[1]
MIGRATION = ROOT / "supabase/migrations/0122_people_commission_policy_workspace.sql"
SECTION = ROOT / "apps/web/app/cadastros/pessoas-section.tsx"
STRUCTURE = ROOT / "apps/web/app/cadastros/person-commercial-structure-and-commission.tsx"
ACTIONS = ROOT / "apps/web/app/cadastros/actions.ts"
CREATE_FORM = ROOT / "apps/web/app/cadastros/governed-person-create-form.tsx"
MASTER_DATA = ROOT / "apps/web/lib/master-data.ts"
PAGE = ROOT / "apps/web/app/cadastros/page.tsx"
GOVERNANCE = ROOT / "apps/web/lib/master-data-governance.ts"


class PeopleCommissionPolicyWorkspaceContract(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        cls.sql = MIGRATION.read_text(encoding="utf-8")
        cls.section = SECTION.read_text(encoding="utf-8")
        cls.structure = STRUCTURE.read_text(encoding="utf-8")
        cls.actions = ACTIONS.read_text(encoding="utf-8")
        cls.create_form = CREATE_FORM.read_text(encoding="utf-8")
        cls.master = MASTER_DATA.read_text(encoding="utf-8")
        cls.page = PAGE.read_text(encoding="utf-8")
        cls.gov = GOVERNANCE.read_text(encoding="utf-8")

    def test_agent_relationship_is_optional(self):
        self.assertNotIn("vendedor_responsavel_id is required", self.sql)
        self.assertNotIn("Obrigatório somente para agente vinculado", self.create_form)
        self.assertNotIn("Vendedor responsável", self.create_form)
        self.assertIn('label: "Agente externo"', self.gov)

    def test_relationships_are_typed_temporal_and_role_validated(self):
        for fragment in (
            "agente_vendedor",
            "vendedor_gerente",
            "origin person must have active agent role",
            "destination person must have active seller role",
            "origin person must have active seller role",
            "destination person must have active manager role",
            "vigencia_inicio",
            "vigencia_fim",
        ):
            self.assertIn(fragment, self.sql)

    def test_legacy_relationship_is_backfilled_but_deprecated(self):
        self.assertIn("Migracao governada do vinculo comercial legado", self.sql)
        self.assertIn("Campo legado de compatibilidade", self.sql)

    def test_manager_scope_uses_canonical_relationships(self):
        self.assertIn("create or replace function public.current_user_manages_seller", self.sql)
        self.assertIn("cad_pessoa_relacionamentos_comerciais", self.sql)
        self.assertIn("agent_seller", self.sql)

    def test_chain_resolver_only_walks_upward(self):
        self.assertIn("resolver_cad_pessoa_cadeia_comercial", self.sql)
        self.assertIn("v_origin_role = 'agente'", self.sql)
        self.assertIn("tipo_relacionamento = 'vendedor_gerente'", self.sql)
        self.assertIn("Nao busca agentes vinculados", self.sql)

    def test_policy_replacement_preserves_previous_version(self):
        self.assertIn("publicar_com_comissao_politica_v2", self.sql)
        self.assertIn("vigencia_fim = v_policy.vigencia_inicio - 1", self.sql)
        self.assertIn("replacement_policy_id", self.sql)
        self.assertIn("new commission policy cannot start in the past", self.sql)
        self.assertNotIn("delete from public.com_comissao_politicas_pessoa", self.sql)

    def test_person_ui_exposes_relationships_and_policy(self):
        self.assertIn("PersonCommercialStructureAndCommission", self.section)
        for fragment in (
            "Estrutura comercial",
            "Vínculos opcionais",
            "Política de comissão",
            "Criar nova versão",
            "Publicar política",
            "Agente → Vendedor",
            "Vendedor → Gerente",
        ):
            self.assertIn(fragment, self.structure)
        self.assertNotIn("function SellerField(", self.section)

    def test_commands_use_governed_rpcs(self):
        for rpc in (
            "registrar_cad_pessoa_relacionamento_comercial",
            "encerrar_cad_pessoa_relacionamento_comercial",
            "criar_com_comissao_politica_rascunho",
            "definir_com_comissao_politica_taxa",
            "remover_com_comissao_politica_taxa",
            "publicar_com_comissao_politica_v2",
        ):
            self.assertIn(f'"{rpc}"', self.actions)

    def test_workspace_is_loaded_only_for_selected_person(self):
        self.assertIn("getPersonCommissionWorkspace", self.master)
        self.assertIn("getPersonCommissionWorkspace(selectedPersonId)", self.page)
        self.assertIn("commissionWorkspace={personCommissionWorkspace}", self.page)


if __name__ == "__main__":
    unittest.main()
