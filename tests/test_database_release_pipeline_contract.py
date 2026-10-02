from pathlib import Path
import unittest


ROOT = Path(__file__).resolve().parents[1]
WORKFLOW = (ROOT / ".github/workflows/ci.yml").read_text(encoding="utf-8")


class DatabaseReleasePipelineContract(unittest.TestCase):
    def _job(self, name: str) -> str:
        start = WORKFLOW.index(f"  {name}:")
        next_job = WORKFLOW.find("\n  deploy-database-", start + 1)
        return WORKFLOW[start:] if next_job == -1 else WORKFLOW[start:next_job]

    def test_manual_modes_and_deployment_jobs_are_governed(self):
        for action in (
            "none",
            "verify-staging",
            "apply-staging",
            "verify-production",
            "apply-production",
        ):
            self.assertIn(f"- {action}", WORKFLOW)

        staging = self._job("deploy-database-staging")
        production = self._job("deploy-database-production")
        for job in (staging, production):
            for dependency in ("python-tests", "web-contract", "database-contract"):
                self.assertIn(f"- {dependency}", job)
            self.assertIn("version: 2.109.0", job)
            self.assertIn("supabase db push --dry-run", job)
            self.assertLess(job.index("supabase db push --dry-run"), job.index("run: supabase db push\n"))
            self.assertIn("cancel-in-progress: false", job)

        self.assertIn("environment: elite-system-staging", staging)
        self.assertIn("refs/heads/staging", staging)
        self.assertIn("ELITE_STAGING_DB_DEPLOY_ENABLED", staging)
        self.assertIn("environment: elite-system-production", production)
        self.assertIn("refs/heads/main", production)
        self.assertIn("ELITE_PRODUCTION_DB_DEPLOY_ENABLED", production)
        self.assertNotIn("refs/heads/staging", production)

    def test_remote_release_jobs_forbid_unsafe_operations(self):
        self.assertNotIn("--include-seed", WORKFLOW)
        self.assertNotIn("db reset --linked", WORKFLOW)
        self.assertNotIn("migration repair", WORKFLOW)


if __name__ == "__main__":
    unittest.main()
