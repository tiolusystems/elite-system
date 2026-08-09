from pathlib import Path
import unittest


ROOT = Path(__file__).resolve().parents[1]
DECISION = ROOT / "docs" / "decisao_pops_documentos_controlados.md"
MAP = ROOT / "docs" / "00_MAPA_EXECUTIVO.md"
STATE = ROOT / "docs" / "01_ESTADO_ATUAL.md"
OPS_GATE = ROOT / "docs" / "validacoes" / "OPS_GATE_01_MATRIZ.md"


class PopsArchitectureDecisionTests(unittest.TestCase):
    def setUp(self) -> None:
        self.decision = DECISION.read_text(encoding="utf-8")
        self.map = MAP.read_text(encoding="utf-8")
        self.state = STATE.read_text(encoding="utf-8")
        self.ops_gate = OPS_GATE.read_text(encoding="utf-8")

    def test_pop_stays_in_pcp_quality_without_new_module(self) -> None:
        self.assertIn("dominio `pcp`", self.decision)
        self.assertIn("Controle -> Qualidade -> POPs e documentos controlados", self.decision)
        self.assertIn("Nao sera criado um novo modulo", self.decision)
        self.assertIn("formula, OP, CQ, POP e transformacao", self.map)

    def test_published_versions_are_immutable_and_never_deleted(self) -> None:
        self.assertIn("Uma versao publicada e imutavel", self.decision)
        self.assertIn("Correcao gera nova versao", self.decision)
        self.assertIn("Nao ha exclusao", self.decision)
        self.assertIn("fisica.", self.decision)
        self.assertIn("justificativa e auditoria", self.decision)

    def test_processes_support_multiple_pop_links_and_op_freezes_references(self) -> None:
        self.assertIn("um ou mais POPs", self.decision)
        self.assertIn("muitos-para-muitos", self.decision)
        self.assertIn("congelar as versoes dos POPs", self.decision)
        for field in ("codigo do POP", "titulo", "revisao", "vigencia utilizada"):
            self.assertIn(field, self.decision)

    def test_print_and_quality_do_not_embed_the_pop_editor(self) -> None:
        self.assertIn("Procedimentos aplicaveis", self.decision)
        self.assertIn("O texto integral do POP permanece no cadastro controlado", self.decision)
        self.assertIn("O editor de POP nao pertence a tela de execucao do CQ", self.decision)
        self.assertIn("vinculadas por", self.decision)
        self.assertIn("`pessoa_id`", self.decision)

    def test_manual_and_pop_remain_distinct_and_ux01h_is_romaneio(self) -> None:
        self.assertIn("O manual contextual explica como operar o Elite System", self.decision)
        self.assertIn("O POP determina como", self.decision)
        self.assertIn("executar o processo industrial ou de qualidade", self.decision)
        self.assertIn("`/qualidade/pops`", self.ops_gate)
        self.assertIn("`/romaneios`", self.ops_gate)
        self.assertIn("versao publicada imutavel", self.ops_gate)


if __name__ == "__main__":
    unittest.main()
