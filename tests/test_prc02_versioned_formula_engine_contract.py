from pathlib import Path
import unittest


ROOT = Path(__file__).resolve().parents[1]
MIGRATION = ROOT / "supabase/migrations/0151_prc02_versioned_formula_engine.sql"
MIGRATIONS = "\n".join(
    path.read_text(encoding="utf-8").lower()
    for path in sorted((ROOT / "supabase/migrations").glob("*.sql"))
)
RUNTIME_SMOKE = ROOT / "tests/sql/prc02_versioned_formula_engine.sql"
AST_SMOKE = ROOT / "tests/sql/prc02_ast_safety.sql"
UPGRADE_BEFORE = ROOT / "tests/sql/prc02_upgrade_before_0151.sql"
UPGRADE_AFTER = ROOT / "tests/sql/prc02_versioned_formula_engine_upgrade.sql"
CI = (ROOT / ".github/workflows/ci.yml").read_text(encoding="utf-8").lower()


class Prc02VersionedFormulaEngineContract(unittest.TestCase):
    def assert_contract(self, phrase: str, capability: str):
        if phrase.lower() not in MIGRATIONS:
            self.fail(f"PRC-02 RED: falta implementar {capability}: {phrase}")

    def runtime_smoke(self) -> str:
        self.assertTrue(
            RUNTIME_SMOKE.exists(),
            "PRC-02 RED: falta o smoke runtime do motor versionado",
        )
        return RUNTIME_SMOKE.read_text(encoding="utf-8").lower()

    def migration(self) -> str:
        self.assertTrue(MIGRATION.exists(), "PRC-02: migration 0151 ausente")
        return MIGRATION.read_text(encoding="utf-8").lower()

    def test_generic_formula_identity_and_append_only_versions_are_missing(self):
        for phrase in (
            "create table public.prc_formula_perfis",
            "create table public.prc_formula_versoes",
            "create table public.prc_formula_revisoes",
            "documento_sha256",
            "formula_vista_ast",
            "formula_prazo_ast",
        ):
            self.assert_contract(phrase, "formula generica versionada e auditavel")

    def test_configurable_versioned_term_grid_is_missing(self):
        for phrase in (
            "create table public.prc_grade_prazos",
            "create table public.prc_grade_prazo_versoes",
            "create table public.prc_grade_prazo_itens",
            "fator_periodo",
        ):
            self.assert_contract(phrase, "grade de prazos versionada e configuravel")

    def test_safe_declarative_ast_validator_and_evaluator_are_missing(self):
        for phrase in (
            "create schema if not exists precificacao_internal",
            "precificacao_internal.validar_prc_formula_ast",
            "precificacao_internal.avaliar_prc_formula_ast",
            "prc-formula-ast-v1",
        ):
            self.assert_contract(phrase, "AST segura e avaliador deterministico privado")

    def test_independent_cash_and_term_formulas_are_missing(self):
        self.assert_contract("formula_vista_ast", "formula de preco a vista configuravel")
        self.assert_contract("formula_prazo_ast", "formula de preco a prazo independente")
        self.assert_contract("term_period", "variavel declarativa de periodo")
        self.assert_contract("term_days", "variavel declarativa de prazo")

    def test_parameter_catalog_and_unit_validation_are_missing(self):
        for phrase in (
            "create table public.prc_formula_parametros",
            "create table public.prc_formula_versao_parametros",
            "semantic_type",
            "unit_code",
            "unidade incompativel",
        ):
            self.assert_contract(phrase, "catalogo tipado e validacao de unidades")

    def test_elite_golden_master_is_missing_from_the_new_engine(self):
        smoke = self.runtime_smoke()
        for phrase in (
            "elite_margem_liquida_v1",
            "elite_markup_v1",
            "golden master elite",
            "30,60,90,120,150,180,210,240,270,300,330,360,390,420,450,480,510,540",
        ):
            self.assertIn(phrase, smoke, "PRC-02 RED: falta golden master Elite no motor novo")

    def test_alternative_profile_without_code_change_is_missing(self):
        smoke = self.runtime_smoke()
        for phrase in (
            "perfil alternativo",
            "28,56,84",
            "cash_price",
            "term_period",
            "sem risco",
        ):
            self.assertIn(phrase, smoke, "PRC-02 RED: falta perfil alternativo configuravel")

    def test_lifecycle_review_and_segregation_are_explicit(self):
        migration = self.migration()
        for phrase in (
            "'pending','approved','rejected'",
            "'active','superseded','withdrawn'",
            "autor nao pode aprovar ou rejeitar a propria formula",
            "somente formula aprovada pode ser ativada",
            "formula historica nao pode ser reativada",
            "prc_formula_lifecycle_eventos",
        ):
            self.assertIn(phrase, migration)

    def test_permissions_are_separate_and_default_deny(self):
        migration = self.migration()
        for action in (
            "precificacao.formula.manage",
            "precificacao.formula.review",
            "precificacao.formula.lifecycle",
        ):
            self.assertIn(action, migration)
        self.assertIn("revoke all on all functions in schema precificacao_internal", migration)
        self.assertIn("enable row level security", migration)
        self.assertNotIn("grant select on public.prc_formula_", migration)

    def test_ast_is_closed_bounded_and_numeric_only(self):
        migration = self.migration()
        for phrase in (
            "p_depth > 32",
            "v_nodes > 512",
            "octet_length(p_ast::text) > 262144",
            "jsonb_object_keys(p_parametros)) > 64",
            "('add','sub','mul','div','pow')",
            "divisao por zero",
            "potencia fora do dominio numerico",
        ):
            self.assertIn(phrase, migration)
        for forbidden in ("execute format(p_", "eval(", "plpython", "plv8"):
            self.assertNotIn(forbidden, migration)

    def test_database_issued_formula_codes_are_bounded(self):
        migration = self.migration()
        self.assertIn("create sequence public.prc_formula_codigo_seq", migration)
        self.assertIn("maxvalue 99999999 no cycle", migration)
        self.assertIn("'^fml-[0-9]{8}$'", migration)
        self.assertIn("pg_advisory_xact_lock", migration)

    def test_shadow_is_additive_and_does_not_replace_prc01(self):
        migration = self.migration()
        self.assertIn("prc_formula_shadow_execucoes", migration)
        self.assertIn("prc_formula_promocao_evidencias", migration)
        self.assertNotIn("create or replace function public.calcular_prc_cenario_idempotente", migration)
        self.assertNotIn("alter table public.prc_calculos", migration)

    def test_runtime_smoke_is_mandatory_in_database_contract(self):
        self.assertIn("tests/sql/prc02_versioned_formula_engine.sql", CI)
        self.assertIn("tests/sql/prc02_ast_safety.sql", CI)
        self.assertIn("tests/sql/prc02_formula_concurrency_worker.sql", CI)
        self.assertIn("tests/sql/prc02_upgrade_before_0151.sql", CI)
        self.assertIn("tests/sql/prc02_versioned_formula_engine_upgrade.sql", CI)

    def test_formula_and_shadow_bind_verified_grid_hash(self):
        migration = self.migration()
        self.assertIn("precificacao_internal.prc_grade_sha256", migration)
        self.assertIn("'term_grid_sha256',v_grid_sha", migration)
        self.assertIn("v_version.documento_sha256 is distinct from public.prc_sha256", migration)

    def test_alternative_profile_has_exactly_five_inputs(self):
        smoke = self.runtime_smoke()
        self.assertIn("array['materia_prima','embalagem','frete','markup','juros_mensais']", smoke)
        self.assertIn("pg_temp.values_alt()", smoke)
        self.assertIn("(10+2+1)*(1+0.20)", smoke)

    def test_behavioral_safety_and_real_upgrade_are_registered(self):
        safety = AST_SMOKE.read_text(encoding="utf-8").lower()
        for case in (
            "unknown operator", "unknown kind", "unexpected key", "depth 33",
            "513+ nodes", "missing parameter", "incompatible unit", "division by zero",
            "negative fractional power", "zero to zero", "power exponent cap", "decimal token cap",
        ):
            self.assertIn(case, safety)
        before = UPGRADE_BEFORE.read_text(encoding="utf-8").lower()
        after = UPGRADE_AFTER.read_text(encoding="utf-8").lower()
        self.assertIn("public.calcular_prc_cenario_idempotente", before)
        self.assertIn("public.prc02_upgrade_probe", after)
        self.assertIn("result_sha256", after)


if __name__ == "__main__":
    unittest.main()
