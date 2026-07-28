from pathlib import Path
import unittest


ROOT = Path(__file__).resolve().parents[1]
WEB = ROOT / "apps" / "web"
MIGRATION = ROOT / "supabase" / "migrations" / "0115_govern_controlled_procedures.sql"
PAGE = WEB / "app" / "qualidade" / "pops" / "page.tsx"
ACTIONS = WEB / "app" / "qualidade" / "pops" / "actions.ts"
QUALITY = WEB / "app" / "producao" / "qualidade" / "quality-workbench.tsx"
PCP_ACTIONS = WEB / "app" / "pcp" / "actions.ts"
PRINT = WEB / "app" / "producao" / "ordens" / "[id]" / "imprimir" / "page.tsx"
NAVIGATION = WEB / "lib" / "app-navigation.ts"
MANUALS = WEB / "lib" / "manuals.ts"


class ControlledProceduresContractTests(unittest.TestCase):
    def setUp(self) -> None:
        self.migration = MIGRATION.read_text(encoding="utf-8")
        self.page = PAGE.read_text(encoding="utf-8")
        self.actions = ACTIONS.read_text(encoding="utf-8")
        self.quality = QUALITY.read_text(encoding="utf-8")
        self.pcp_actions = PCP_ACTIONS.read_text(encoding="utf-8")
        self.print_page = PRINT.read_text(encoding="utf-8")
        self.navigation = NAVIGATION.read_text(encoding="utf-8")
        self.manuals = MANUALS.read_text(encoding="utf-8")

    def test_catalog_belongs_to_pcp_quality_without_new_module(self) -> None:
        self.assertIn("('/qualidade/pops', 'pcp', true)", self.migration)
        self.assertIn('href: "/qualidade/pops"', self.navigation)
        self.assertIn("POPs e documentos controlados", self.page)
        self.assertNotIn("create table public.sys_modules", self.migration)

    def test_permissions_are_atomic_and_sensitive_writes_default_to_denied(self) -> None:
        for action in (
            "pcp.pop.read",
            "pcp.pop.version.create",
            "pcp.pop.publish",
            "pcp.pop.state.manage",
            "pcp.pop.applicability.manage",
            "pcp.pop.cq.record",
        ):
            self.assertIn(action, self.migration)
        self.assertIn(
            "('pcp.pop.version.create', 'pcp', 'Criar versao de POP', false",
            self.migration,
        )
        self.assertIn(
            "revoke all on table public.pcp_pop_versoes from public, anon, authenticated",
            self.migration,
        )

    def test_published_versions_and_operational_snapshots_are_immutable(self) -> None:
        for expected in (
            "guard_pcp_pop_version_publication",
            "published POP versions are immutable",
            "prevent_pcp_pop_append_only_changes",
            "pcp_op_pops_congelados",
            "trg_pcp_op_freeze_pop_versions",
            "after insert on public.pcp_ordens_producao",
        ):
            self.assertIn(expected, self.migration)

    def test_many_to_many_applicability_is_relational_and_historized(self) -> None:
        self.assertIn("pcp_pop_aplicabilidade_eventos", self.migration)
        self.assertIn("formula_versao_id bigint references public.pcp_formula_versoes", self.migration)
        self.assertIn("status in ('active', 'inactive')", self.migration)
        self.assertIn("set_pcp_pop_applicability", self.actions)
        self.assertNotIn('name="pop_id"', self.quality)

    def test_quality_records_only_frozen_references(self) -> None:
        self.assertIn("Procedimentos aplicaveis", self.quality)
        self.assertIn('name="pop_snapshot_id"', self.quality)
        self.assertIn("finalizar_pcp_op_relacional_com_pops", self.pcp_actions)
        self.assertIn("snapshot does not belong to this order", self.migration)
        self.assertIn("pcp_op_cq_pop_registros", self.migration)

    def test_print_shows_references_without_full_pop_content(self) -> None:
        for expected in ("Procedimentos aplicaveis", "Codigo", "Titulo", "Revisao", "Vigencia"):
            self.assertIn(expected, self.print_page)
        self.assertNotIn("procedure.content", self.print_page)
        self.assertNotIn("Conteudo controlado", self.print_page)

    def test_manual_distinguishes_system_help_from_controlled_document(self) -> None:
        self.assertIn('manual("/qualidade/pops"', self.manuals)
        self.assertIn("Versoes publicadas permanecem imutaveis", self.manuals)
        self.assertIn("Novas revisoes nao alteram OPs abertas ou concluidas", self.manuals)


if __name__ == "__main__":
    unittest.main()
