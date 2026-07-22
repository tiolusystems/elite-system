from pathlib import Path
import unittest


ROOT = Path(__file__).resolve().parents[1]
SMOKE = ROOT / "tests" / "sql" / "production_end_to_end_chain.sql"
CI = ROOT / ".github" / "workflows" / "ci.yml"


class ProductionEndToEndChainContractTests(unittest.TestCase):
    def test_smoke_covers_the_full_industrial_chain(self) -> None:
        source = SMOKE.read_text(encoding="utf-8")
        for operation in (
            "create_pcp_formula_versao",
            "create_pcp_op",
            "reservar_pcp_op_componente",
            "iniciar_pcp_op",
            "finalizar_pcp_op",
            "emitir_pcp_op_mapa_com_envase",
            "reservar_pcp_ordem_envase_embalagem",
            "iniciar_pcp_ordem_envase",
            "finalizar_pcp_ordem_envase",
            "consultar_est_estoque_pa_posicao",
        ):
            self.assertIn(operation, source)

        self.assertIn("exactly one PI lot", source)
        self.assertIn("exactly one PA lot", source)
        self.assertIn("rel_estoque_lotes_vencimento", source)
        self.assertIn("pcp.op.finish", source)
        self.assertIn("pcp.envase.finish", source)

    def test_smoke_is_transactional_and_ci_wired(self) -> None:
        source = SMOKE.read_text(encoding="utf-8").lower()
        ci = CI.read_text(encoding="utf-8")

        self.assertIn("begin;", source)
        self.assertIn("rollback;", source)
        self.assertIn("integrated production smoke requires disposable test environment", source)
        self.assertIn("PG_PRODUCTION_END_TO_END_CHAIN_OK", SMOKE.read_text(encoding="utf-8"))
        self.assertIn("tests/sql/production_end_to_end_chain.sql", ci)


if __name__ == "__main__":
    unittest.main()
