from __future__ import annotations

from pathlib import Path
import subprocess
import unittest


ROOT = Path(__file__).resolve().parents[1]
GUARD = ROOT / "scripts" / "assert-disposable-supabase-target.ps1"
AGENTS = ROOT / "AGENTS.md"


class DisposableSupabaseValidationGuardTests(unittest.TestCase):
    def run_guard(self, *arguments: str) -> subprocess.CompletedProcess[str]:
        return subprocess.run(
            [
                "powershell",
                "-NoProfile",
                "-ExecutionPolicy",
                "Bypass",
                "-File",
                str(GUARD),
                *arguments,
            ],
            cwd=ROOT,
            check=False,
            capture_output=True,
            text=True,
        )

    def test_active_local_project_is_blocked_even_when_authorized(self) -> None:
        result = self.run_guard(
            "-TargetProjectId",
            "elite-system",
            "-Operation",
            "db-reset",
            "-TargetContainer",
            "supabase_db_elite-system",
            "-TargetVolume",
            "supabase_db_elite-system-data",
            "-ExplicitAuthorization",
        )

        self.assertEqual(result.returncode, 64)
        self.assertIn("ELITE_DESTRUCTIVE_VALIDATION_BLOCKED", result.stderr)
        self.assertIn("runtime local ativo", result.stderr)

    def test_explicit_authorization_is_required(self) -> None:
        result = self.run_guard(
            "-TargetProjectId",
            "elite-validation-0058",
            "-Operation",
            "db-reset",
            "-TargetContainer",
            "supabase_db_elite-validation-0058",
            "-TargetVolume",
            "supabase_db_elite-validation-0058-data",
        )

        self.assertEqual(result.returncode, 64)
        self.assertIn("autorizacao destrutiva explicita ausente", result.stderr)

    def test_separate_project_container_and_volume_are_accepted(self) -> None:
        result = self.run_guard(
            "-TargetProjectId",
            "elite-validation-0058",
            "-Operation",
            "db-reset",
            "-TargetContainer",
            "supabase_db_elite-validation-0058",
            "-TargetVolume",
            "supabase_db_elite-validation-0058-data",
            "-ExplicitAuthorization",
        )

        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertIn("ELITE_DISPOSABLE_TARGET_OK", result.stdout)

    def test_repository_contract_names_the_mandatory_guard(self) -> None:
        contract = AGENTS.read_text(encoding="utf-8")

        self.assertIn("assert-disposable-supabase-target.ps1", contract)
        self.assertIn("Nunca use o `project_id` ativo", contract)
        self.assertIn("container e volume proprios", contract)


if __name__ == "__main__":
    unittest.main()
