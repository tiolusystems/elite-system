from pathlib import Path
import unittest


ROOT = Path(__file__).resolve().parents[1]
MIGRATION = ROOT / "supabase" / "migrations" / "0137_govern_price_list_operational_xlsx.sql"
PARSER = ROOT / "apps" / "web" / "lib" / "price-list-xlsx.ts"
ACTIONS = ROOT / "apps" / "web" / "app" / "pedidos" / "listas-precos" / "actions.ts"
PAGE = ROOT / "apps" / "web" / "app" / "pedidos" / "listas-precos" / "page.tsx"
COMPONENT = ROOT / "apps" / "web" / "app" / "pedidos" / "listas-precos" / "price-list-import-panel.tsx"
SMOKE = ROOT / "tests" / "sql" / "price_list_operational_xlsx.sql"
CI = ROOT / ".github" / "workflows" / "ci.yml"
E2E_BOOTSTRAP = ROOT / "apps" / "web" / "e2e" / "bootstrap-synthetic-users.mjs"
E2E_SPEC = ROOT / "apps" / "web" / "e2e" / "price-list-xlsx-workspace.spec.mjs"


class PriceListOperationalXlsxContractTests(unittest.TestCase):
    @classmethod
    def setUpClass(cls) -> None:
        cls.migration = MIGRATION.read_text(encoding="utf-8").lower()
        cls.parser = PARSER.read_text(encoding="utf-8")
        cls.actions = ACTIONS.read_text(encoding="utf-8")
        cls.page = PAGE.read_text(encoding="utf-8")
        cls.component = COMPONENT.read_text(encoding="utf-8")
        cls.smoke = SMOKE.read_text(encoding="utf-8").lower()

    def test_template_has_exact_governed_sheets_and_stable_code_columns(self) -> None:
        for sheet in ("INSTRUCOES", "LISTA", "PRECOS", "CATALOGOS"):
            self.assertIn(f'"{sheet}"', self.parser)
        for column in (
            "codigo_lista",
            "codigo_produto",
            "codigo_apresentacao",
            "unidade_precificacao",
            "fator_por_apresentacao",
            "pmp_min_dias",
            "pmp_max_dias",
            "preco_unitario",
        ):
            self.assertIn(f'"{column}"', self.parser)
        self.assertIn("addTable", self.parser)
        self.assertIn('views = [{ state: "frozen"', self.parser)

    def test_parser_rejects_structural_and_authoritative_cell_errors(self) -> None:
        for contract in (
            "PRICE_LIST_XLSX_MAX_BYTES",
            "PRICE_LIST_XLSX_MAX_ROWS = 10_000",
            "inspectXlsxArchive(bytes)",
            "PRICE_LIST_XLSX_MAX_UNCOMPRESSED_BYTES",
            "PRICE_LIST_XLSX_MAX_ENTRY_BYTES",
            "PRICE_LIST_XLSX_MAX_COMPRESSION_RATIO",
            "validateWorksheetDimensions",
            "O arquivo nao e um XLSX valido",
            "As abas LISTA e PRECOS sao obrigatorias",
            "Cabecalho duplicado",
            "Desconhecidos:",
            "A aba LISTA deve possuir exatamente uma linha",
            "A aba PRECOS deve possuir ao menos uma linha",
        ):
            self.assertIn(contract, self.parser)
        self.assertIn("formulas", self.parser)
        self.assertIn("`${letter}${row.number}`", self.parser)
        self.assertIn('createHash("sha256")', self.parser)

    def test_row_hash_uses_one_ordered_cross_runtime_document(self) -> None:
        self.assertIn("canonicalPriceListRowDocument(canonical)", self.parser)
        self.assertIn('"price-list-row-v1"', self.parser)
        self.assertIn("postgresJsonArray", self.parser)
        self.assertIn("canonicalDecimal", self.parser)
        self.assertIn("ord01_price_list_xlsx_row_document", self.migration)
        self.assertIn("ord01_price_list_xlsx_row_sha256", self.migration)
        self.assertIn("v_row_hash is distinct from v_recomputed_row_hash", self.migration)
        self.assertLess(
            self.migration.index("v_row_hash is distinct from v_recomputed_row_hash"),
            self.migration.index("insert into public.source_rows"),
        )

    def test_database_binds_by_codes_and_treats_names_as_warnings(self) -> None:
        for exact_code_lookup in (
            "upper(btrim(product.codigo_produto)) = v_codigo_produto",
            "upper(btrim(presentation.codigo_item)) = v_codigo_apresentacao",
            "lower(btrim(unit.codigo)) = v_codigo_unidade",
        ):
            self.assertIn(exact_code_lookup, self.migration)
        self.assertIn("nome importado difere do cadastro", self.migration)
        self.assertNotIn("produto.nome_normalizado =", self.migration)
        self.assertNotIn("insert into public.cad_produtos_base", self.migration)
        self.assertNotIn("insert into public.cad_produto_embalagens", self.migration)
        self.assertIn("lista_id bigint references public.com_listas_preco", self.migration)
        self.assertIn("nome da lista importado difere do cadastro", self.migration)
        self.assertIn("v_lista_id := v_analysis.lista_id", self.migration)
        self.assertNotIn("rename", self.migration)

    def test_pmp_ranges_are_an_order_independent_contiguous_partition(self) -> None:
        for contract in (
            "partition by line.produto_embalagem_id order by line.pmp_min_dias, line.pmp_max_dias, line.excel_row",
            "a primeira faixa de pmp da apresentacao deve iniciar em 0",
            "as faixas de pmp da apresentacao possuem lacuna",
            "faixa de pmp duplicada ou sobreposta",
            "o limite superior da faixa de pmp deve ser unico",
            "order by line.pmp_max_dias",
        ):
            self.assertIn(contract, self.migration)

    def test_analysis_is_fail_closed_and_publication_is_atomic_and_bound(self) -> None:
        for contract in (
            "p_workbook_sha256",
            "v_expected_hash",
            "status = 'erro'",
            "confirme os avisos antes de publicar",
            "conteudo analisado diverge da confirmacao",
            "create_com_lista_preco_rascunho_idempotente",
            "replace_com_lista_preco_rascunho_idempotente",
            "publish_com_lista_preco_versao_idempotente",
        ):
            self.assertIn(contract, self.migration)
        self.assertIn("pg_advisory_xact_lock", self.migration)
        self.assertIn("com_lista_preco_xlsx_publicacoes", self.migration)
        self.assertIn("canonical_payload_sha256", self.migration)

    def test_web_uses_server_actions_and_audited_rpc_boundary(self) -> None:
        self.assertIn('"use server"', self.actions)
        self.assertIn("auditedRpc", self.actions)
        self.assertNotIn("supabase.from(", self.actions)
        self.assertNotIn("supabase.rpc(", self.actions)
        self.assertIn("Listas de precos", self.page)
        self.assertIn("Publicar nova versao da lista de precos", self.component)
        self.assertIn("confirmo que os codigos governados estao corretos", self.component)

    def test_permissions_are_minimal_and_legacy_entrypoints_are_owner_private(self) -> None:
        for action in (
            "pedidos.price_lists.import.stage",
            "pedidos.price_lists.publish",
            "pedidos.price_lists.draft.manage",
        ):
            self.assertIn(action, self.migration)
        self.assertIn("enable row level security", self.migration)
        self.assertIn("revoke all on table", self.migration)
        self.assertIn("from public, anon, authenticated", self.migration)
        self.assertIn("revoke execute on function public.stage_com_lista_preco_xlsx_import_idempotente", self.migration)
        self.assertIn("revoke execute on function public.apply_com_lista_preco_import_idempotente", self.migration)
        self.assertGreaterEqual(self.migration.count("volatile\nsecurity definer"), 2)

    def test_smoke_and_ci_cover_material_behavior(self) -> None:
        for evidence in (
            "usuario sem alcada analisou planilha",
            "aviso por nome ou half_up nao foi preservado",
            "analise invalida nao bloqueou",
            "aviso nao confirmado foi publicado",
            "retry divergente foi aceito",
            "versao publicada foi alterada",
            "faixa inicial 31-60 nao foi bloqueada",
            "faixas 0-30 e 61-90 nao registraram lacuna",
            "pmp intermediario nao resolveu teto autorizado",
            "publicacao renomeou lista existente",
            "preco alterado com hash antigo foi aceito",
        ):
            self.assertIn(evidence, self.smoke)
        ci = CI.read_text(encoding="utf-8")
        self.assertEqual(ci.count("tests/sql/price_list_operational_xlsx.sql"), 1)

    def test_browser_contract_covers_workspace_and_five_resolutions(self) -> None:
        bootstrap = E2E_BOOTSTRAP.read_text(encoding="utf-8")
        browser = E2E_SPEC.read_text(encoding="utf-8")
        self.assertIn('"price-list-admin"', bootstrap)
        for behavior in (
            "modelo_lista_precos_elite.xlsx",
            "lista-data-invalida.xlsx",
            "Formula nao permitida",
            "Apresentacao nao pertence",
            "Faixa de PMP duplicada ou sobreposta",
            "Publicar nova versao da lista de precos",
            "usuario sem permissao nao ve menu nem acessa a rota",
            "assertNoHorizontalOverflow",
        ):
            self.assertIn(behavior, browser)
        config = (ROOT / "apps" / "web" / "playwright.config.mjs").read_text(encoding="utf-8")
        for width in (1920, 1366, 768, 390, 360):
            self.assertIn(f"width: {width}", config)


if __name__ == "__main__":
    unittest.main()
