from pathlib import Path
import re
import unittest


ROOT = Path(__file__).resolve().parents[1]
WORKFLOW = (ROOT / ".github/workflows/ci.yml").read_text(encoding="utf-8")


class DatabaseReleasePipelineContract(unittest.TestCase):
    def _job(self, name: str) -> str:
        start = WORKFLOW.index(f"  {name}:")
        next_job = re.search(r"\n  [a-z][a-z0-9-]+:\n", WORKFLOW[start + 1 :])
        end = len(WORKFLOW) if next_job is None else start + 1 + next_job.start()
        return WORKFLOW[start:end]

    def test_ci_push_trigger_is_limited_to_canonical_branches(self):
        triggers = WORKFLOW[WORKFLOW.index("on:\n") : WORKFLOW.index("\njobs:\n")]

        self.assertIn(
            "  push:\n    branches:\n      - staging\n      - main\n",
            triggers,
        )
        self.assertIn("  pull_request:\n", triggers)
        self.assertIn("  workflow_dispatch:\n", triggers)
        self.assertNotIn("- ci/", triggers)
        self.assertNotIn("- feature/", triggers)

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
        verify_production = self._job("verify-database-production")
        approve_production = self._job("approve-database-production-apply")
        apply_production = self._job("apply-database-production")

        for job in (verify_production, approve_production, apply_production):
            condition = re.search(
                r"    if: >\n(?P<value>.*?)\n    runs-on:", job, re.DOTALL
            )
            self.assertIsNotNone(condition)
            self.assertEqual(
                condition.group("value").count("("),
                condition.group("value").count(")"),
            )

        for job in (staging, verify_production, apply_production):
            for dependency in ("python-tests", "web-contract", "database-contract"):
                if job != apply_production:
                    self.assertIn(f"- {dependency}", job)
            self.assertIn("version: 2.109.0", job)
            self.assertIn("SUPABASE_DB_PASSWORD", job)
            self.assertIn("SUPABASE_PROJECT_ID", job)
            self.assertIn("SUPABASE_POOLER_HOST", job)
            self.assertIn("Prepare direct database connection", job)
            self.assertIn("urllib.parse.quote", job)
            self.assertIn("safe=\"\"", job)
            self.assertIn("::add-mask::$db_url", job)
            self.assertIn("sslmode=require", job)
            self.assertIn("supabase db push --db-url \"$SUPABASE_DB_URL\" --dry-run", job)
            self.assertIn("supabase migration list --db-url \"$SUPABASE_DB_URL\"", job)
            self.assertIn("cancel-in-progress: false", job)

        self.assertIn("environment: elite-system-staging", staging)
        self.assertIn("refs/heads/staging", staging)
        self.assertIn("ELITE_STAGING_DB_DEPLOY_ENABLED", staging)
        self.assertIn("environment: elite-system-production", verify_production)
        self.assertIn("workflow_dispatch", verify_production)
        self.assertIn("refs/heads/main", verify_production)
        self.assertIn("verify-production", verify_production)
        self.assertIn("apply-production", verify_production)
        self.assertNotIn("github.event_name == 'push'", verify_production)
        self.assertNotIn("run: supabase db push --db-url \"$SUPABASE_DB_URL\"\n", verify_production)

        self.assertIn("needs: verify-database-production", approve_production)
        self.assertIn("environment: elite-system-production-approval", approve_production)
        self.assertIn("inputs.database_action == 'apply-production'", approve_production)
        for forbidden in (
            "SUPABASE_DB_PASSWORD",
            "SUPABASE_PROJECT_ID",
            "SUPABASE_POOLER_HOST",
            "SUPABASE_DB_URL",
            "supabase/setup-cli",
            "supabase db",
            "supabase migration",
        ):
            self.assertNotIn(forbidden, approve_production)

        self.assertIn("needs: approve-database-production-apply", apply_production)
        self.assertIn("environment: elite-system-production", apply_production)
        self.assertIn("workflow_dispatch", apply_production)
        self.assertIn("refs/heads/main", apply_production)
        self.assertIn("inputs.database_action == 'apply-production'", apply_production)
        self.assertNotIn("github.event_name == 'push'", apply_production)
        self.assertLess(
            apply_production.index("Verify production migration ledger before apply"),
            apply_production.index("Dry-run production migrations before apply"),
        )
        self.assertLess(
            apply_production.index("Dry-run production migrations before apply"),
            apply_production.index("run: supabase db push --db-url \"$SUPABASE_DB_URL\"\n"),
        )
        production_jobs = "\n".join((verify_production, approve_production, apply_production))
        self.assertEqual(
            production_jobs.count("run: supabase db push --db-url \"$SUPABASE_DB_URL\"\n"),
            1,
        )
        self.assertNotIn("ELITE_PRODUCTION_DB_DEPLOY_ENABLED", WORKFLOW)
        self.assertNotIn("refs/heads/staging", production_jobs)

    def test_remote_release_jobs_forbid_unsafe_operations(self):
        self.assertNotIn("supabase link", WORKFLOW)
        self.assertNotIn("SUPABASE_ACCESS_TOKEN", WORKFLOW)
        self.assertNotIn("--include-seed", WORKFLOW)
        self.assertNotIn("db reset --linked", WORKFLOW)
        self.assertNotIn("migration repair", WORKFLOW)


if __name__ == "__main__":
    unittest.main()
