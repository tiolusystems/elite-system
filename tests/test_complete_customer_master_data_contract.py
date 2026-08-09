from pathlib import Path
import unittest


ROOT = Path(__file__).resolve().parents[1]
SQL = (ROOT / "supabase" / "migrations" / "0084_complete_customer_master_data.sql").read_text(encoding="utf-8")
UI = (ROOT / "apps" / "web" / "app" / "cadastros" / "clientes-section.tsx").read_text(encoding="utf-8")
ACTIONS = (ROOT / "apps" / "web" / "app" / "cadastros" / "actions.ts").read_text(encoding="utf-8")


class CompleteCustomerMasterDataContractTests(unittest.TestCase):
    def test_additive_relational_model_keeps_credit_in_finance(self):
        for table in ("cad_cliente_identificacoes", "cad_cliente_estabelecimentos", "cad_cliente_enderecos"):
            self.assertIn(f"create table public.{table}", SQL)
        self.assertNotIn("alter table public.cad_clientes add column", SQL.lower())
        self.assertNotIn("update public.cad_limites_credito_cliente", SQL.lower())

    def test_rls_and_direct_write_denial(self):
        for table in ("cad_cliente_identificacoes", "cad_cliente_estabelecimentos", "cad_cliente_enderecos"):
            self.assertIn(f"alter table public.{table} enable row level security", SQL)
        self.assertIn("revoke insert, update, delete, truncate", SQL)
        self.assertNotRegex(SQL.lower(), r"grant\s+execute[^;]+\s+to\s+(anon|public)")
        self.assertRegex(SQL.lower(), r"grant\s+execute[^;]+\s+to\s+authenticated")

    def test_governed_rpcs_are_audited(self):
        for function in (
            "upsert_cad_cliente_identificacao", "create_cad_cliente_documento", "create_cad_cliente_contato",
            "create_cad_cliente_propriedade", "create_cad_cliente_estabelecimento", "create_cad_cliente_endereco"
        ):
            self.assertIn(f"function public.{function}", SQL)
            self.assertIn(f'"{function}"', ACTIONS)
        self.assertGreaterEqual(SQL.count("begin_audited_rpc"), 6)
        self.assertGreaterEqual(SQL.count("log_audited_rpc_change"), 6)

    def test_customer_workbench_has_all_sections(self):
        for label in ("Resumo", "Identificação", "Documentos", "Estabelecimentos e propriedades", "Endereços", "Contatos", "Comercial", "Crédito", "Histórico"):
            self.assertIn(label, UI)
        self.assertIn("Administrado pelo Financeiro", UI)
        self.assertNotIn("status_credito}", UI)

    def test_document_normalization_and_no_destructive_cascade(self):
        self.assertIn("normalize_customer_document", SQL)
        self.assertIn("on delete restrict", SQL)
        self.assertNotIn("on delete cascade", SQL)
        self.assertNotIn("drop table", SQL.lower())
        self.assertNotIn("delete from", SQL.lower())


if __name__ == "__main__":
    unittest.main()
