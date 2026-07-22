from pathlib import Path
import unittest

ROOT = Path(__file__).resolve().parents[1]


class OperationalManualDocsContractTests(unittest.TestCase):
    def test_priority_operational_manuals_are_present_and_indexed(self):
        index = (ROOT / "docs/manuais/README.md").read_text(encoding="utf-8")
        manuals = (
            "cadastros/CLIENTES_PROPRIEDADES.md",
            "cadastros/PESSOAS_VINCULOS.md",
            "cadastros/PRODUTOS_APRESENTACOES_EMBALAGENS.md",
            "producao/FORMULAS_GARANTIAS.md",
            "producao/ORDEM_ENVASE.md",
            "pedidos/PEDIDOS_E_APROVACAO.md",
            "financeiro/RECEBIMENTOS_COMISSOES.md",
            "ROMANEIO.md",
        )
        for relative_path in manuals:
            self.assertIn(f"`{relative_path}`", index)
            self.assertTrue((ROOT / "docs/manuais" / relative_path).is_file())

    def test_people_manual_separates_business_role_from_system_access(self):
        text = (ROOT / "docs/manuais/cadastros/PESSOAS_VINCULOS.md").read_text(encoding="utf-8")
        self.assertIn("alterar papel comercial nao concede acesso ao sistema", text)
        self.assertIn("reativar a pessoa nao reabre automaticamente areas encerradas", text)

    def test_finance_manual_documents_event_ledgers(self):
        text = (ROOT / "docs/manuais/financeiro/RECEBIMENTOS_COMISSOES.md").read_text(encoding="utf-8")
        self.assertIn("Cada recebimento libera a fracao", text)
        self.assertIn("O movimento original nunca e", text)


if __name__ == "__main__":
    unittest.main()
