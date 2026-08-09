from __future__ import annotations

from pathlib import Path
import unittest


ROOT = Path(__file__).resolve().parents[1]
PAGE = ROOT / "apps" / "web" / "app" / "cadastros" / "page.tsx"
PEOPLE = ROOT / "apps" / "web" / "app" / "cadastros" / "pessoas-section.tsx"
PERSON_CREATE = ROOT / "apps" / "web" / "app" / "cadastros" / "governed-person-create-form.tsx"
ACTIONS = ROOT / "apps" / "web" / "app" / "cadastros" / "actions.ts"
DATA = ROOT / "apps" / "web" / "lib" / "master-data.ts"
GOVERNANCE = ROOT / "apps" / "web" / "lib" / "master-data-governance.ts"
CSS = ROOT / "apps" / "web" / "app" / "globals.css"


class PeopleCommercialUxContractTests(unittest.TestCase):
    def test_people_workbench_reuses_audited_actions(self) -> None:
        text = PEOPLE.read_text(encoding="utf-8")
        create = PERSON_CREATE.read_text(encoding="utf-8")
        for action in (
            "updatePessoaComercialIdentityAction",
            "updatePessoaComercialRoleAction",
            "deactivatePessoaComercialAction",
            "reactivatePessoaComercialAction",
            "linkPessoaAreaComercialAction",
            "closePessoaAreaComercialAction",
        ):
            self.assertIn(f"action={{{action}}}", text)
        self.assertIn("reviewAndCreatePessoaComercialAction", create)
        self.assertIn("useActionState", create)
        self.assertNotIn(".rpc(", text)
        self.assertNotIn(".rpc(", create)
        self.assertNotIn("service_role", text)

    def test_people_labels_are_centralized_and_raw_enums_are_not_rendered(self) -> None:
        people = PEOPLE.read_text(encoding="utf-8")
        governance = GOVERNANCE.read_text(encoding="utf-8")
        for contract in (
            "TIPO_COMERCIAL_OPTIONS",
            "PAPEL_COMERCIAL_OPTIONS",
            "MOTIVO_PAPEL_OPTIONS",
            "papelAreaLabel",
        ):
            self.assertIn(contract, governance)
            self.assertIn(contract, people)
        for raw_option in (
            ">funcionario_elite<",
            ">agente_vinculado<",
            ">tecnico_campo<",
            ">pending_review<",
        ):
            self.assertNotIn(raw_option, people)

    def test_people_data_uses_relational_sources_and_governed_area_actions(self) -> None:
        data = DATA.read_text(encoding="utf-8")
        people = PEOPLE.read_text(encoding="utf-8")
        for relation in (
            "cad_pessoas_comerciais",
            "cad_pessoas_comerciais_papeis_ativos",
            "cad_areas_comerciais",
            "cad_pessoa_areas_comerciais",
        ):
            self.assertIn(relation, data)
        self.assertIn('action={linkPessoaAreaComercialAction}', people)
        self.assertIn('action={closePessoaAreaComercialAction}', people)

    def test_navigation_preserves_people_context(self) -> None:
        page = PAGE.read_text(encoding="utf-8")
        actions = ACTIONS.read_text(encoding="utf-8")
        self.assertIn('params.pessoa', page)
        self.assertIn('grupo=pessoas&modo=novo#cadastro-pessoa', page)
        self.assertIn('grupo=pessoas&pessoa=${pessoaId}', actions)

    def test_workbench_has_responsive_contract(self) -> None:
        css = CSS.read_text(encoding="utf-8")
        self.assertTrue(css.startswith(":root"), "globals.css must not prefix :root with a BOM")
        self.assertIn(".clients-workbench", css)
        self.assertIn("@media (max-width: 820px)", css)
        self.assertIn(".person-role-fieldset", css)
        self.assertIn(".role-chip-list", css)
        self.assertIn(".person-duplicate-review", css)
        self.assertIn(".area-link-form", css)


if __name__ == "__main__":
    unittest.main()
