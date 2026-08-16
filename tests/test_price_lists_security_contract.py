from pathlib import Path
import re
import unittest


ROOT = Path(__file__).resolve().parents[1]
MIGRATION = ROOT / "supabase" / "migrations" / "0124_govern_canonical_price_lists.sql"
SMOKE = ROOT / "tests" / "sql" / "price_lists_canonical_foundation.sql"


class PriceListSecurityContractTests(unittest.TestCase):
    @classmethod
    def setUpClass(cls) -> None:
        cls.sql = MIGRATION.read_text(encoding="utf-8").lower()
        cls.smoke = SMOKE.read_text(encoding="utf-8").lower()

    def test_operational_rpcs_check_permission_before_domain_validation(self) -> None:
        names = (
            "create_com_lista_preco_rascunho_idempotente",
            "create_com_lista_preco_versao_idempotente",
            "replace_com_lista_preco_rascunho_idempotente",
            "publish_com_lista_preco_versao_idempotente",
            "withdraw_com_lista_preco_publicacao_idempotente",
        )
        for name in names:
            match = re.search(
                rf"create or replace function public\.{name}\(.*?\nas \$\$(.*?)\nend;\n\$\$;",
                self.sql,
                re.DOTALL,
            )
            self.assertIsNotNone(match, name)
            body = match.group(1)
            self.assertIn("begin_audited_rpc", body)
            self.assertLess(body.index("begin_audited_rpc"), body.index("is null"))

    def test_operational_rpcs_are_not_exposed_to_anon_or_public(self) -> None:
        self.assertNotRegex(self.sql, r"grant execute on function .* to (anon|public)")
        for name in (
            "create_com_lista_preco_rascunho_idempotente",
            "create_com_lista_preco_versao_idempotente",
            "replace_com_lista_preco_rascunho_idempotente",
            "publish_com_lista_preco_versao_idempotente",
            "withdraw_com_lista_preco_publicacao_idempotente",
            "consultar_com_lista_preco_versao",
        ):
            self.assertRegex(
                self.sql,
                rf"revoke all on function public\.{name}\(.*?\) from public, anon;",
            )

    def test_internal_helpers_are_not_callable_by_authenticated(self) -> None:
        for name in (
            "com_lista_preco_versao_documento",
            "prevent_com_lista_preco_fact_changes",
            "protect_com_lista_preco_published_content",
        ):
            self.assertRegex(
                self.sql,
                rf"revoke all on function public\.{name}\(.*?\) from public, anon, authenticated;",
            )

    def test_default_deny_smoke_uses_valid_payload_and_exact_permission_error(self) -> None:
        self.assertIn("'negada0124', 'lista sem alcada 0124'", self.smoke)
        self.assertIn("not allowed: pedidos.price_lists.draft.manage", self.smoke)
        self.assertIn("negacao nao veio da camada de permissao", self.smoke)


if __name__ == "__main__":
    unittest.main()
