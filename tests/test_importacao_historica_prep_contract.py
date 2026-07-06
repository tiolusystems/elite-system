from __future__ import annotations

import re
import unittest
from pathlib import Path


REPO_ROOT = Path(__file__).resolve().parents[1]
MIGRATION_0034 = REPO_ROOT / "supabase" / "migrations" / "0034_historical_import_prep.sql"
DECISION_DOC = REPO_ROOT / "docs" / "decisao_importacao_historica_prep.md"
RECIPE_DOC = REPO_ROOT / "docs" / "receita_rls_rpc_auditada.md"
VALIDATION_DOC = REPO_ROOT / "docs" / "validacao_importacao_historica_prep.md"


class HistoricalImportPrepContractTests(unittest.TestCase):
    def test_system_actor_is_explicit_and_inactive(self) -> None:
        sql = MIGRATION_0034.read_text(encoding="utf-8").lower()

        self.assertIn("add column if not exists is_system_actor boolean not null default false", sql)
        self.assertIn("add column if not exists system_actor_key text", sql)
        self.assertIn("user_profiles_system_actor_inactive_check", sql)
        self.assertIn("is_system_actor = false or status = 'inactive'", sql)
        self.assertIn("'migracao_historica'", sql)
        self.assertIn("'migracao historica'", sql)
        self.assertIn("'auditoria'", sql)
        self.assertNotIn("status = 'active',\n        true,\n        'migracao_historica'", sql)

    def test_historical_origin_columns_exist_on_expected_tables(self) -> None:
        sql = MIGRATION_0034.read_text(encoding="utf-8").lower()
        expected_tables = [
            "com_pedidos",
            "com_pedido_itens",
            "cad_clientes",
            "cad_pessoas_comerciais",
            "cad_materias_primas",
            "cad_produtos_base",
            "cad_embalagens",
            "cad_produto_embalagens",
        ]

        for table in expected_tables:
            with self.subTest(table=table):
                self.assertIn(f"'{table}'", sql)

        self.assertIn("add column if not exists origem_dados text", sql)
        self.assertIn("add column if not exists codigo_legado text", sql)
        self.assertIn("origem_dados in (''sistema'', ''excel_legado'')", sql)

    def test_no_importer_or_real_data_is_added(self) -> None:
        sql = MIGRATION_0034.read_text(encoding="utf-8").lower()

        forbidden_patterns = [
            r"create\s+or\s+replace\s+function\s+public\.importar_",
            r"\.xlsx",
            r"\.xlsm",
            r"copy\s+",
        ]

        for pattern in forbidden_patterns:
            with self.subTest(pattern=pattern):
                self.assertIsNone(re.search(pattern, sql))

    def test_docs_record_legacy_data_rule_and_pending_decisions(self) -> None:
        docs = "\n".join(
            (
                DECISION_DOC.read_text(encoding="utf-8"),
                RECIPE_DOC.read_text(encoding="utf-8"),
                VALIDATION_DOC.read_text(encoding="utf-8"),
            )
        ).lower()

        self.assertIn("nao devem assumir implicitamente que todo registro nasceu por uma rpc ao vivo", docs)
        self.assertIn("decisoes pendentes para luciano", docs)
        self.assertIn("nf, recebimentos, romaneios, lotes e movimentos de estoque", docs)
        self.assertIn("pg_validate_0034_with_smoke_ok", docs)


if __name__ == "__main__":
    unittest.main()
