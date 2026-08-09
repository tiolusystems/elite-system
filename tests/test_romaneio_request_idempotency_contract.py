from pathlib import Path
import unittest


ROOT = Path(__file__).resolve().parents[1]
MIGRATION = ROOT / "supabase/migrations/0098_romaneio_request_idempotency.sql"
ACTIONS = ROOT / "apps/web/app/romaneios/actions.ts"
PREPARATION = ROOT / "apps/web/app/romaneios/romaneio-preparation.tsx"


class RomaneioRequestIdempotencyContractTests(unittest.TestCase):
    def test_request_map_is_append_only_and_serialized(self):
        sql = MIGRATION.read_text(encoding="utf-8")
        self.assertIn("create table public.exp_romaneio_requisicoes", sql)
        self.assertIn("before update or delete", sql)
        self.assertIn("before truncate", sql)
        self.assertIn("pg_advisory_xact_lock", sql)
        self.assertIn("payload_hash", sql)

    def test_only_keyed_save_entrypoint_is_exposed(self):
        sql = MIGRATION.read_text(encoding="utf-8")
        self.assertIn("gravar_exp_romaneio_pedido_idempotente", sql)
        self.assertIn(
            "revoke all on function public.gravar_exp_romaneio_pedido(bigint, jsonb)",
            sql,
        )
        self.assertNotIn(
            "grant execute on function public.gravar_exp_romaneio_pedido(bigint, jsonb)",
            sql,
        )

    def test_web_uses_stable_request_key(self):
        actions = ACTIONS.read_text(encoding="utf-8")
        preparation = PREPARATION.read_text(encoding="utf-8")
        self.assertIn('"gravar_exp_romaneio_pedido_idempotente"', actions)
        self.assertIn('p_idempotency_key: idempotencyKey', actions)
        self.assertIn('useState(() => crypto.randomUUID())', preparation)
        self.assertIn('name="idempotency_key"', preparation)


if __name__ == "__main__":
    unittest.main()
