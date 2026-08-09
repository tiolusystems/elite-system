from __future__ import annotations

from pathlib import Path
import unittest


ROOT = Path(__file__).resolve().parents[1]
MIGRATION = ROOT / "supabase" / "migrations" / "0112_fix_romaneio_envase_density_chain.sql"
SMOKE = ROOT / "tests" / "sql" / "production_end_to_end_chain.sql"


class RomaneioEnvaseLoadDensityContractTests(unittest.TestCase):
    def test_view_follows_envase_to_the_operational_pi_cq(self) -> None:
        text = MIGRATION.read_text(encoding="utf-8")

        for contract in (
            "create or replace view public.exp_romaneio_carga_resumo",
            "with (security_invoker = true)",
            "public.pcp_ordem_envase_lotes_pa",
            "public.pcp_ordens_envase",
            "produto_pi.lote_pi_id = envase.lote_pi_origem_id",
            "public.pcp_op_cq_resultados",
            "produto_pa.tipo_produto = 'PA'",
        ):
            self.assertIn(contract, text)

        self.assertNotIn(
            "join public.pcp_op_produtos_gerados gerado on gerado.lote_pa_id",
            text,
        )

    def test_view_keeps_minimum_privilege(self) -> None:
        text = MIGRATION.read_text(encoding="utf-8")

        self.assertIn(
            "revoke all on public.exp_romaneio_carga_resumo from public, anon, authenticated;",
            text,
        )
        self.assertIn(
            "grant select on public.exp_romaneio_carga_resumo to authenticated;",
            text,
        )
        self.assertNotIn("grant all", text.lower())

    def test_integrated_smoke_asserts_envase_load_measurements(self) -> None:
        text = SMOKE.read_text(encoding="utf-8")

        for contract in (
            "exp_romaneio_carga_resumo",
            "envase PA load did not use the operational PI CQ density",
            "v_load.peso_liquido_kg <> 5",
            "v_load.peso_bruto_kg <> 5.25",
            "v_load.itens_sem_densidade <> 0",
            "romaneio load summary is not security_invoker",
            "romaneio load summary privileges are broader than authenticated read",
        ):
            self.assertIn(contract, text)


if __name__ == "__main__":
    unittest.main()
