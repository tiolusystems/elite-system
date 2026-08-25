from pathlib import Path
import unittest


ROOT = Path(__file__).resolve().parents[1]
MIGRATION = ROOT / "supabase" / "migrations" / "0125_stage_price_list_xlsx_imports.sql"
OPERATIONAL_MIGRATION = ROOT / "supabase" / "migrations" / "0137_govern_price_list_operational_xlsx.sql"
SMOKE = ROOT / "tests" / "sql" / "price_list_xlsx_import.sql"
CI = ROOT / ".github" / "workflows" / "ci.yml"


class PriceListXlsxImportContractTests(unittest.TestCase):
    @classmethod
    def setUpClass(cls) -> None:
        cls.sql = MIGRATION.read_text(encoding="utf-8").lower()

    def test_reuses_source_lineage_and_preserves_raw_and_normalized_values(self) -> None:
        for table in ("source_workbooks", "source_tables", "source_rows", "migration_batches"):
            self.assertIn(f"public.{table}", self.sql)
        self.assertIn("valor_bruto_texto text", self.sql)
        self.assertIn("valor_bruto numeric", self.sql)
        self.assertIn("valor_normalizado numeric(20,2)", self.sql)
        self.assertIn("valor_centavos_por_litro bigint", self.sql)
        self.assertIn("round(v_valor, 2)", self.sql)
        for column in (
            "coluna_produto text not null",
            "coluna_embalagem text not null",
            "coluna_preco text not null",
            "celula_preco text not null",
        ):
            self.assertIn(column, self.sql)
        self.assertIn("valor normalizado diverge da celula fonte", self.sql)
        self.assertIn("celula de preco diverge da linha de origem", self.sql)
        self.assertIn("normalizar_com_lista_preco_valor_bruto", self.sql)

    def test_single_worksheet_and_workbook_hash_are_enforced(self) -> None:
        self.assertIn("jsonb_array_length(p_tabelas) <> 1", self.sql)
        self.assertIn("workbook_repetido", self.sql)
        self.assertIn("esta planilha ja foi importada", self.sql)
        self.assertLess(
            self.sql.index("pg_advisory_xact_lock(hashtextextended(lower(p_workbook_sha256), 0))"),
            self.sql.index("select importacao.* into v_existing"),
        )

    def test_reconciliation_is_relational_and_fails_closed(self) -> None:
        self.assertIn("references public.cad_produtos_base(id)", self.sql)
        self.assertIn("references public.cad_produto_embalagens(id)", self.sql)
        self.assertIn("produto_nao_encontrado", self.sql)
        self.assertIn("produto_ambiguo", self.sql)
        self.assertIn("apresentacao_nao_encontrada", self.sql)
        self.assertIn("apresentacao_ambigua", self.sql)
        self.assertIn("duplicidade_preco", self.sql)
        self.assertIn("unique (importacao_id, source_row_id, prazo_dias, celula_preco)", self.sql)
        self.assertIn("importacao possui linhas nao conciliadas; nao pode aplicar", self.sql)
        self.assertNotIn("insert into public.cad_produtos_base", self.sql)
        self.assertNotIn("insert into public.cad_produto_embalagens", self.sql)

    def test_writes_are_governed_default_deny_and_idempotent(self) -> None:
        for action in ("pedidos.price_lists.import.stage", "pedidos.price_lists.import.apply"):
            self.assertIn(action, self.sql)
        self.assertIn("default_allowed", self.sql)
        self.assertIn("false, 130", self.sql)
        self.assertIn("false, 131", self.sql)
        self.assertGreaterEqual(self.sql.count("pg_advisory_xact_lock"), 2)
        self.assertIn("enable row level security", self.sql)
        self.assertIn("revoke all on table public.com_lista_preco_importacoes", self.sql)
        self.assertIn("revoke all on function public.stage_com_lista_preco_xlsx_import_idempotente", self.sql)
        self.assertIn("grant execute on function public.stage_com_lista_preco_xlsx_import_idempotente", self.sql)

        operational_sql = OPERATIONAL_MIGRATION.read_text(encoding="utf-8").lower()
        self.assertIn(
            "revoke execute on function public.stage_com_lista_preco_xlsx_import_idempotente",
            operational_sql,
        )
        self.assertIn(
            "revoke execute on function public.apply_com_lista_preco_import_idempotente",
            operational_sql,
        )

    def test_smoke_and_ci_cover_the_governed_import(self) -> None:
        smoke = SMOKE.read_text(encoding="utf-8").lower()
        ci = CI.read_text(encoding="utf-8")
        for expected in (
            "produto_nao_encontrado",
            "produto_ambiguo",
            "apresentacao_nao_encontrada",
            "preco bruto arredondado",
            "retry do staging",
            "workbook repetido",
            "valor normalizado adulterado",
            "duplicidade de apresentacao e prazo",
            "importacao bloqueada foi aplicada",
        ):
            self.assertIn(expected, smoke)
        self.assertIn("tests/sql/price_list_xlsx_import.sql", ci)
        self.assertIn("tests/sql/price_list_operational_xlsx.sql", ci)


if __name__ == "__main__":
    unittest.main()
