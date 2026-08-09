from __future__ import annotations

from pathlib import Path
import unittest


ROOT = Path(__file__).resolve().parents[1]
MIGRATION = ROOT / "supabase" / "migrations" / "0103_govern_product_groups.sql"
PAGE = ROOT / "apps" / "web" / "app" / "cadastros" / "grupos-produto" / "page.tsx"
PRODUCTS = ROOT / "apps" / "web" / "app" / "cadastros" / "produtos" / "page.tsx"
ACTIONS = ROOT / "apps" / "web" / "app" / "cadastros" / "actions.ts"
MANUALS = ROOT / "apps" / "web" / "lib" / "manuals.ts"


class ProductGroupsGovernanceContractTests(unittest.TestCase):
    def test_migration_governs_existing_relational_catalog(self) -> None:
        text = MIGRATION.read_text(encoding="utf-8")
        self.assertNotIn("create table public.cad_grupos_produto", text.lower())
        for contract in (
            "idx_cad_grupos_produto_nome_norm",
            "create_cad_grupo_produto",
            "update_cad_grupo_produto",
            "set_cad_grupo_produto_active_state",
            "list_cad_grupo_produto_history",
            "create_cad_produto_base_governado",
            "begin_audited_rpc",
            "log_audited_rpc_change",
            "revoke insert, update, delete, truncate",
        ):
            self.assertIn(contract, text)
        self.assertIn("from authenticated", text)
        self.assertIn("from public, anon", text)

    def test_product_creation_uses_group_id_and_governed_rpc(self) -> None:
        page = PRODUCTS.read_text(encoding="utf-8")
        actions = ACTIONS.read_text(encoding="utf-8")
        self.assertIn('name="grupo_id"', page)
        self.assertNotIn('name="grupo"', page)
        self.assertIn('value={item.id}', page)
        self.assertIn('"create_cad_produto_base_governado"', actions)
        self.assertIn("p_grupo_id", actions)
        self.assertNotIn('p_grupo: optionalField(formData, "grupo")', actions)

    def test_canonical_workbench_has_operations_history_context_and_manual(self) -> None:
        page = PAGE.read_text(encoding="utf-8")
        for action in (
            "createProdutoGroupAction",
            "updateProdutoGroupAction",
            "setProdutoGroupActiveStateAction",
        ):
            self.assertIn(f"action={{{action}}}", page)
        self.assertIn("Produtos vinculados", page)
        self.assertIn("Histórico de alterações", page)
        self.assertIn("getTechnicalProductGroupHistory", page)
        self.assertIn("/cadastros/grupos-produto", MANUALS.read_text(encoding="utf-8"))
        self.assertNotIn(".rpc(", page)


if __name__ == "__main__":
    unittest.main()
