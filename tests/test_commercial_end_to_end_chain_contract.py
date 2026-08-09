from pathlib import Path
import unittest

ROOT = Path(__file__).resolve().parents[1]


class CommercialEndToEndChainContractTests(unittest.TestCase):
    def test_ci_executes_the_transactional_commercial_chain(self):
        workflow = (ROOT / ".github/workflows/ci.yml").read_text(encoding="utf-8")
        self.assertIn("tests/sql/commercial_end_to_end_chain.sql", workflow)

    def test_chain_covers_approval_receipt_commission_and_rollback(self):
        sql = (ROOT / "tests/sql/commercial_end_to_end_chain.sql").read_text(encoding="utf-8")
        for contract in (
            "registrar_com_pedido_decisao_gerencial",
            "definir_com_pedido_comissao",
            "registrar_com_recebimento",
            "registrar_fin_comissao_pagamento",
            "valor_liberado",
            "saldo_aberto",
            "action_logs",
            "rollback;",
            "PG_COMMERCIAL_END_TO_END_CHAIN_OK",
        ):
            self.assertIn(contract, sql)


if __name__ == "__main__":
    unittest.main()
