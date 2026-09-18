from pathlib import Path
import json
import subprocess
import textwrap
import unittest


ROOT = Path(__file__).resolve().parents[1]
VALIDATION_MODULE = (ROOT / "apps/web/app/custos-precos/pricing-form-validation.ts").as_uri()
ACTION_STATE_MODULE = (ROOT / "apps/web/app/custos-precos/pricing-action-state.ts").as_uri()
FORM_DOM_MODULE = (ROOT / "apps/web/app/custos-precos/pricing-form-dom.ts").as_uri()
FORMS = (ROOT / "apps/web/app/custos-precos/pricing-action-forms.tsx").read_text(encoding="utf-8")
ACTION_STATE = (ROOT / "apps/web/app/custos-precos/pricing-action-state.ts").read_text(encoding="utf-8")
FORM_DOM = (ROOT / "apps/web/app/custos-precos/pricing-form-dom.ts").read_text(encoding="utf-8")
PRICING_CSS = (ROOT / "apps/web/app/custos-precos/pricing.module.css").read_text(encoding="utf-8")
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
            const policy = (method, margin, markup, interest, politica_id = "") => validatePolicy(form({{
              politica_id, codigo: "POL-FORGED", nome: "Politica operacional", metodo: method, lucro_minimo: margin, markup,
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
              marginWithSymbol: policy("margem_liquida", "30%", "", "1,9%").payload,
              decimalWithSymbol: policy("markup", "", "30,5%", "1.9%").payload,
              existing: policy("margem_liquida", "2%", "", "1%", "7").payload,
              scenario: scenario.payload,
              literalSmall: parsePercentage("0,2"),
              literalSmallWarning: percentageWarning("0,2"),
              invalidThousands: parsePercentage("1.234,56"),
              invalidMixed: parsePercentage("1,234.56"),
              invalidPolicyId: policy("margem_liquida", "2", "", "1", "forged").fieldErrors,
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
        self.assertEqual(result["marginWithSymbol"]["p_lucro_minimo"], 0.3)
        self.assertEqual(result["marginWithSymbol"]["p_juros_mensais"], 0.019)
        self.assertEqual(result["decimalWithSymbol"]["p_markup"], 0.305)
        self.assertEqual(result["decimalWithSymbol"]["p_juros_mensais"], 0.019)
        self.assertEqual(result["existing"]["p_politica_id"], 7)
        self.assertIsNone(result["existing"]["p_nome"])
        self.assertEqual(result["scenario"]["p_componentes"][7]["valor"], 0.02)
        self.assertEqual(result["scenario"]["p_componentes"][8]["valor"], 0.035)
        self.assertEqual(result["scenario"]["p_componentes"][9]["valor"], 0.01)
        self.assertEqual(result["scenario"]["p_componentes"][10]["valor"], 0.04)
        self.assertEqual(result["literalSmall"], 0.002)
        self.assertEqual(result["literalSmallWarning"], "0,2 significa 0,2%. Para 20%, digite 20.")
        self.assertIsNone(result["invalidThousands"])
        self.assertIsNone(result["invalidMixed"])
        self.assertIn("politica_id", result["invalidPolicyId"])
        self.assertIn("lucro_minimo", result["invalidMargin"])
        self.assertIsNone(result["invalidMarginPayload"])
        self.assertIn("markup", result["invalidNegative"])
        self.assertIn("source_kind", result["fixtureSource"])

    def test_forms_keep_feedback_local_and_accessible_without_action_redirects(self):
        self.assertIn("useActionState", FORMS)
        self.assertIn("role={isError ? \"alert\" : \"status\"}", FORMS)
        self.assertIn("aria-live={isError ? \"assertive\" : \"polite\"}", FORMS)
        self.assertIn("restoreValues(formRef.current, state.values)", FORMS)
        self.assertIn("revealPricingFeedback(feedbackRef.current, window.innerHeight)", FORMS)
        self.assertIn("if (state.status !== \"error\" && !localMessage) return;", FORMS)
        self.assertIn("disabled={pending || !ready}", FORMS)
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

    def test_css_module_controls_the_responsive_form_layout(self):
        self.assertIn('import styles from "./pricing.module.css";', FORMS)
        for class_name in ("pricingForm", "pricingInlineForm", "pricingComponents", "pricingWide", "pricingFeedback", "pricingFieldError", "pricingHelp", "pricingPolicyIdentity", "pricingSubmit"):
            self.assertIn(f"styles.{class_name}", FORMS)
        self.assertIn(".pricingForm{display:grid;grid-template-columns:repeat(3,minmax(0,1fr))", PRICING_CSS)
        self.assertIn(".pricingWide{grid-column:span 2}", PRICING_CSS)
        self.assertIn(".pricingForm input,.pricingForm select", PRICING_CSS)
        self.assertIn("width:100%", PRICING_CSS)
        self.assertIn("@media(max-width:900px){.pricingForm,.pricingComponents{grid-template-columns:repeat(2,minmax(0,1fr))}", PRICING_CSS)
        self.assertIn("@media(max-width:600px){.pricingForm,.pricingComponents,.loading{grid-template-columns:1fr}", PRICING_CSS)
        self.assertNotIn(".pricing-form", PRICING_CSS)
        self.assertNotIn("notApplicable=", FORMS)
        self.assertNotIn('name="codigo"', FORMS)

    def test_initial_render_is_safe_before_first_action(self):
        self.assertIn('fieldErrors: {},', ACTION_STATE)
        self.assertIn('values: {},', ACTION_STATE)
        self.assertIn('status: "idle"', ACTION_STATE)
        self.assertIn('export function normalizePricingActionState(value: unknown)', ACTION_STATE)
        self.assertIn('const [rawState, formAction, pending] = useActionState', FORMS)
        self.assertIn('const state = useMemo(() => normalizePricingActionState(rawState), [rawState]);', FORMS)
        self.assertIn('useMemo', FORMS)
        self.assertIn('Object.entries(state.fieldErrors ?? {})', FORMS)
        self.assertIn('Object.entries(values ?? {})', FORMS)
        self.assertIn('if (safeState.status === "idle" && !localMessage) return null;', FORMS)
        self.assertIn('export function PricingPolicyForm({ policies }', FORMS)
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

    def test_first_render_reads_values_without_dom_globals(self):
        script = textwrap.dedent(
            f"""
            import {{ readFormControlValue, revealPricingFeedback, writeFormControlValue }} from "{FORM_DOM_MODULE}";
            const controls = {{ lucro_minimo: {{ value: "20" }}, markup: {{ value: "25" }}, juros_mensais: {{ value: "1,9" }}, materia_prima: {{ value: "12,5" }} }};
            const form = {{ elements: {{ namedItem: (name) => controls[name] ?? null }} }};
            const documentState = {{ activeElement: {{ tagName: "INPUT" }} }};
            const feedback = {{
              tagName: "SECTION", focused: false, scrolled: false,
              getBoundingClientRect: () => ({{ top: 720, bottom: 780 }}),
              focus: () => {{ documentState.activeElement = feedback; feedback.focused = true; }},
              scrollIntoView: () => {{ feedback.scrolled = true; }},
            }};
            writeFormControlValue(form, "markup", "30");
            console.log(JSON.stringify({{
              lucro: readFormControlValue(form, "lucro_minimo"), markup: readFormControlValue(form, "markup"), juros: readFormControlValue(form, "juros_mensais"), scenario: readFormControlValue(form, "materia_prima"), missing: readFormControlValue(null, "lucro_minimo"),
              revealed: revealPricingFeedback(feedback, 600), feedbackFocused: feedback.focused, feedbackScrolled: feedback.scrolled, activeElement: documentState.activeElement.tagName
            }}));
            """
        )
        result = execute_validation(script)
        self.assertEqual({name: result[name] for name in ("lucro", "markup", "juros", "scenario", "missing")}, {"lucro": "20", "markup": "30", "juros": "1,9", "scenario": "12,5", "missing": ""})
        self.assertTrue(result["revealed"])
        self.assertTrue(result["feedbackFocused"])
        self.assertTrue(result["feedbackScrolled"])
        self.assertNotIn(result["activeElement"], {"INPUT", "SELECT", "TEXTAREA"})
        self.assertNotIn("HTMLInputElement", FORM_DOM)
        self.assertNotIn("HTMLSelectElement", FORM_DOM)
        self.assertNotIn("instanceof", FORM_DOM)
        self.assertNotIn("focusProblem", FORMS)
        self.assertNotIn("querySelector<HTMLElement>(\"[aria-invalid='true']\")", FORMS)
        self.assertNotIn("input.focus", FORMS)
        self.assertNotIn("document.activeElement", FORMS)
        self.assertIn("export function revealPricingFeedback", FORM_DOM)
        self.assertIn("feedback.focus({ preventScroll: true })", FORM_DOM)
        self.assertIn('feedback.scrollIntoView({ behavior: "smooth", block: "nearest" })', FORM_DOM)

    def test_unavailable_workspace_is_not_presented_as_an_empty_workspace(self):
        self.assertIn("if (!data) return", PAGE)
        self.assertIn("Consulta indisponivel", PAGE)
        self.assertIn('aria-live="assertive"', PAGE)
        self.assertIn('aria-busy="true"', LOADING)
        self.assertIn("Carregando a memoria de custos e precos.", LOADING)


if __name__ == "__main__":
    unittest.main()
