from pathlib import Path
import unittest


ROOT = Path(__file__).resolve().parents[1]
MIGRATION = ROOT / "supabase" / "migrations" / "0120_commission_policy_domain.sql"
DECISION = ROOT / "docs" / "decisao_dominio_comissoes_20260810.md"


class CommissionPolicyDomainContract(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        cls.sql = MIGRATION.read_text(encoding="utf-8")
        cls.doc = DECISION.read_text(encoding="utf-8")

    def test_sales_only_is_an_explicit_invariant(self):
        self.assertIn("only sale orders generate commission", self.sql)
        self.assertIn("orders.tipo_pedido = 'venda'", self.sql)
        self.assertIn("Somente pedidos de venda", self.doc)

    def test_receipt_does_not_remove_commission_eligibility(self):
        search_section = self.sql.split(
            "create or replace function public.buscar_fin_pedidos_comissionamento", 1
        )[1]
        self.assertNotIn(
            "not exists (\\n        select 1\\n        from public.fin_recebimento_alocacoes",
            search_section,
        )
        self.assertIn("Recebimento parcial ou total nao remove elegibilidade", self.sql)

    def test_relationships_are_optional_temporal_domain_objects(self):
        self.assertIn("cad_pessoa_relacionamentos_comerciais", self.sql)
        self.assertIn("'agente_vendedor'", self.sql)
        self.assertIn("'vendedor_gerente'", self.sql)
        self.assertIn("vigencia_inicio", self.sql)
        self.assertIn("vigencia_fim", self.sql)
        self.assertIn("opcionais", self.doc.lower())

    def test_commission_rates_are_normalized_not_magic_json(self):
        self.assertIn("com_comissao_politicas_pessoa", self.sql)
        self.assertIn("com_comissao_politica_taxas_grupo", self.sql)
        self.assertIn("grupo_produto_id", self.sql)
        self.assertIn("percentual numeric not null", self.sql)
        self.assertIn("Percentuais de negocio nao ficam em JSON", self.sql)

    def test_policy_publish_is_explicit_second_step(self):
        self.assertIn("criar_com_comissao_politica_rascunho", self.sql)
        self.assertIn("publicar_com_comissao_politica", self.sql)
        self.assertIn("explicit policy confirmation is required", self.sql)

    def test_manual_commission_change_requires_prepare_and_confirm(self):
        self.assertIn("propor_com_pedido_comissao", self.sql)
        self.assertIn("confirmar_com_pedido_comissao", self.sql)
        self.assertIn("double_confirmation_step", self.sql)
        self.assertIn("contexto_hash", self.sql)
        self.assertIn("commission context changed after review", self.sql)

    def test_old_one_step_entrypoint_is_not_public_anymore(self):
        self.assertIn(
            "revoke execute on function public.definir_com_pedido_comissao_idempotente",
            self.sql,
        )

    def test_post_receipt_participant_can_receive_existing_proportional_release(self):
        self.assertIn("liberar_fin_comissionado_recebimentos_existentes", self.sql)
        self.assertIn("novo_participante_pos_recebimento", self.sql)
        self.assertIn("release.alocacao_id = allocation.id", self.sql)
        self.assertIn("release.comissionado_id = v_assignment.id", self.sql)

    def test_order_can_be_resolved_by_id_with_reason(self):
        self.assertIn("consultar_fin_pedido_comissionamento", self.sql)
        self.assertIn("motivo_inelegibilidade", self.sql)
        self.assertIn("nao depende da pagina atual da listagem", self.sql)

    def test_history_snapshot_is_first_class(self):
        self.assertIn("com_comissao_estrutura_snapshots", self.sql)
        self.assertIn("com_comissao_estrutura_snapshot_participantes", self.sql)
        self.assertIn("nao reescrevem fatos historicos", self.sql)


    def test_closed_relationship_history_still_blocks_overlap(self):
        self.assertIn("relation.status <> 'cancelled'", self.sql)

    def test_closed_policy_history_still_blocks_overlap(self):
        self.assertIn("other_policy.status in ('published', 'closed')", self.sql)

    def test_non_commissionable_policy_cannot_keep_rates(self):
        self.assertIn("non-commissionable policy cannot publish group rates", self.sql)

    def test_historical_release_is_called_only_when_receipts_exist(self):
        confirm = self.sql.split(
            "create or replace function public.confirmar_com_pedido_comissao", 1
        )[1]
        call = "v_releases := public.liberar_fin_comissionado_recebimentos_existentes(v_assignment_id);"
        self.assertIn("if exists (", confirm)
        self.assertIn(call, confirm)
        self.assertLess(confirm.find("if exists ("), confirm.find(call))


if __name__ == "__main__":
    unittest.main()
