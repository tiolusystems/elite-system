from pathlib import Path
import unittest


ROOT = Path(__file__).resolve().parents[1]
MIGRATION = ROOT / "supabase" / "migrations" / "0124_govern_canonical_price_lists.sql"


class PriceListCanonicalFoundationContractTests(unittest.TestCase):
    @classmethod
    def setUpClass(cls) -> None:
        cls.sql = MIGRATION.read_text(encoding="utf-8").lower()

    def test_canonical_identity_coverage_and_prices_are_normalized(self) -> None:
        for table in (
            "com_listas_preco",
            "com_lista_preco_versoes",
            "com_lista_preco_versao_itens",
            "com_lista_preco_versao_precos",
            "com_lista_preco_regras",
        ):
            self.assertIn(f"create table public.{table}", self.sql)
        self.assertIn("references public.cad_produto_embalagens(id)", self.sql)
        self.assertIn("valor_centavos_por_litro bigint not null", self.sql)
        self.assertIn("check (valor_centavos_por_litro > 0)", self.sql)
        self.assertIn("check (prazo_dias >= 0)", self.sql)
        self.assertNotIn("check (prazo_dias > 0)", self.sql)
        self.assertIn("unique (versao_item_id, prazo_dias)", self.sql)

    def test_scopes_use_real_relations_without_polymorphic_identity(self) -> None:
        for scope in (
            "regra_origens",
            "regra_pessoas",
            "regra_areas",
            "regra_ufs",
            "regra_clientes",
            "regra_produtos",
            "regra_apresentacoes",
        ):
            self.assertIn(f"create table public.com_lista_preco_{scope}", self.sql)
        self.assertIn("references public.cad_pessoa_papeis(id)", self.sql)
        self.assertIn("references public.cad_areas_comerciais(id)", self.sql)
        self.assertIn("references public.cad_clientes(id)", self.sql)
        self.assertIn("references public.cad_produtos_base(id)", self.sql)
        self.assertNotIn("scope_type", self.sql)
        self.assertNotIn("entity_id", self.sql)
        self.assertIn("dimensoes associadas usam and; valores na mesma dimensao usam or", self.sql)

    def test_publication_has_one_canonical_source_and_append_only_lifecycle(self) -> None:
        self.assertIn("create table public.com_lista_preco_publicacoes", self.sql)
        self.assertIn("create table public.com_lista_preco_lifecycle_eventos", self.sql)
        self.assertNotIn("'published'", self.sql)
        self.assertIn("tipo in ('superseded', 'withdrawn')", self.sql)
        self.assertIn("fonte canonica unica do fato de publicacao", self.sql)
        self.assertIn("prevent_com_lista_preco_fact_changes", self.sql)
        self.assertIn("protect_com_lista_preco_published_content", self.sql)
        self.assertIn("versao publicada e imutavel", self.sql)

    def test_published_content_checks_old_and_new_parent_on_update(self) -> None:
        self.assertIn("v_old_versao_id bigint", self.sql)
        self.assertIn("v_new_versao_id bigint", self.sql)
        self.assertIn("if tg_op in ('update', 'delete')", self.sql)
        self.assertIn("if tg_op in ('insert', 'update')", self.sql)
        self.assertIn("publication.versao_id in (v_old_versao_id, v_new_versao_id)", self.sql)

    def test_version_lineage_is_scoped_to_list_and_successor_is_not_retroactive(self) -> None:
        self.assertIn("unique (lista_id, id)", self.sql)
        self.assertIn("foreign key (lista_id, versao_anterior_id)", self.sql)
        self.assertIn("references public.com_lista_preco_versoes(lista_id, id)", self.sql)
        self.assertIn(
            "if v_version.vigencia_inicio < (clock_timestamp() at time zone 'america/sao_paulo')::date",
            self.sql,
        )
        self.assertIn("publicacao sucessora nao permite vigencia retroativa", self.sql)

    def test_governed_rpcs_are_idempotent_and_serialized(self) -> None:
        for function in (
            "create_com_lista_preco_rascunho_idempotente",
            "create_com_lista_preco_versao_idempotente",
            "replace_com_lista_preco_rascunho_idempotente",
            "publish_com_lista_preco_versao_idempotente",
            "withdraw_com_lista_preco_publicacao_idempotente",
        ):
            self.assertIn(f"function public.{function}", self.sql)
        self.assertGreaterEqual(self.sql.count("pg_advisory_xact_lock"), 7)
        self.assertIn("chave de idempotencia reutilizada com conteudo diferente", self.sql)
        self.assertIn("com_lista_preco_requisicoes", self.sql)
        self.assertIn("before update or delete on public.com_lista_preco_requisicoes", self.sql)

    def test_permissions_are_default_deny_and_direct_writes_are_closed(self) -> None:
        for action in (
            "pedidos.price_lists.view",
            "pedidos.price_lists.draft.manage",
            "pedidos.price_lists.publish",
            "pedidos.price_lists.withdraw",
        ):
            self.assertIn(action, self.sql)
        self.assertGreaterEqual(self.sql.count("false, 12"), 4)
        self.assertIn("enable row level security", self.sql)
        self.assertIn("revoke all on table public.%i from public, anon, authenticated", self.sql)

    def test_tranche_does_not_change_orders_comm_or_import_xlsx(self) -> None:
        forbidden = (
            "alter table public.com_pedidos",
            "alter table public.com_pedido_itens",
            "create table public.com_campanh",
            "create table public.com_comissao",
            "source_workbooks",
            "source_rows",
            "xlsx",
        )
        for token in forbidden:
            self.assertNotIn(token, self.sql)


if __name__ == "__main__":
    unittest.main()
