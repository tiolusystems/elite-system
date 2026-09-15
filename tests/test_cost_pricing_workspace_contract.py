from pathlib import Path
import json
import subprocess
import textwrap
import unittest


ROOT = Path(__file__).resolve().parents[1]
VALIDATION_MODULE = (ROOT / "apps/web/app/custos-precos/pricing-form-validation.ts").as_uri()
ACTION_STATE_MODULE = (ROOT / "apps/web/app/custos-precos/pricing-action-state.ts").as_uri()
FORMS = (ROOT / "apps/web/app/custos-precos/pricing-action-forms.tsx").read_text(encoding="utf-8")
ACTION_STATE = (ROOT / "apps/web/app/custos-precos/pricing-action-state.ts").read_text(encoding="utf-8")
ACTIONS = (ROOT / "apps/web/app/custos-precos/actions.ts").read_text(encoding="utf-8")
PAGE = (ROOT / "apps/web/app/custos-precos/page.tsx").read_text(encoding="utf-8")
LOADING = (ROOT / "apps/web/app/custos-precos/loading.tsx").read_text(encoding="utf-8")


def execute_validation(script: str):
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


class CostPricingWorkspaceContract(unittest.TestCase):
    def test_human_percentages_are_converted_and_invalid_formats_are_rejected(self):
        script = textwrap.dedent(
            f"""
            import {{ parsePercentage, percentageWarning, validatePolicy, validateScenario }} from "{VALIDATION_MODULE}";
            const form = (values) => {{ const data = new FormData(); for (const [key, value] of Object.entries(values)) data.append(key, value); return data; }};
            const policy = (method, margin, markup, interest) => validatePolicy(form({{
              codigo: "POL-01", nome: "Politica operacional", metodo: method, lucro_minimo: margin, markup,
              juros_mensais: interest, motivo: "Justificativa operacional valida"
            }}));
            const scenario = validateScenario(form({{
              politica_versao_id: "1", produto_embalagem_id: "2", nome: "Cenario operacional", motivo: "Motivo operacional valido",
              source_kind: "substituicao_manual", source_reference: "MAN-01", source_effective_date: "2026-09-15", source_reason: "Substituicao manual valida",
              materia_prima: "12,5", embalagem: "1.5", custo_pontuacao_vendedor: "0", custo_pontuacao_revenda: "0", premiacao_revenda: "0", premio_producao: "0", frete: "1",
              comissao: "2", risco: "3,5", marketing: "1", tributacao: "4"
            }}));
            console.log(JSON.stringify({{
              margin: policy("margem_liquida", "30", "25", "1,9").payload,
              markup: policy("markup", "30", "25", "1.9").payload,
              scenario: scenario.payload,
              literalSmall: parsePercentage("0,2"),
              literalSmallWarning: percentageWarning("0,2"),
              invalidThousands: parsePercentage("1.234,56"),
              invalidMixed: parsePercentage("1,234.56"),
              invalidMargin: policy("margem_liquida", "100", "", "1").fieldErrors,
               invalidMarginPayload: policy("margem_liquida", "100", "", "1").payload,
               invalidNegative: policy("markup", "", "-1", "1").fieldErrors,
               fixtureSource: validateScenario(form({{
                 politica_versao_id: "1", produto_embalagem_id: "2", nome: "Cenario operacional", motivo: "Motivo operacional valido",
                 source_kind: "fixture_validacao", source_reference: "SIM-01", source_effective_date: "2026-09-15", source_reason: "Fonte sintetica valida",
                 materia_prima: "12,5", embalagem: "1.5", custo_pontuacao_vendedor: "0", custo_pontuacao_revenda: "0", premiacao_revenda: "0", premio_producao: "0", frete: "1",
                 comissao: "2", risco: "3,5", marketing: "1", tributacao: "4"
               }})).fieldErrors
            }}));
            """
        )
        result = execute_validation(script)
        self.assertEqual(result["margin"]["p_lucro_minimo"], 0.3)
        self.assertIsNone(result["margin"]["p_markup"])
        self.assertEqual(result["margin"]["p_juros_mensais"], 0.019)
        self.assertEqual(result["markup"]["p_markup"], 0.25)
        self.assertIsNone(result["markup"]["p_lucro_minimo"])
        self.assertEqual(result["markup"]["p_juros_mensais"], 0.019)
        self.assertEqual(result["scenario"]["p_componentes"][7]["valor"], 0.02)
        self.assertEqual(result["scenario"]["p_componentes"][8]["valor"], 0.035)
        self.assertEqual(result["scenario"]["p_componentes"][9]["valor"], 0.01)
        self.assertEqual(result["scenario"]["p_componentes"][10]["valor"], 0.04)
        self.assertEqual(result["literalSmall"], 0.002)
        self.assertEqual(result["literalSmallWarning"], "0,2 significa 0,2%. Para 20%, digite 20.")
        self.assertIsNone(result["invalidThousands"])
        self.assertIsNone(result["invalidMixed"])
        self.assertIn("lucro_minimo", result["invalidMargin"])
        self.assertIsNone(result["invalidMarginPayload"])
        self.assertIn("markup", result["invalidNegative"])
        self.assertIn("source_kind", result["fixtureSource"])

    def test_forms_keep_feedback_local_and_accessible_without_action_redirects(self):
        self.assertIn("useActionState", FORMS)
        self.assertIn("role={isError ? \"alert\" : \"status\"}", FORMS)
        self.assertIn("aria-live={isError ? \"assertive\" : \"polite\"}", FORMS)
        self.assertIn("restoreValues(formRef.current, state.values)", FORMS)
        self.assertIn("focusProblem(formRef.current, feedbackRef.current)", FORMS)
        self.assertIn("disabled={pending}", FORMS)
        self.assertIn("aria-invalid", FORMS)
        self.assertIn("aria-describedby", FORMS)
        self.assertIn("router.refresh()", FORMS)
        self.assertNotIn("redirect(", ACTIONS)
        self.assertIn("if (rejected) return rejected;", ACTIONS)
        self.assertIn("prc_politica_versoes_check", ACTIONS)
        self.assertIn("Codigo de ocorrencia", FORMS)
        self.assertIn("dismissedServerErrorState", FORMS)
        self.assertIn("clientValidation.resultId === state.resultId", FORMS)
        self.assertIn("dismissedServerErrorState.resultId === state.resultId", FORMS)
        self.assertIn('source_kind" value="substituicao_manual"', FORMS)
        self.assertNotIn('option value="fixture_validacao"', FORMS)

    def test_initial_render_is_safe_before_first_action(self):
        self.assertIn('fieldErrors: {},', ACTION_STATE)
        self.assertIn('values: {},', ACTION_STATE)
        self.assertIn('status: "idle"', ACTION_STATE)
        self.assertIn('export function normalizePricingActionState(value: unknown)', ACTION_STATE)
        self.assertIn('const [rawState, formAction, pending] = useActionState', FORMS)
        self.assertIn('const state = normalizePricingActionState(rawState)', FORMS)
        self.assertIn('Object.entries(state.fieldErrors ?? {})', FORMS)
        self.assertIn('Object.entries(values ?? {})', FORMS)
        self.assertIn('if (safeState.status === "idle" && !localMessage) return null;', FORMS)
        self.assertIn('export function PricingPolicyForm()', FORMS)
        self.assertIn('export function PricingScenarioForm(', FORMS)
        self.assertIn('INITIAL_PRICING_ACTION_STATE, normalizePricingActionState, type PricingActionState } from "./pricing-action-state";', FORMS)
        self.assertNotIn('INITIAL_PRICING_ACTION_STATE,', FORMS.split('} from "./actions";', 1)[0])

    def test_state_normalization_handles_pre_action_nullish_fields(self):
        script = textwrap.dedent(
            f"""
            import {{ INITIAL_PRICING_ACTION_STATE, normalizePricingActionState }} from "{ACTION_STATE_MODULE}";
            console.log(JSON.stringify({{
              initial: normalizePricingActionState(INITIAL_PRICING_ACTION_STATE),
              empty: normalizePricingActionState(null),
              partial: normalizePricingActionState({{ status: "idle", fieldErrors: null, values: null, message: null, resultId: null, occurrenceId: null }}),
              error: normalizePricingActionState({{ status: "error", fieldErrors: {{ nome: "Obrigatorio" }}, values: {{ nome: "Teste" }}, message: "Falhou", resultId: "r1", occurrenceId: "o1" }})
            }}));
            """
        )
        result = execute_validation(script)
        self.assertEqual(result["initial"], {"status": "idle", "message": "", "fieldErrors": {}, "values": {}, "resultId": "", "occurrenceId": None})
        self.assertEqual(result["empty"], result["initial"])
        self.assertEqual(result["partial"], result["initial"])
        self.assertEqual(result["error"]["fieldErrors"], {"nome": "Obrigatorio"})
        self.assertEqual(result["error"]["values"], {"nome": "Teste"})

    def test_unavailable_workspace_is_not_presented_as_an_empty_workspace(self):
        self.assertIn("if (!data) return", PAGE)
        self.assertIn("Consulta indisponivel", PAGE)
        self.assertIn('aria-live="assertive"', PAGE)
        self.assertIn('aria-busy="true"', LOADING)
        self.assertIn("Carregando a memoria de custos e precos.", LOADING)


if __name__ == "__main__":
    unittest.main()
