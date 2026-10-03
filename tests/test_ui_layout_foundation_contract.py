from pathlib import Path
import unittest


ROOT = Path(__file__).resolve().parents[1]
COMPONENTS = (ROOT / "apps/web/app/workspace-components.tsx").read_text(encoding="utf-8")
GLOBAL_CSS = (ROOT / "apps/web/app/globals.css").read_text(encoding="utf-8")
PAGE = (ROOT / "apps/web/app/custos-precos/page.tsx").read_text(encoding="utf-8")
PRICING_CSS = (ROOT / "apps/web/app/custos-precos/pricing.module.css").read_text(encoding="utf-8")
TEST_SOURCE = Path(__file__).read_text(encoding="utf-8")
OPERATIONAL_START = ".operational-workspace {"
OPERATIONAL_END = "/* UX-SYS-01 Fase 2: canonical workflow guide"
OPERATIONAL_START_INDEX = GLOBAL_CSS.index(OPERATIONAL_START)
OPERATIONAL_END_INDEX = GLOBAL_CSS.index(OPERATIONAL_END, OPERATIONAL_START_INDEX)
OPERATIONAL_CSS = GLOBAL_CSS[OPERATIONAL_START_INDEX:OPERATIONAL_END_INDEX]
OPERATIONAL_BASE_CSS = OPERATIONAL_CSS.split("@media", 1)[0]


class UiLayoutFoundationContract(unittest.TestCase):
    def test_shared_operational_shell_is_available_and_responsive(self):
        self.assertEqual(OPERATIONAL_BASE_CSS.count(OPERATIONAL_START), 1)

        for selector in (
            ".governed-workflow-stepper",
            ".operational-context-panel",
            "@media (max-width: 1179px)",
            "@media (max-width: 900px)",
            "@media (max-width: 600px)",
        ):
            self.assertIn(selector, OPERATIONAL_CSS)

        for unrelated_selector in (
            ".clients-workbench",
            ".order-signature-panel",
            ".finance-manual-topic-card",
        ):
            self.assertNotIn(unrelated_selector, OPERATIONAL_CSS)

        for component in (
            "OperationalWorkspace",
            "OperationalPageHeader",
            "GovernedWorkflowStepper",
            "OperationalWorkspaceLayout",
            "OperationalWorkspaceSurface",
            "OperationalWorkspaceBody",
            "OperationalContextPanel",
            "OperationalStageHeader",
        ):
            self.assertIn(f"export function {component}", COMPONENTS)

        for selector in (
            ".operational-page-header",
            ".operational-page-facts",
            ".governed-workflow-stepper",
            ".operational-workspace-layout",
            ".operational-workspace-surface",
            ".operational-context-panel",
            ".operational-stage-header",
        ):
            self.assertIn(selector, GLOBAL_CSS)

        self.assertIn("overflow-x: auto", GLOBAL_CSS)
        self.assertIn("display: flex", OPERATIONAL_CSS)
        self.assertIn("width: max-content", OPERATIONAL_CSS)
        self.assertIn("min-width: 100%", OPERATIONAL_CSS)
        self.assertIn("flex: 1 0 152px", OPERATIONAL_CSS)
        self.assertNotIn("grid-template-columns: repeat(5", OPERATIONAL_CSS)
        self.assertIn('grid-template-areas: "context" "stage"', GLOBAL_CSS)
        self.assertIn("@media (max-width: 900px)", GLOBAL_CSS)
        self.assertIn("@media (max-width: 600px)", GLOBAL_CSS)

    def test_workflow_state_and_id_contracts_are_closed_and_generic(self):
        self.assertIn("export type GovernedWorkflowState =", COMPONENTS)
        for state in ("complete", "available", "waiting", "blocked", "neutral"):
            self.assertIn(f'| "{state}"', COMPONENTS)
        self.assertNotIn("state: string", COMPONENTS)
        self.assertNotIn('"quiet"', COMPONENTS)
        self.assertIn("export type GovernedWorkflowStep<TId extends string>", COMPONENTS)
        self.assertIn("readonly id: TId;", COMPONENTS)
        self.assertIn("readonly href: string;", COMPONENTS)
        self.assertIn("readonly title: string;", COMPONENTS)
        self.assertIn("readonly label: string;", COMPONENTS)
        self.assertIn("readonly state: GovernedWorkflowState;", COMPONENTS)
        self.assertIn("type GovernedWorkflowStepperProps<TId extends string> =", COMPONENTS)
        self.assertIn("steps: readonly GovernedWorkflowStep<TId>[];", COMPONENTS)
        self.assertIn("selectedId: NoInfer<TId>;", COMPONENTS)
        self.assertIn("currentId: NoInfer<TId>;", COMPONENTS)
        self.assertIn("export function GovernedWorkflowStepper<const TId extends string>", COMPONENTS)
        self.assertNotIn(" any", COMPONENTS)
        self.assertNotIn("type StageState", PAGE)
        self.assertIn('state: pendingReviews ? "waiting" : approvedCalculations ? "neutral" : "blocked"', PAGE)

    def test_selected_view_and_current_process_step_have_distinct_semantics(self):
        self.assertIn("const isSelected = step.id === selectedId;", COMPONENTS)
        self.assertIn("const isCurrent = step.id === currentId;", COMPONENTS)
        self.assertIn('aria-current={isSelected ? "page" : undefined}', COMPONENTS)
        self.assertNotIn('aria-current={step.id === selectedId ? "step" : undefined}', COMPONENTS)
        self.assertIn("data-current={isCurrent || undefined}", COMPONENTS)
        self.assertIn("Etapa atual do processo", COMPONENTS)
        self.assertIn("governed-workflow-stepper-current\"", COMPONENTS)
        self.assertIn("governed-workflow-stepper-current-sr", COMPONENTS)
        self.assertNotIn("<em", COMPONENTS)
        self.assertIn('a[aria-current="page"]', GLOBAL_CSS)
        self.assertNotIn('a[aria-current="step"]', GLOBAL_CSS)

    def test_facts_context_and_stage_header_have_stable_structural_contracts(self):
        self.assertIn("readonly id: string;", COMPONENTS)
        self.assertIn("readonly label: string;", COMPONENTS)
        self.assertIn("readonly value: ReactNode;", COMPONENTS)
        self.assertIn("facts?: readonly WorkspaceFact[]", COMPONENTS)
        self.assertIn("rows: readonly WorkspaceFact[];", COMPONENTS)
        self.assertIn("key={fact.id}", COMPONENTS)
        self.assertIn("key={row.id}", COMPONENTS)
        self.assertIn("note?: ReactNode;", COMPONENTS)
        self.assertIn("{note != null ? <small>{note}</small> : null}", COMPONENTS)
        self.assertIn("<dl>", COMPONENTS)
        self.assertIn("<dt>{row.label}</dt>", COMPONENTS)
        self.assertIn("<dd>{row.value}</dd>", COMPONENTS)
        self.assertNotIn("<strong>{row.value}</strong>", COMPONENTS)
        self.assertIn("state: GovernedWorkflowState;", COMPONENTS)
        self.assertIn("data-state={state}", COMPONENTS)
        for fact_id in (
            'id: "policies"',
            'id: "scenarios"',
            'id: "calculations"',
            'id: "current-stage"',
            'id: "next-action"',
            'id: "responsible"',
            'id: "situation"',
        ):
            self.assertIn(fact_id, PAGE)
        self.assertIn("state={selectedStageInfo.state}", PAGE)

    def test_workspace_root_is_limited_to_main_or_div(self):
        self.assertIn('as?: "main" | "div";', COMPONENTS)
        self.assertIn('as = "main"', COMPONENTS)
        self.assertIn('if (as === "div")', COMPONENTS)
        self.assertIn("return <div", COMPONENTS)
        self.assertIn("return <main", COMPONENTS)
        self.assertNotIn("ElementType", COMPONENTS)

    def test_workspace_body_owns_stage_content_spacing(self):
        self.assertIn("export function OperationalWorkspaceBody", COMPONENTS)
        self.assertIn('className="operational-workspace-body"', COMPONENTS)
        self.assertIn("<OperationalWorkspaceBody>{stageContent}</OperationalWorkspaceBody>", PAGE)
        self.assertIn(".operational-workspace-body { padding-top: 22px; }", GLOBAL_CSS)
        self.assertNotIn(".operational-workspace-surface > :not(.operational-stage-header)", GLOBAL_CSS)

    def test_operational_tokens_are_canonical_compact_and_only_used_by_operational_css(self):
        root_block = GLOBAL_CSS.split("}", 1)[0]
        self.assertEqual(GLOBAL_CSS.count(":root"), 1)
        for token in (
            "--operational-workspace-max-width",
            "--operational-workspace-text",
            "--operational-workspace-muted",
            "--operational-workspace-border",
            "--operational-workspace-surface",
            "--operational-workspace-surface-muted",
            "--operational-workspace-surface-hover",
            "--operational-workspace-accent",
            "--operational-workspace-accent-strong",
            "--operational-workspace-accent-muted",
            "--operational-workspace-shadow",
            "--operational-workspace-shadow-subtle",
        ):
            self.assertIn(token, root_block)

        self.assertNotIn("--operational-workspace-muted-surface", GLOBAL_CSS)
        self.assertNotIn("#", OPERATIONAL_CSS)
        for pricing_selector in (".pricing", ".cost-", ".scenario", ".policy"):
            self.assertNotIn(pricing_selector, OPERATIONAL_CSS)

    def test_screen_reader_only_current_step_marker_remains_accessible(self):
        sr_start = GLOBAL_CSS.index(".governed-workflow-stepper-current-sr")
        sr_rule = GLOBAL_CSS[sr_start:GLOBAL_CSS.index("}", sr_start)]
        for declaration in (
            "position: absolute",
            "width: 1px",
            "height: 1px",
            "padding: 0",
            "margin: -1px",
            "overflow: hidden",
            "white-space: nowrap",
            "border: 0",
            "clip:",
            "clip-path:",
        ):
            self.assertIn(declaration, sr_rule)
        self.assertNotIn("display: none", sr_rule)
        self.assertNotIn("visibility: hidden", sr_rule)

    def test_shared_components_remain_domain_neutral_and_without_test_tautologies(self):
        for term in (
            "Politica comercial",
            "Cenario",
            "Precos e prazos",
            "Revisao e dossie",
            "Custo tecnico",
        ):
            self.assertNotIn(term, COMPONENTS)

        self.assertNotIn("if" + " False", TEST_SOURCE)
        self.assertNotIn("assert" + ".assert", TEST_SOURCE)

    def test_pricing_consumes_the_shared_shell_without_reintroducing_it(self):
        self.assertIn('from "../workspace-components"', PAGE)
        for component in (
            "OperationalWorkspace",
            "OperationalPageHeader",
            "GovernedWorkflowStepper",
            "OperationalWorkspaceLayout",
            "OperationalWorkspaceSurface",
            "OperationalWorkspaceBody",
            "OperationalContextPanel",
            "OperationalStageHeader",
        ):
            self.assertIn(component, PAGE)

        for selector in (
            ".workspace{",
            ".heading{",
            ".headerFacts",
            ".workflowStepper",
            ".workspaceLayout",
            ".activeStage",
            ".workspaceContext",
            ".stageHeading",
            ".stageTitle",
            ".stageDescription",
        ):
            self.assertNotIn(selector, PRICING_CSS)

    def test_existing_shared_public_components_and_pricing_governance_remain_available(self):
        for component in (
            "PageWorkspace",
            "PageHeader",
            "WorkflowGuide",
            "DomainNavigation",
            "DomainShell",
            "ExportMenu",
            "Panel",
            "FormSection",
            "EmptyState",
            "ErrorState",
            "PermissionState",
        ):
            self.assertIn(f"export function {component}", COMPONENTS)

        self.assertIn("normalizeStage(params.etapa, workflow.current.id)", PAGE)
        self.assertEqual(PAGE.count('const stageContent = selectedStage === "base-custo"'), 1)
        self.assertIn('pendingReviews ? "revisao-dossie"', PAGE)
        self.assertIn('approvedCalculations.length ? approvedCalculations.map', PAGE)
        self.assertIn("Custo tecnico automatico ainda nao calculado", PAGE)


if __name__ == "__main__":
    unittest.main()
