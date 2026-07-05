from __future__ import annotations

import unittest
from pathlib import Path


REPO_ROOT = Path(__file__).resolve().parents[1]
RECIPE_DOC = REPO_ROOT / "docs" / "receita_rls_rpc_auditada.md"
COMPOSITION_DOC = REPO_ROOT / "docs" / "decisao_composicao_rpc_auditada.md"
XML_VALIDATION_DOC = REPO_ROOT / "docs" / "validacao_importacao_xml_mp_lot_contract.md"
MIGRATION_0021 = REPO_ROOT / "supabase" / "migrations" / "0021_estoque_lot_entry_rpc_contract.sql"
MIGRATION_0023 = REPO_ROOT / "supabase" / "migrations" / "0023_importacao_xml_mp_lot_contract.sql"


class AuditedRpcCompositionContractTests(unittest.TestCase):
    def test_recipe_documents_composed_rpc_contract(self) -> None:
        text = RECIPE_DOC.read_text(encoding="utf-8")

        self.assertIn("## Composicao de RPCs auditadas", text)
        self.assertIn("a operacao exige a uniao das alcadas envolvidas", text)
        self.assertIn("cada evento de negocio grava seu proprio log", text)
        self.assertIn("correlation_id", text)
        self.assertIn("'pcp_op:' || p_op_id || ':finish'", text)

    def test_decision_doc_defines_dual_permission_and_correlation_rules(self) -> None:
        text = COMPOSITION_DOC.read_text(encoding="utf-8")

        self.assertIn("importacao.nfe_xml.generate_mp_lot", text)
        self.assertIn("estoque.mp.lots.create", text)
        self.assertIn("usuario precise das duas alcadas", text)
        self.assertIn("metadata_json.lote_mp_id", text)
        self.assertIn("metadata_json.origem_ref", text)
        self.assertIn("correlation_id = 'pcp_op:' || p_op_id || ':finish'", text)

    def test_xml_mp_lot_generation_exposes_nested_stock_dependency(self) -> None:
        text = MIGRATION_0023.read_text(encoding="utf-8")

        self.assertIn("'stock_action_key', 'estoque.mp.lots.create'", text)
        self.assertIn("'estoque_action_key', 'estoque.mp.lots.create'", text)
        self.assertIn("'lote_mp_id', v_lote_id", text)
        self.assertIn("'origem_ref', v_origem_ref", text)
        self.assertIn("v_lote_id := public.create_est_lote_mp(", text)

    def test_nested_stock_lot_log_keeps_operational_reference_for_join(self) -> None:
        text = MIGRATION_0021.read_text(encoding="utf-8")

        self.assertIn("create or replace function public.create_est_lote_mp", text)
        self.assertIn("'origem_ref', nullif(trim(p_origem_ref), '')", text)
        self.assertIn("'estoque.mp_lote_created'", text)
        self.assertIn("'estoque.mp.lots.create'", text)

    def test_validation_doc_records_two_logs_and_future_correlation_requirement(self) -> None:
        text = XML_VALIDATION_DOC.read_text(encoding="utf-8")

        self.assertIn("duas camadas de autorizacao e auditoria", text)
        self.assertIn("Essa dupla autorizacao e intencional", text)
        self.assertIn("log externo: `metadata_json.lote_mp_id`", text)
        self.assertIn("log interno de estoque: `entity_id = lote_mp_id`", text)
        self.assertIn("`finalizar_pcp_op`", text)
        self.assertIn("`correlation_id` comum", text)


if __name__ == "__main__":
    unittest.main()
