from __future__ import annotations

import re
import unittest
from pathlib import Path


REPO_ROOT = Path(__file__).resolve().parents[1]
MIGRATION_0032 = REPO_ROOT / "supabase" / "migrations" / "0032_metas_event_ledger_contract.sql"
COMMISSIONS_DOC = REPO_ROOT / "docs" / "escopo_comissoes_recebimentos_credito.md"
RECIPE_DOC = REPO_ROOT / "docs" / "receita_rls_rpc_auditada.md"
SECURITY_MATRIX_DOC = REPO_ROOT / "docs" / "matriz_seguranca_alcadas.md"
VALIDATION_DOC = REPO_ROOT / "docs" / "validacao_metas_ledger_contract.md"


class MetasLedgerContractTests(unittest.TestCase):
    def test_0032_adds_target_event_axis_and_action_keys(self) -> None:
        text = MIGRATION_0032.read_text(encoding="utf-8")
        docs = "\n".join(
            (
                COMMISSIONS_DOC.read_text(encoding="utf-8"),
                RECIPE_DOC.read_text(encoding="utf-8"),
                SECURITY_MATRIX_DOC.read_text(encoding="utf-8"),
            )
        )

        self.assertIn("alter type public.audit_axis add value if not exists 'target_event'", text)
        self.assertIn("'target_event'", text)
        self.assertIn("axis = target_event", docs)

        for action_key in (
            "metas.view",
            "metas.periods.manage",
            "metas.sales.register",
            "metas.cancellations.register",
            "metas.returns.register",
            "metas.adjust",
        ):
            self.assertIn(action_key, text)
            self.assertIn(action_key, docs)

    def test_creates_period_lock_and_append_only_movement_ledger(self) -> None:
        text = MIGRATION_0032.read_text(encoding="utf-8")
        lower_text = text.lower()

        self.assertIn("create table if not exists public.com_meta_periodos", text)
        self.assertIn("create table if not exists public.com_meta_pessoa_periodo_locks", text)
        self.assertIn("primary key (periodo_id, pessoa_id)", text)
        self.assertIn("create table if not exists public.com_meta_movimentos", text)
        self.assertIn("tipo_movimento in ('venda_aberta', 'cancelamento', 'devolucao', 'ajuste_manual')", text)
        self.assertIn("before update or delete on public.com_meta_movimentos", lower_text)
        self.assertIn("target event ledgers are append-only", text)
        self.assertIn("revoke insert, update, delete on public.com_meta_periodos", lower_text)
        self.assertIn("revoke insert, update, delete on public.com_meta_periodos, public.com_meta_pessoa_periodo_locks, public.com_meta_movimentos", lower_text)

    def test_meta_balance_is_derived_not_editable_state(self) -> None:
        text = MIGRATION_0032.read_text(encoding="utf-8").lower()

        table_match = re.search(
            r"create table if not exists public\.com_meta_movimentos\s*\((.*?)\n\);",
            text,
            flags=re.DOTALL,
        )
        self.assertIsNotNone(table_match)
        table_body = table_match.group(1)

        self.assertNotIn("saldo", table_body)
        self.assertIn("create or replace view public.com_meta_saldos_pessoa_periodo", text)
        self.assertIn("coalesce(sum(movimento.valor_meta), 0)::numeric as valor_meta_liquido", text)

    def test_period_and_manual_adjustment_rpcs_are_audited_and_validate_reason(self) -> None:
        period_body = self._function_body("upsert_com_meta_periodo")
        adjustment_body = self._function_body("registrar_com_meta_ajuste_manual")

        self.assertIn("public.begin_audited_rpc(", period_body)
        self.assertIn("perform public.log_audited_rpc_change(", period_body)
        self.assertIn("metas.periods.manage", period_body)
        self.assertIn("'target_event'", period_body)

        self.assertIn("public.begin_audited_rpc(", adjustment_body)
        self.assertIn("perform public.log_audited_rpc_change(", adjustment_body)
        self.assertIn("metas.adjust", adjustment_body)
        self.assertIn("'target_event'", adjustment_body)
        self.assertIn("v_motivo_codigo not in ('correcao_lancamento', 'ajuste_meta', 'campanha_excepcional', 'outro')", adjustment_body)
        self.assertIn("motivo_detalhe is required when motivo_codigo is outro", adjustment_body)
        self.assertIn("public.lock_com_meta_pessoa_periodo", adjustment_body)

    def test_sale_open_rpc_uses_order_date_and_idempotency_lock(self) -> None:
        body = self._function_body("registrar_com_meta_venda_aberta")
        text = MIGRATION_0032.read_text(encoding="utf-8")

        self.assertIn("metas.sales.register", body)
        self.assertIn("'target_event'", body)
        self.assertIn("v_pedido.status <> 'open'", body)
        self.assertIn("v_pedido.tipo_pedido <> 'venda'", body)
        self.assertIn("public.resolve_com_meta_periodo(v_pedido.data_pedido)", body)
        self.assertIn("public.lock_com_meta_pessoa_periodo", body)
        self.assertIn("'period_rule', 'data_pedido'", body)
        self.assertIn("meta sale already registered for pedido", body)
        self.assertIn("idx_com_meta_venda_aberta_once", text)

    def test_cancellation_and_return_rpcs_register_negative_events_without_reopening_original_period(self) -> None:
        cancel_body = self._function_body("registrar_com_meta_cancelamento_pedido")
        return_body = self._function_body("registrar_com_meta_devolucao_nf")

        self.assertIn("metas.cancellations.register", cancel_body)
        self.assertIn("v_pedido.status <> 'cancelled'", cancel_body)
        self.assertIn("public.resolve_com_meta_periodo(p_data_evento)", cancel_body)
        self.assertIn("-1 * abs(v_venda.valor_meta)", cancel_body)
        self.assertIn("'period_rule', 'data_evento'", cancel_body)
        self.assertIn("'cancelamento_abate_periodo_vigente', true", cancel_body)

        self.assertIn("metas.returns.register", return_body)
        self.assertIn("v_nota.tipo <> 'devolucao'", return_body)
        self.assertIn("motivo_devolucao", return_body)
        self.assertIn("v_motivo_devolucao = 'qualidade'", return_body)
        self.assertIn("'qualidade_sem_penalizacao', true", return_body)
        self.assertIn("'devolucao_abate_periodo_vigente', true", return_body)
        self.assertIn("meta sale event not found for returned item", return_body)

    def test_docs_record_0032_scope_and_validation(self) -> None:
        commissions_doc = COMMISSIONS_DOC.read_text(encoding="utf-8")
        recipe_doc = RECIPE_DOC.read_text(encoding="utf-8")
        matrix_doc = SECURITY_MATRIX_DOC.read_text(encoding="utf-8")
        validation_doc = VALIDATION_DOC.read_text(encoding="utf-8")

        self.assertIn("Entrega tecnica 0032 - ledger de metas", commissions_doc)
        self.assertIn("nao chama o ledger de metas automaticamente", commissions_doc)
        self.assertIn("target_event", recipe_doc)
        self.assertIn("lock de pessoa + periodo", recipe_doc)
        self.assertIn("| metas |", matrix_doc)
        self.assertIn("0032_metas_event_ledger_contract.sql", validation_doc)
        self.assertIn("PG_VALIDATE_0032_WITH_SMOKE_OK", validation_doc)

    def _function_body(self, function_name: str) -> str:
        text = MIGRATION_0032.read_text(encoding="utf-8")
        pattern = re.compile(
            rf"create or replace function public\.{re.escape(function_name)}\b.*?\n\$\$;",
            re.DOTALL | re.IGNORECASE,
        )
        match = pattern.search(text)
        self.assertIsNotNone(match, f"Function {function_name} not found")
        return match.group(0).lower()


if __name__ == "__main__":
    unittest.main()
