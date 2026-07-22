from __future__ import annotations

from pathlib import Path
import unittest


ROOT = Path(__file__).resolve().parents[1]
MIGRATION = ROOT / "supabase" / "migrations" / "0090_restore_historical_mp_audited_rpc_access.sql"
FOUNDATION = ROOT / "supabase" / "migrations" / "0045_historical_mp_import_foundation.sql"


class HistoricalMpRpcAccessContractTests(unittest.TestCase):
    def test_only_audited_import_entrypoints_are_restored(self) -> None:
        migration = MIGRATION.read_text(encoding="utf-8").lower()
        foundation = FOUNDATION.read_text(encoding="utf-8").lower()

        entrypoints = (
            "stage_migration_mp_items",
            "approve_migration_mp_mapping",
            "register_migration_mp_acquisition_value",
        )
        for function in entrypoints:
            with self.subTest(function=function):
                self.assertIn(f"grant execute on function public.{function}", migration)
                self.assertIn("to authenticated", migration)
                self.assertIn(f"revoke all on function public.{function}", migration)

                start = foundation.index(f"create or replace function public.{function}")
                end = foundation.index("$$;", start)
                body = foundation[start:end]
                self.assertIn("security definer", body)
                self.assertIn("public.begin_audited_rpc(", body)
                self.assertIn("public.log_audited_rpc_change(", body)

        self.assertNotIn("prevent_historical_mp_fact_changes", migration)
        self.assertNotIn("enforce_historical_mp_source_lineage", migration)
        self.assertNotIn("enforce_historical_mp_batch_row_consistency", migration)

    def test_public_and_anon_remain_denied(self) -> None:
        migration = MIGRATION.read_text(encoding="utf-8").lower()
        self.assertEqual(migration.count(" from public;"), 3)
        self.assertEqual(migration.count(" from anon;"), 3)
        self.assertNotIn("to anon", migration)
        self.assertNotIn("to public", migration)


if __name__ == "__main__":
    unittest.main()
