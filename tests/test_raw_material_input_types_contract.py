from pathlib import Path
import unittest


ROOT = Path(__file__).resolve().parents[1]
MIGRATION = ROOT / "supabase" / "migrations" / "0063_govern_raw_material_input_types.sql"
PAGE = ROOT / "apps" / "web" / "app" / "cadastros" / "tipos-insumo" / "page.tsx"
MATERIALS = ROOT / "apps" / "web" / "app" / "cadastros" / "materias-primas" / "page.tsx"
LOADER = ROOT / "apps" / "web" / "lib" / "technical-catalog.ts"
SMOKE = ROOT / "tests" / "sql" / "raw_material_input_types.sql"


class RawMaterialInputTypesContractTests(unittest.TestCase):
    def test_schema_is_relational_and_preserves_legacy_without_inference(self) -> None:
        sql = MIGRATION.read_text(encoding="utf-8")
        self.assertIn("create table public.cad_tipos_insumo", sql)
        self.assertIn("tipo_insumo_id bigint", sql)
        self.assertIn("foreign key (tipo_insumo_id)", sql)
        self.assertIn("origem_dados text not null default 'sistema'", sql)
        self.assertIn("classificadas_por_inferencia", sql)
        self.assertIn("0::integer as classificadas_por_inferencia", sql)
        self.assertNotIn("update public.cad_materias_primas\n   set tipo_insumo_id", sql)
        self.assertIn("legacy free-text input type is read-only", sql)

    def test_security_and_audit_contract_are_explicit(self) -> None:
        sql = MIGRATION.read_text(encoding="utf-8")
        for rpc in (
            "create_cad_tipo_insumo", "update_cad_tipo_insumo",
            "activate_cad_tipo_insumo", "deactivate_cad_tipo_insumo",
            "set_cad_materia_prima_tipo", "create_cad_materia_prima_governada",
        ):
            self.assertIn(f"function public.{rpc}", sql)
        self.assertGreaterEqual(sql.count("public.begin_audited_rpc("), 6)
        self.assertGreaterEqual(sql.count("public.log_audited_rpc_change("), 6)
        self.assertIn("revoke insert, update, delete, truncate", sql)
        self.assertIn("from public, anon", sql)
        self.assertIn("prevent_cad_tipo_insumo_delete", sql)

    def test_ui_uses_database_catalog_by_id_and_ptbr_labels(self) -> None:
        page = PAGE.read_text(encoding="utf-8")
        materials = MATERIALS.read_text(encoding="utf-8")
        loader = LOADER.read_text(encoding="utf-8")
        self.assertIn('.from("cad_tipos_insumo")', loader)
        self.assertIn('name="tipo_insumo_id"', page + materials)
        self.assertNotIn('name="tipo" placeholder=', materials)
        self.assertIn("Tipo de insumo não definido", page + materials + loader)
        self.assertIn("Sem classificação", materials)
        for raw in (">active<", ">pending_review<", ">inactive<"):
            self.assertNotIn(raw, page)

    def test_smoke_covers_integrity_audit_and_anonymous_denial(self) -> None:
        smoke = SMOKE.read_text(encoding="utf-8")
        for evidence in (
            "normalized duplicate name was accepted", "missing input type was accepted",
            "physical deletion was accepted", "anonymous RPC execution was accepted",
            "PG_VALIDATE_0063_WITH_SMOKE_OK",
        ):
            self.assertIn(evidence, smoke)


if __name__ == "__main__":
    unittest.main()
