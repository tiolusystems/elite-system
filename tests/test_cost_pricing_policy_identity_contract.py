from pathlib import Path
import json
import subprocess
import textwrap
import unittest


ROOT = Path(__file__).resolve().parents[1]
MIGRATION = (ROOT / "supabase/migrations/0150_govern_prc_policy_identity.sql").read_text(encoding="utf-8")
SMOKE = (ROOT / "tests/sql/cost_pricing_iso_foundation.sql").read_text(encoding="utf-8")
FORMS = (ROOT / "apps/web/app/custos-precos/pricing-action-forms.tsx").read_text(encoding="utf-8")
PAGE = (ROOT / "apps/web/app/custos-precos/page.tsx").read_text(encoding="utf-8")
VALIDATION_MODULE = (ROOT / "apps/web/app/custos-precos/pricing-form-validation.ts").as_uri()


def validate(script: str):
    process = subprocess.run(
        ["node", "--experimental-strip-types", "--input-type=module", "--eval", script],
        cwd=ROOT,
        capture_output=True,
        text=True,
        check=False,
    )
    if process.returncode:
        raise AssertionError(process.stderr)
    return json.loads(process.stdout)


class CostPricingPolicyIdentityContract(unittest.TestCase):
    def test_policy_validation_accepts_human_percentages_and_omits_client_code(self):
        result = validate(textwrap.dedent(f"""
            import {{ validatePolicy }} from \"{VALIDATION_MODULE}\";
            const form = (values) => {{ const data = new FormData(); for (const [key, value] of Object.entries(values)) data.append(key, value); return data; }};
            const common = {{ nome: \"Politica operacional\", metodo: \"margem_liquida\", markup: \"\", motivo: \"Justificativa operacional valida\", codigo: \"POL-FORGED\" }};
            const created = validatePolicy(form({{ ...common, politica_id: \"\", lucro_minimo: \"30%\", juros_mensais: \"1,9%\" }}));
            const versioned = validatePolicy(form({{ ...common, politica_id: \"7\", lucro_minimo: \"2%\", juros_mensais: \"1.9\" }}));
            console.log(JSON.stringify({{ created: created.payload, versioned: versioned.payload }}));
        """))
        self.assertEqual(result["created"]["p_lucro_minimo"], 0.3)
        self.assertEqual(result["created"]["p_juros_mensais"], 0.019)
        self.assertNotIn("p_codigo", result["created"])
        self.assertEqual(result["versioned"]["p_politica_id"], 7)
        self.assertIsNone(result["versioned"]["p_nome"])

    def test_database_issues_codes_and_retires_the_client_code_overload(self):
        self.assertIn("create sequence if not exists public.prc_politica_codigo_seq", MIGRATION)
        self.assertIn("format('POL-%s', lpad(nextval('public.prc_politica_codigo_seq')::text, 8, '0'))", MIGRATION)
        self.assertIn("drop function public.salvar_prc_politica_versao_idempotente(uuid,text,text,text,numeric,numeric,numeric,text)", MIGRATION)
        self.assertIn("p_politica_id bigint", MIGRATION)
        self.assertNotIn("p_codigo text", MIGRATION)
        self.assertIn("revoke all on sequence public.prc_politica_codigo_seq from public, anon, authenticated", MIGRATION)
        self.assertIn("codigos automaticos repetidos", SMOKE)
        self.assertIn("sobrecarga legada por codigo permaneceu executavel", SMOKE)

    def test_existing_policy_versioning_and_idempotency_stay_serialized(self):
        self.assertIn("perform public.prc_lock_idempotency_key(p_key)", MIGRATION)
        self.assertLess(MIGRATION.index("perform public.prc_lock_idempotency_key(p_key)"), MIGRATION.index("v_existing := public.prc_idempotent_result"))
        self.assertIn("perform pg_advisory_xact_lock(hashtextextended('prc-policy:' || v_policy.id::text, 0))", MIGRATION)
        self.assertIn("insert into public.prc_requisicoes", MIGRATION)
        self.assertIn("nova versao nao reutilizou a politica existente", SMOKE)
        self.assertIn("retry de politica duplicou fato", SMOKE)

    def test_policy_form_selects_existing_identity_without_a_code_input(self):
        self.assertIn("PricingPolicyForm({ policies }", FORMS)
        self.assertIn('name="politica_id"', FORMS)
        self.assertIn("Nova politica", FORMS)
        self.assertIn("Codigo e nome sao definidos pelo sistema.", FORMS)
        self.assertNotIn('name="codigo"', FORMS)
        self.assertIn("`${policy.codigo} - ${policy.nome}`", PAGE)


if __name__ == "__main__":
    unittest.main()
