from __future__ import annotations

from pathlib import Path
import subprocess
import unittest


ROOT = Path(__file__).resolve().parents[1]
ACTION = ROOT / "apps" / "web" / "app" / "importacao-historica" / "mp" / "actions.ts"
WORKSPACE = ROOT / "apps" / "web" / "app" / "importacao-historica" / "mp" / "workbook-analysis.tsx"
PAGE = ROOT / "apps" / "web" / "app" / "importacao-historica" / "mp" / "page.tsx"
CONFIG = ROOT / "apps" / "web" / "next.config.mjs"


class HistoricalWorkbookWebContractTests(unittest.TestCase):
    @classmethod
    def setUpClass(cls) -> None:
        cls.action = ACTION.read_text(encoding="utf-8")
        cls.workspace = WORKSPACE.read_text(encoding="utf-8")
        cls.page = PAGE.read_text(encoding="utf-8")

    def test_server_bridge_is_local_read_only_and_permission_checked(self) -> None:
        self.assertIn('"use server"', self.action)
        self.assertIn('p_action_key: "migration.mp.view"', self.action)
        self.assertIn('runtime.databaseMode === "production"', self.action)
        self.assertIn('process.env.VERCEL === "1"', self.action)
        self.assertNotIn("auditedRpc", self.action)
        self.assertNotIn("service_role", self.action.casefold())
        self.assertNotIn(".insert(", self.action)
        self.assertNotIn(".update(", self.action)
        self.assertNotIn(".delete(", self.action)

    def test_temporary_workbook_is_removed_in_finally(self) -> None:
        self.assertIn("mkdtemp", self.action)
        self.assertIn("finally", self.action)
        self.assertIn("await rm(temporaryDirectory, { recursive: true, force: true })", self.action)
        self.assertIn('path.join(temporaryDirectory, "workbook.xlsx")', self.action)

    def test_python_bridge_has_an_explicit_utf8_transport_contract(self) -> None:
        self.assertIn('PYTHONIOENCODING: "utf-8"', self.action)
        self.assertIn('PYTHONUTF8: "1"', self.action)
        self.assertIn('new StringDecoder("utf8")', self.action)

    def test_interface_contains_required_controls_and_literal_notice(self) -> None:
        for expected in (
            'type="file"',
            "Analisar arquivo",
            "Baixar relatório CSV",
            "Esta etapa apenas analisa o arquivo. Nenhum dado será gravado no banco.",
            "SHA256",
            "Referências classificadas",
            "Tabelas classificadas",
            "Drift estrutural",
            "Aba",
            "Domínio",
            "Status",
        ):
            self.assertIn(expected, self.workspace)

    def test_metadata_report_has_formula_injection_guard(self) -> None:
        self.assertIn("analysis.reportRows", self.workspace)
        self.assertIn('"source_table_id"', self.workspace)
        self.assertIn('"classificacao_fonte"', self.workspace)
        self.assertIn("text/csv;charset=utf-8", self.workspace)
        self.assertIn("/^[=+\\-@]/", self.workspace)
        self.assertIn("URL.revokeObjectURL", self.workspace)

    def test_upload_limit_is_configured_without_new_dependency(self) -> None:
        config = CONFIG.read_text(encoding="utf-8")
        self.assertIn('bodySizeLimit: "32mb"', config)
        package = (ROOT / "apps" / "web" / "package.json").read_text(encoding="utf-8")
        self.assertNotIn('"xlsx"', package)
        self.assertNotIn('"exceljs"', package)

    def test_no_real_workbook_or_database_artifact_is_tracked(self) -> None:
        completed = subprocess.run(
            ["git", "ls-files"], cwd=ROOT, capture_output=True, text=True, check=True
        )
        forbidden_suffixes = (".xlsx", ".xls", ".sqlite", ".sqlite3", ".db", ".dump", ".backup")
        tracked = [line for line in completed.stdout.splitlines() if line.casefold().endswith(forbidden_suffixes)]
        self.assertEqual(tracked, [])


if __name__ == "__main__":
    unittest.main()
