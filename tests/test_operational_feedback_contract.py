from pathlib import Path
import unittest


ROOT = Path(__file__).resolve().parents[1]
FEEDBACK = (ROOT / "apps" / "web" / "app" / "operational-feedback.tsx").read_text(encoding="utf-8")
CADASTROS = (ROOT / "apps" / "web" / "app" / "cadastros" / "page.tsx").read_text(encoding="utf-8")
CATALOG = (ROOT / "apps" / "web" / "app" / "cadastros" / "tecnicos" / "catalog-shell.tsx").read_text(encoding="utf-8")
CSS = (ROOT / "apps" / "web" / "app" / "globals.css").read_text(encoding="utf-8")


class OperationalFeedbackContractTests(unittest.TestCase):
    def test_feedback_is_viewport_layered_and_responsive(self) -> None:
        self.assertIn('className={`operational-feedback ${kind}`}', FEEDBACK)
        self.assertIn("position: fixed", CSS)
        self.assertIn("z-index: 80", CSS)
        self.assertIn("@media (max-width: 640px)", CSS)
        self.assertIn("width: calc(100vw - 24px)", CSS)

    def test_success_warning_and_error_have_distinct_semantics(self) -> None:
        self.assertIn('export type OperationalFeedbackKind = "ok" | "warning" | "error"', FEEDBACK)
        self.assertIn('role={isSuccess ? "status" : "alert"}', FEEDBACK)
        self.assertIn('aria-live={isSuccess ? "polite" : "assertive"}', FEEDBACK)
        self.assertIn("window.setTimeout(() => setVisible(false), 5000)", FEEDBACK)
        self.assertIn(".operational-feedback.error", CSS)

    def test_feedback_can_close_without_rewriting_navigation_or_scrolling(self) -> None:
        self.assertIn('aria-label="Fechar mensagem"', FEEDBACK)
        self.assertIn("onClick={() => setVisible(false)}", FEEDBACK)
        self.assertNotIn("scrollTo", FEEDBACK)
        self.assertNotIn("scrollIntoView", FEEDBACK)
        self.assertNotIn("router.", FEEDBACK)

    def test_cadastros_and_technical_catalogs_share_the_feedback_surface(self) -> None:
        self.assertIn('import { OperationalFeedback } from "@/app/operational-feedback"', CADASTROS)
        self.assertIn("<OperationalFeedback kind={formMessage.kind}", CADASTROS)
        self.assertIn('import { OperationalFeedback } from "@/app/operational-feedback"', CATALOG)
        self.assertIn("<OperationalFeedback kind={feedback.kind}", CATALOG)


if __name__ == "__main__":
    unittest.main()
