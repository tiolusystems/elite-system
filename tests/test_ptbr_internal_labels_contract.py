from __future__ import annotations

from pathlib import Path
import re
import unittest


ROOT = Path(__file__).resolve().parents[1]
UI_ROOT = ROOT / "apps" / "web" / "app"
LABELS = ROOT / "apps" / "web" / "lib" / "labels-ptbr.ts"

INTERNAL_VALUES = (
    "active", "inactive", "pending_review", "approved", "rejected", "draft",
    "planned", "in_process", "completed", "cancelled", "reversed", "available",
    "blocked", "read_only", "read_write", "disabled", "construction",
    "technical_validation", "business_validation",
)


class PtBrInternalLabelsContractTests(unittest.TestCase):
    def test_central_label_registry_covers_governed_values_and_safe_fallback(self) -> None:
        text = LABELS.read_text(encoding="utf-8")
        for value in INTERNAL_VALUES:
            self.assertIn(f'{value}: "', text)
        self.assertIn('"Situacao nao reconhecida"', text)

    def test_options_do_not_repeat_internal_english_value_as_visible_text(self) -> None:
        pattern = re.compile(r'<option[^>]*value="([a-z][a-z0-9_]*)"[^>]*>\s*\1\s*</option>')
        violations: list[str] = []
        for path in UI_ROOT.rglob("*.tsx"):
            for match in pattern.finditer(path.read_text(encoding="utf-8")):
                violations.append(f"{path.relative_to(ROOT)}: {match.group(1)}")
        self.assertEqual([], violations)

    def test_status_is_not_rendered_directly_as_visible_text(self) -> None:
        direct_status = re.compile(r">\s*\{[A-Za-z0-9_.]+\.status\}\s*<")
        violations: list[str] = []
        for path in UI_ROOT.rglob("*.tsx"):
            for match in direct_status.finditer(path.read_text(encoding="utf-8")):
                violations.append(f"{path.relative_to(ROOT)}: {match.group(0)}")
        self.assertEqual([], violations)


if __name__ == "__main__":
    unittest.main()
