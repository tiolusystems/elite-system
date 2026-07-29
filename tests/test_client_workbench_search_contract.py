from pathlib import Path
import unittest


ROOT = Path(__file__).resolve().parents[1]
MIGRATION = ROOT / "supabase" / "migrations" / "0117_govern_client_workbench_search.sql"
SMOKE = ROOT / "tests" / "sql" / "client_workbench_search.sql"
MASTER_DATA = ROOT / "apps" / "web" / "lib" / "master-data.ts"
PAGE = ROOT / "apps" / "web" / "app" / "cadastros" / "page.tsx"
CLIENTS = ROOT / "apps" / "web" / "app" / "cadastros" / "clientes-section.tsx"
CSS = ROOT / "apps" / "web" / "app" / "globals.css"
CI = ROOT / ".github" / "workflows" / "ci.yml"


class ClientWorkbenchSearchContractTests(unittest.TestCase):
    def test_search_is_server_paginated_and_rls_preserving(self) -> None:
        sql = MIGRATION.read_text(encoding="utf-8")
        self.assertIn("consultar_cad_clientes_paginada", sql)
        self.assertIn("security invoker", sql.lower())
        self.assertIn("count(*) over ()", sql)
        self.assertIn("public.current_actor_id() is not null", sql)
        self.assertIn("limit greatest(1, least(coalesce(p_limite, 25), 50))", sql)
        self.assertIn("revoke all on function", sql)
        self.assertIn("from public, anon", sql)
        self.assertIn("to authenticated", sql)
        self.assertNotIn("security definer", sql.lower())
        self.assertNotIn("insert into", sql.lower())
        self.assertNotIn("update public.", sql.lower())
        self.assertNotIn("delete from", sql.lower())

    def test_search_covers_governed_customer_identity_and_relations(self) -> None:
        sql = MIGRATION.read_text(encoding="utf-8")
        for expected in (
            "client.nome",
            "client.codigo_legado",
            "identification.razao_social",
            "identification.nome_fantasia",
            "client.apelidos_json",
            "cad_cliente_documentos",
            "cad_cliente_propriedades",
            "cad_cliente_estabelecimentos",
            "cad_cliente_contatos",
            "contact.telefone",
            "contact.email",
            "cad_cliente_enderecos",
            "address.cep",
        ):
            self.assertIn(expected, sql)
        self.assertIn("normalize_client_search_text", sql)

    def test_route_loads_only_the_selected_client_relations(self) -> None:
        library = MASTER_DATA.read_text(encoding="utf-8")
        page = PAGE.read_text(encoding="utf-8")
        self.assertIn('supabase.rpc("consultar_cad_clientes_paginada"', library)
        self.assertIn('.eq("cliente_id", clienteId)', library)
        self.assertIn('.eq("id", clienteId)', library)
        self.assertNotIn("getClientMasterData", library)
        self.assertIn("carregarLista: !selectedClientId && !newClientMode", page)
        self.assertIn(
            'getMasterDataDashboard({ lightweight: activeGroup?.key === "clientes" })',
            page,
        )
        self.assertIn("if (options.lightweight)", library)
        self.assertIn("clienteSelecionado={clientWorkspace?.cliente ?? null}", page)
        self.assertIn("clientNewHref", page)
        self.assertIn('query.set("busca", input.busca.trim())', page)
        self.assertIn('query.set("pagina", String(input.pagina))', page)

    def test_list_file_and_new_modes_are_visually_separate(self) -> None:
        clients = CLIENTS.read_text(encoding="utf-8")
        css = CSS.read_text(encoding="utf-8")
        self.assertIn("clients-workbench-list", clients)
        self.assertIn("clients-workbench-detail", clients)
        self.assertIn("clients-workbench-form", clients)
        self.assertIn("Voltar aos clientes", clients)
        self.assertIn("Buscar clientes", clients)
        self.assertIn("client-pagination", clients)
        self.assertNotIn("clientesFiltrados", clients)
        self.assertNotIn("position: sticky", css[css.index("/* UX-01C.2"):])
        self.assertIn("grid-template-columns: minmax(0, 1fr)", css)

    def test_search_smoke_and_ci_cover_pagination_and_permissions(self) -> None:
        smoke = SMOKE.read_text(encoding="utf-8")
        workflow = CI.read_text(encoding="utf-8")
        self.assertIn("first page or total is invalid", smoke)
        self.assertIn("second page is invalid", smoke)
        self.assertIn("records beyond the old 250 limit are missing", smoke)
        self.assertIn("last partial page is invalid", smoke)
        self.assertIn("without an active profile enumerated clients", smoke)
        self.assertIn("client search is exposed to anon or PUBLIC", smoke)
        self.assertIn("client search migration expanded direct write access", smoke)
        self.assertIn("tests/sql/client_workbench_search.sql", workflow)


if __name__ == "__main__":
    unittest.main()
