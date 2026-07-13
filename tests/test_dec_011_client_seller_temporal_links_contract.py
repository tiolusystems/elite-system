from __future__ import annotations

from pathlib import Path
import re
import unittest


ROOT = Path(__file__).resolve().parents[1]
MIGRATION = ROOT / "supabase" / "migrations" / "0052_dec_011_client_seller_temporal_links.sql"
SMOKE = ROOT / "tests" / "sql" / "dec_011_client_seller_temporal_links.sql"
ADR = ROOT / "docs" / "decisoes-arquiteturais" / "ADR-009-vinculos-cliente-vendedor-area.md"
CI = ROOT / ".github" / "workflows" / "ci.yml"
UPGRADE_BEFORE = ROOT / "tests" / "sql" / "upgrade" / "dec_011_pre_0052_fixture.sql"
UPGRADE_AFTER = ROOT / "tests" / "sql" / "upgrade" / "dec_011_post_0052_verify.sql"


class Dec011ClientSellerTemporalLinksContractTest(unittest.TestCase):
    @classmethod
    def setUpClass(cls) -> None:
        cls.sql = MIGRATION.read_text(encoding="utf-8").lower()
        cls.adr = ADR.read_text(encoding="utf-8").lower()

    def test_roles_links_and_areas_are_relational(self) -> None:
        self.assertIn("create table public.cad_cliente_vinculo_papeis", self.sql)
        self.assertIn("create table public.cad_cliente_areas_comerciais", self.sql)
        self.assertIn("papel_vinculo_id bigint", self.sql)
        self.assertIn("references public.cad_cliente_vinculo_papeis", self.sql)
        self.assertIn("cad_cliente_vendedores_propriedade_fk", self.sql)

        role_block = re.search(
            r"create table public\.cad_cliente_vinculo_papeis\s*\((.*?)\n\);",
            self.sql,
            re.DOTALL,
        )
        self.assertIsNotNone(role_block)
        self.assertNotIn("json", role_block.group(1))

    def test_registration_and_service_are_distinct(self) -> None:
        self.assertIn("('cadastrou', 'cadastrou o cliente', false", self.sql)
        self.assertIn("('atende', 'atende o cliente', true", self.sql)
        self.assertIn("concede_visibilidade", self.sql)
        self.assertIn("papel de negocio nao e `user_profiles.role`", self.adr)

    def test_temporal_integrity_and_no_hard_delete(self) -> None:
        for fragment in (
            "cad_cliente_vendedores_vigencia_check",
            "cad_cliente_areas_vigencia_check",
            "active client/seller link overlaps an existing period",
            "active client/area link overlaps an existing period",
            "prevent_temporal_commercial_link_delete",
        ):
            self.assertIn(fragment, self.sql)

    def test_historical_links_require_lineage_and_never_grant_visibility(self) -> None:
        for fragment in (
            "idx_cad_cliente_vendedores_source_once",
            "idx_cad_cliente_areas_source_once",
            "enforce_historical_record_contract",
            "relation.origem_dados = 'sistema'",
            "client_area.origem_dados = 'sistema'",
            "person_area.origem_dados = 'sistema'",
        ):
            self.assertIn(fragment, self.sql)

    def test_order_reference_is_relational_and_property_scoped(self) -> None:
        self.assertIn("cliente_vendedor_vinculo_id bigint", self.sql)
        self.assertIn("com_pedidos_cliente_vendedor_vinculo_fk", self.sql)
        self.assertIn("order property is outside the selected client/seller link", self.sql)
        self.assertIn("order requires an active client/seller link on order date", self.sql)

    def test_smoke_upgrade_and_ci_are_wired(self) -> None:
        self.assertTrue(SMOKE.exists())
        self.assertTrue(UPGRADE_BEFORE.exists())
        self.assertTrue(UPGRADE_AFTER.exists())
        self.assertIn(
            "tests/sql/dec_011_client_seller_temporal_links.sql",
            CI.read_text(encoding="utf-8"),
        )

    def test_adr_documents_required_decision_elements(self) -> None:
        for heading in (
            "## ownership e dependencias",
            "## chaves naturais e idempotencia",
            "## campos obrigatorios",
            "## campos opcionais",
            "## pendentes de revisao",
            "## backfill",
            "## rollback",
        ):
            self.assertIn(heading, self.adr)


if __name__ == "__main__":
    unittest.main()
