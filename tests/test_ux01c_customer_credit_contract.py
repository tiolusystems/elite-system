from pathlib import Path
import unittest


ROOT = Path(__file__).resolve().parents[1]
CLIENTS = (ROOT / "apps/web/app/cadastros/clientes-section.tsx").read_text(encoding="utf-8")
MASTER_DATA = (ROOT / "apps/web/lib/master-data.ts").read_text(encoding="utf-8")
ORDERS_ACTIONS = (ROOT / "apps/web/app/pedidos/actions.ts").read_text(encoding="utf-8")
CADASTROS_PAGE = (ROOT / "apps/web/app/cadastros/page.tsx").read_text(encoding="utf-8")
CLIENT_SEARCH = (
    ROOT / "supabase/migrations/0117_govern_client_workbench_search.sql"
).read_text(encoding="utf-8")


class Ux01cCustomerCreditContractTests(unittest.TestCase):
    def test_customer_search_covers_relational_record(self) -> None:
        self.assertIn("consultar_cad_clientes_paginada", MASTER_DATA)
        for source in (
            "cad_cliente_propriedades",
            "cad_cliente_documentos",
            "cad_cliente_contatos",
            "cad_cliente_identificacoes",
            "cad_cliente_estabelecimentos",
            "cad_cliente_enderecos",
        ):
            self.assertIn(source, CLIENT_SEARCH)
        for value in (
            "property.cnpj",
            "customer_document.numero",
            "contact.telefone",
            "contact.email",
            "identification.razao_social",
            "identification.nome_fantasia",
            "address.cep",
        ):
            self.assertIn(value, CLIENT_SEARCH)
        self.assertIn("normalize_client_search_text", CLIENT_SEARCH)
        self.assertNotIn("normalizeSearch", CLIENTS)

    def test_credit_remains_finance_owned_and_permission_checked(self) -> None:
        self.assertIn('p_action_key: "financeiro.credit_limits.adjust"', MASTER_DATA)
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

    def test_customer_related_write_results_have_success_messages(self) -> None:
        for result, title in {
            "identification_saved": "Identificação atualizada",
            "document_created": "Documento adicionado",
            "contact_created": "Contato adicionado",
            "property_created": "Propriedade adicionada",
            "establishment_created": "Estabelecimento adicionado",
            "address_created": "Endereço adicionado",
        }.items():
            self.assertIn(result, CADASTROS_PAGE)
            self.assertIn(title, CADASTROS_PAGE)


if __name__ == "__main__":
    unittest.main()
