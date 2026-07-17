from __future__ import annotations

from pathlib import Path
import unittest


ROOT = Path(__file__).resolve().parents[1]
PAGE = ROOT / "apps" / "web" / "app" / "cadastros" / "page.tsx"
CSS = ROOT / "apps" / "web" / "app" / "globals.css"


class MasterDataHubUxContractTests(unittest.TestCase):
    def test_hub_exposes_the_eight_approved_groups(self) -> None:
        text = PAGE.read_text(encoding="utf-8")
        for title in (
            "Clientes e propriedades",
            "Pessoas e vinculos comerciais",
            "Materias-primas e insumos",
            "Produtos e apresentacoes",
            "Embalagens e conversoes",
            "Veiculos e logistica",
            "Cadastros tecnicos",
            "Validacao e pendencias",
        ):
            self.assertIn(title, text)

    def test_hub_uses_governed_url_state_and_keeps_existing_actions(self) -> None:
        text = PAGE.read_text(encoding="utf-8")
        self.assertIn("params.grupo", text)
        self.assertIn("params.busca", text)
        self.assertIn('action="/cadastros"', text)
        self.assertIn("activeGroup?.key", text)
        for action in (
            "createClienteAction",
            "createPessoaComercialAction",
            "createMateriaPrimaAction",
            "createProdutoBaseAction",
            "createEmbalagemAction",
            "createProdutoEmbalagemAction",
            "createConversaoUnidadeMpAction",
        ):
            self.assertIn(f"action={{{action}}}", text)

        self.assertNotIn(".rpc(", text)
        self.assertNotIn("service_role", text)

    def test_hub_has_empty_search_and_responsive_contracts(self) -> None:
        page = PAGE.read_text(encoding="utf-8")
        css = CSS.read_text(encoding="utf-8")
        self.assertIn("Nenhuma area encontrada", page)
        self.assertIn("cadastros-no-results", page)
        self.assertIn("@media (max-width: 820px)", css)
        self.assertIn("@media (max-width: 420px)", css)
        self.assertIn(".cadastros-group-grid", css)
        self.assertIn("grid-template-columns: 1fr", css)


if __name__ == "__main__":
    unittest.main()
