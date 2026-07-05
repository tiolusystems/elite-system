from __future__ import annotations

import re
import unittest
from pathlib import Path


REPO_ROOT = Path(__file__).resolve().parents[1]
DECISION_DOC = REPO_ROOT / "docs" / "decisao_faturamento_notas_fiscais.md"
ROMANEIO_DOC = REPO_ROOT / "docs" / "escopo_romaneio.md"
COMMISSIONS_DOC = REPO_ROOT / "docs" / "escopo_comissoes_recebimentos_credito.md"
FLOW_DOC = REPO_ROOT / "docs" / "fluxo_operacional_elite_system.md"
RECIPE_DOC = REPO_ROOT / "docs" / "receita_rls_rpc_auditada.md"
SECURITY_MATRIX_DOC = REPO_ROOT / "docs" / "matriz_seguranca_alcadas.md"
MIGRATIONS = REPO_ROOT / "supabase" / "migrations"


class FaturamentoNfDecisionContractTests(unittest.TestCase):
    def test_decision_models_nf_as_one_to_many_not_order_field(self) -> None:
        text = DECISION_DOC.read_text(encoding="utf-8")

        self.assertIn("nota fiscal nao e um campo solto do pedido", text)
        self.assertIn("NF deve aparecer no corpo do pedido como rastreabilidade fiscal", text)
        self.assertIn("relacao um-para-muitos", text)
        self.assertIn("pedido pode ter zero, uma ou varias notas fiscais", text)
        self.assertIn("fat_notas_fiscais", text)
        self.assertIn("fat_nota_fiscal_eventos", text)
        self.assertIn("nao deve existir campo como `numero_nf`, `chave_nfe`, `valor_nf` ou `status_nf` dentro de `com_pedidos`", text)

    def test_simples_faturamento_keeps_romaneio_nullable_and_does_not_move_stock(self) -> None:
        text = DECISION_DOC.read_text(encoding="utf-8")

        self.assertIn("`simples_faturamento` convive com NF por romaneio", text)
        self.assertIn("`romaneio_id` deve ser nullable", text)
        self.assertIn("simples faturamento nao baixa estoque", text)
        self.assertIn("NF emitida nao baixa estoque por si so", text)
        self.assertIn("romaneio confirmado baixa PA", text)

    def test_simple_invoice_is_parent_of_remittance_invoices(self) -> None:
        text = DECISION_DOC.read_text(encoding="utf-8")
        romaneio = ROMANEIO_DOC.read_text(encoding="utf-8")
        flow = FLOW_DOC.read_text(encoding="utf-8")
        combined = f"{text}\n{romaneio}\n{flow}"

        self.assertIn("NF de simples faturamento vira o documento fiscal pai do pedido", combined)
        self.assertIn("cada romaneio de carga posterior deve sair com uma NF de remessa filha", combined)
        self.assertIn("`tipo = remessa` exige `pedido_id`, `romaneio_id`", combined)
        self.assertIn("`nota_pai_id` apontando para essa NF pai", combined)
        self.assertIn("NF de remessa deve pertencer ao mesmo `pedido_id` da NF pai", combined)
        self.assertIn("`tipo = complementar` deve apontar `nota_complementada_id`", combined)
        self.assertIn("`nota_pai_id` e `nota_complementada_id` nao devem ser preenchidos ao mesmo tempo", combined)
        self.assertIn("romaneio de carga deve exibir a NF de remessa e a NF simples pai", combined)
        self.assertIn("fat_pedido_dossie_fiscal", combined)
        self.assertNotIn("nota_referenciada_id", combined)

    def test_fiscal_lifecycle_is_event_based(self) -> None:
        text = DECISION_DOC.read_text(encoding="utf-8")

        self.assertIn("cancelamento cria evento `cancelada`", text)
        self.assertIn("carta de correcao cria evento `carta_correcao`", text)
        self.assertIn("NF complementar cria uma nova linha em `fat_notas_fiscais`", text)
        self.assertIn("correcao de erro deve ser novo evento fiscal", text)
        self.assertIn("hard-delete de NF/evento fiscal nao faz parte do fluxo operacional", text)
        self.assertIn("fonte auditavel do ciclo de vida deve ser `fat_nota_fiscal_eventos`", text)

    def test_event_payload_json_has_documented_contract(self) -> None:
        text = DECISION_DOC.read_text(encoding="utf-8")
        recipe = RECIPE_DOC.read_text(encoding="utf-8")
        combined = f"{text}\n{recipe}"

        self.assertIn("`payload_json` nao e texto livre", text)
        self.assertIn("Contrato inicial:", text)
        self.assertIn("`protocolo_autorizacao`", text)
        self.assertIn("`protocolo_cancelamento`", text)
        self.assertIn("`sequencia_cce`", text)
        self.assertIn("`nota_substituta_id`", text)
        self.assertIn("`nota_complementar_id`", text)
        self.assertIn("migration deve adicionar comentario de coluna", text)
        self.assertIn("RPC de evento deve validar no minimo os campos obrigatorios", text)
        self.assertIn("nao JSON livre", combined)

    def test_commission_trigger_remains_receipt_not_nf_emission(self) -> None:
        text = DECISION_DOC.read_text(encoding="utf-8")
        commissions = COMMISSIONS_DOC.read_text(encoding="utf-8")
        combined = f"{text}\n{commissions}"

        self.assertIn("Comissao continua sendo liberada por `recebimento`", combined)
        self.assertIn("NF emitida nao libera comissao sozinha", combined)
        self.assertIn("recebimento parcial ou integral libera comissao proporcional", combined)
        self.assertIn("fin_recebimento_alocacoes", combined)

    def test_operational_docs_reference_fiscal_decision(self) -> None:
        romaneio = ROMANEIO_DOC.read_text(encoding="utf-8")
        flow = FLOW_DOC.read_text(encoding="utf-8")
        commissions = COMMISSIONS_DOC.read_text(encoding="utf-8")

        for text in (romaneio, flow, commissions):
            self.assertIn("docs/decisao_faturamento_notas_fiscais.md", text)

        self.assertIn("NF por simples faturamento deve apontar para `pedido_id` e deixar `romaneio_id` nullable", romaneio)
        self.assertIn("quando o pedido tiver NF de simples faturamento, a NF de remessa deve apontar `nota_pai_id`", romaneio)
        self.assertIn("12. Faturamento e NF.", flow)
        self.assertIn("Faturamento/NF como evento fiscal auditavel", flow)

    def test_recipe_and_matrix_define_fiscal_event_axis_and_action_keys(self) -> None:
        recipe = RECIPE_DOC.read_text(encoding="utf-8")
        matrix = SECURITY_MATRIX_DOC.read_text(encoding="utf-8")
        combined = f"{recipe}\n{matrix}"

        self.assertIn("axis = fiscal_event", recipe)
        self.assertIn("documento fiscal com ciclo de vida por eventos", recipe)

        for action_key in (
            "faturamento.nf.view",
            "faturamento.nf.issue",
            "faturamento.nf.cancel",
            "faturamento.nf.correct",
            "faturamento.nf.complement",
            "faturamento.nf.substitute",
        ):
            self.assertIn(action_key, combined)

    def test_existing_order_schema_does_not_add_nf_columns_to_com_pedidos(self) -> None:
        combined_sql = "\n".join(path.read_text(encoding="utf-8") for path in sorted(MIGRATIONS.glob("*.sql")))
        pattern = re.compile(
            r"(alter\s+table\s+(?:public\.)?com_pedidos\s+add\s+column[^;]*(?:nf|nfe|nota)|"
            r"create\s+table\s+if\s+not\s+exists\s+public\.com_pedidos\s*\([^;]*(?:numero_nf|chave_nfe|valor_nf|status_nf))",
            flags=re.IGNORECASE | re.DOTALL,
        )

        self.assertIsNone(pattern.search(combined_sql))


if __name__ == "__main__":
    unittest.main()
