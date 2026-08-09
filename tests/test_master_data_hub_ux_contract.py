from __future__ import annotations

from pathlib import Path
import unittest


ROOT = Path(__file__).resolve().parents[1]
PAGE = ROOT / "apps" / "web" / "app" / "cadastros" / "page.tsx"
CLIENTS = ROOT / "apps" / "web" / "app" / "cadastros" / "clientes-section.tsx"
PEOPLE = ROOT / "apps" / "web" / "app" / "cadastros" / "pessoas-section.tsx"
PERSON_CREATE = ROOT / "apps" / "web" / "app" / "cadastros" / "governed-person-create-form.tsx"
CSS = ROOT / "apps" / "web" / "app" / "globals.css"


class MasterDataHubUxContractTests(unittest.TestCase):
    def test_hub_exposes_the_eight_approved_groups(self) -> None:
        text = PAGE.read_text(encoding="utf-8") + CLIENTS.read_text(encoding="utf-8") + PEOPLE.read_text(encoding="utf-8")
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

    def test_hub_routes_governed_catalogs_to_their_canonical_workbenches(self) -> None:
        text = PAGE.read_text(encoding="utf-8") + CLIENTS.read_text(encoding="utf-8") + PEOPLE.read_text(encoding="utf-8")
        person_create = PERSON_CREATE.read_text(encoding="utf-8")
        self.assertIn("params.grupo", text)
        self.assertIn("params.busca", text)
        self.assertIn('action="/cadastros"', text)
        self.assertIn("activeGroup?.key", text)
        self.assertIn("createClienteAction", text)
        for canonical_route in (
            "/cadastros/materias-primas",
            "/cadastros/produtos",
            "/cadastros/embalagens",
            "/cadastros/tecnicos",
        ):
            self.assertIn(canonical_route, text)
        for legacy_action in (
            "createMateriaPrimaAction",
            "createProdutoBaseAction",
            "createEmbalagemAction",
            "createProdutoEmbalagemAction",
            "createConversaoUnidadeMpAction",
        ):
            self.assertNotIn(legacy_action, PAGE.read_text(encoding="utf-8"))
        self.assertIn("reviewAndCreatePessoaComercialAction", person_create)

        self.assertNotIn(".rpc(", text + person_create)
        self.assertNotIn("service_role", text + person_create)

    def test_hub_has_empty_search_and_responsive_contracts(self) -> None:
        page = PAGE.read_text(encoding="utf-8")
        css = CSS.read_text(encoding="utf-8")
        self.assertIn("Nenhum cadastro encontrado", page)
        self.assertIn("Revise a busca ou limpe o filtro para ver todos os grupos.", page)
        self.assertIn("cadastros-no-results", page)
        self.assertIn("@media (max-width: 820px)", css)
        self.assertIn("@media (max-width: 420px)", css)
        self.assertIn(".cadastros-group-grid", css)
        self.assertIn("grid-template-columns: 1fr", css)


if __name__ == "__main__":
    unittest.main()
