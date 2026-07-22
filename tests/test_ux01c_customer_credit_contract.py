from pathlib import Path
import unittest


ROOT = Path(__file__).resolve().parents[1]
CLIENTS = (ROOT / "apps/web/app/cadastros/clientes-section.tsx").read_text(encoding="utf-8")
MASTER_DATA = (ROOT / "apps/web/lib/master-data.ts").read_text(encoding="utf-8")
ORDERS_ACTIONS = (ROOT / "apps/web/app/pedidos/actions.ts").read_text(encoding="utf-8")


class Ux01cCustomerCreditContractTests(unittest.TestCase):
    def test_customer_search_covers_relational_record(self) -> None:
        for source in (
            "props.propriedades", "props.documentos", "props.contatos",
            "props.identificacoes", "props.estabelecimentos", "props.enderecos",
        ):
            self.assertIn(source, CLIENTS)
        for value in ("item.cnpj", "item.numero", "item.telefone", "item.email", "item.razaoSocial", "item.nomeFantasia", "item.cep"):
            self.assertIn(value, CLIENTS)
        self.assertIn("normalizeSearch", CLIENTS)

    def test_credit_remains_finance_owned_and_permission_checked(self) -> None:
        self.assertIn('p_action_key: "pedidos.credit.limit.adjust"', MASTER_DATA)
        self.assertIn("creditoGravacaoDisponivel", MASTER_DATA)
        self.assertIn("ajustarLimiteCreditoAction", CLIENTS)
        self.assertIn('name="justificativa_limite"', CLIENTS)
        self.assertIn('name="idempotency_key"', CLIENTS)
        self.assertIn("Você pode consultar o crédito, mas não possui alçada", CLIENTS)

    def test_credit_history_is_relational_and_read_only_in_ui(self) -> None:
        self.assertIn('from("cad_limite_credito_eventos")', MASTER_DATA)
        self.assertIn("clienteCreditoEventos", MASTER_DATA)
        self.assertIn("Histórico de crédito", CLIENTS)
        self.assertNotIn('.from("cad_limites_credito_cliente").update', CLIENTS)

    def test_credit_action_reuses_governed_idempotent_rpc_and_safe_return(self) -> None:
        self.assertIn('"ajustar_com_limite_credito_cliente_idempotente"', ORDERS_ACTIONS)
        self.assertIn("creditAdjustmentTarget", ORDERS_ACTIONS)
        self.assertIn("requestedPath === clientPath", ORDERS_ACTIONS)
        self.assertIn('revalidatePath("/cadastros")', ORDERS_ACTIONS)


if __name__ == "__main__":
    unittest.main()
