from pathlib import Path
import re
import unittest


ROOT = Path(__file__).resolve().parents[1]
APP_ROOT = ROOT / "apps" / "web" / "app"
MATRIX_PATH = ROOT / "docs" / "validacoes" / "OPS_GATE_01_MATRIZ.md"


def route_for_file(path: Path) -> str:
    relative = path.relative_to(APP_ROOT)
    parts = relative.parts[:-1]
    return "/" + "/".join(parts) if parts else "/"


class OpsGateInventoryContractTests(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        cls.matrix = MATRIX_PATH.read_text(encoding="utf-8")

    def test_every_published_page_is_classified(self):
        routes = {route_for_file(page) for page in APP_ROOT.rglob("page.tsx")}
        missing = {route for route in routes if f"`{route}`" not in self.matrix}
        self.assertEqual(set(), missing)

    def test_every_published_route_handler_is_classified(self):
        routes = {route_for_file(route) for route in APP_ROOT.rglob("route.ts")}
        missing = {route for route in routes if f"`{route}`" not in self.matrix}
        self.assertEqual(set(), missing)

    def test_every_server_action_is_classified(self):
        action_names = set()
        for action_file in APP_ROOT.rglob("actions.ts"):
            action_names.update(
                re.findall(
                    r"export async function ([A-Za-z0-9_]+Action)",
                    action_file.read_text(encoding="utf-8"),
                )
            )
        missing = {name for name in action_names if f"`{name}`" not in self.matrix}
        self.assertEqual(set(), missing)

    def test_matrix_has_no_unclassified_state(self):
        self.assertNotIn("ainda nao testado", self.matrix.lower())
        for state in (
            "comprovado",
            "comprovado com ressalva",
            "bloqueado corretamente",
            "nao aplicavel",
        ):
            self.assertIn(state, self.matrix)


if __name__ == "__main__":
    unittest.main()
