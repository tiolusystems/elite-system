from pathlib import Path
import unittest


ROOT = Path(__file__).resolve().parents[1]
MIGRATION = ROOT / "supabase/migrations/0099_packaging_issue_request_idempotency.sql"
ACTIONS = ROOT / "apps/web/app/producao/envase/actions.ts"
WORKBENCH = ROOT / "apps/web/app/producao/envase/packaging-workbench.tsx"


class PackagingIssueRequestIdempotencyContractTests(unittest.TestCase):
    def test_request_map_is_append_only_and_serialized(self):
        sql = MIGRATION.read_text(encoding="utf-8")
        self.assertIn("create table public.pcp_ordem_envase_emissao_requisicoes", sql)
        self.assertIn("before update or delete", sql)
        self.assertIn("before truncate", sql)
        self.assertIn("pg_advisory_xact_lock", sql)
        self.assertIn("payload_hash", sql)

    def test_only_keyed_issue_entrypoint_is_exposed(self):
        sql = MIGRATION.read_text(encoding="utf-8")
        self.assertIn("emitir_pcp_op_mapa_com_envase_idempotente", sql)
        self.assertIn(
            "revoke all on function public.emitir_pcp_op_mapa_com_envase(bigint, bigint, bigint, numeric, text, text)",
            sql,
        )

    def test_web_supplies_stable_request_key(self):
        actions = ACTIONS.read_text(encoding="utf-8")
        workbench = WORKBENCH.read_text(encoding="utf-8")
        self.assertIn('"emitir_pcp_op_mapa_com_envase_idempotente"', actions)
        self.assertIn("p_idempotency_key: idempotencyKey", actions)
        self.assertIn("randomUUID()", workbench)
        self.assertIn('name="idempotency_key"', workbench)


if __name__ == "__main__":
    unittest.main()
