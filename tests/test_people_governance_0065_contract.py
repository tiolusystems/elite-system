from __future__ import annotations

from pathlib import Path
import unittest


ROOT = Path(__file__).resolve().parents[1]
MIGRATION = ROOT / "supabase" / "migrations" / "0065_govern_commercial_people_relationships.sql"
ACTIONS = ROOT / "apps" / "web" / "app" / "cadastros" / "actions.ts"
FORM = ROOT / "apps" / "web" / "app" / "cadastros" / "governed-person-create-form.tsx"
PEOPLE = ROOT / "apps" / "web" / "app" / "cadastros" / "pessoas-section.tsx"
STRUCTURE = ROOT / "apps" / "web" / "app" / "cadastros" / "person-commercial-structure-and-commission.tsx"


class PeopleGovernance0065ContractTests(unittest.TestCase):
    def test_aliases_are_unique_per_person_and_searchable_globally(self) -> None:
        sql = MIGRATION.read_text(encoding="utf-8").lower()
        self.assertIn("drop constraint if exists cad_pessoa_aliases_alias_norm_key", sql)
        self.assertIn("unique (pessoa_id, alias_norm)", sql)
        self.assertIn("idx_cad_pessoa_aliases_alias_norm", sql)
        self.assertIn("duplicate alias within the same person exists", sql)

    def test_duplicate_preflight_and_create_are_transactional(self) -> None:
        sql = MIGRATION.read_text(encoding="utf-8").lower()
        self.assertIn("find_cad_pessoa_possible_duplicates", sql)
        self.assertIn("pg_advisory_xact_lock", sql)
        self.assertIn("p_candidatos_apresentados bigint[]", sql)
        self.assertIn("duplicate candidates changed; review again", sql)
        self.assertIn("possible_duplicate_confirmed", sql)
        self.assertIn("normalized legacy code already exists", sql)

    def test_area_and_reactivation_contracts_are_audited_and_minimal(self) -> None:
        sql = MIGRATION.read_text(encoding="utf-8").lower()
        for function_name in (
            "link_cad_pessoa_area_comercial",
            "close_cad_pessoa_area_comercial",
            "list_cad_pessoa_area_history",
            "reactivate_cad_pessoa_comercial",
        ):
            self.assertIn(f"function public.{function_name}", sql)
        self.assertIn("relationships_reopened', false", sql)
        self.assertIn("begin_audited_rpc", sql)
        self.assertIn("log_audited_rpc_change", sql)
        self.assertNotIn("grant execute on function public.link_cad_pessoa_area_comercial(bigint, bigint, text, date, text) to anon", sql)

    def test_interface_uses_ids_and_ptbr_labels(self) -> None:
        actions = ACTIONS.read_text(encoding="utf-8")
        form = FORM.read_text(encoding="utf-8")
        people = PEOPLE.read_text(encoding="utf-8")
        structure = STRUCTURE.read_text(encoding="utf-8")
        self.assertNotIn('name="vendedor_responsavel_id"', form)
        self.assertIn('name="candidatos_apresentados"', form)
        self.assertIn('name="pessoa_destino_id"', structure)
        self.assertIn('name="tipo_relacionamento"', structure)
        self.assertIn('name="area_id"', people)
        self.assertIn('name="vinculo_id"', people)
        self.assertIn('"find_cad_pessoa_possible_duplicates"', actions)
        for raw_value in ("same_normalized_name", "name_matches_existing_alias", "pending_review"):
            self.assertNotIn(f">{raw_value}<", form + people)


if __name__ == "__main__":
    unittest.main()
