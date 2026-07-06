from __future__ import annotations

import unittest
from pathlib import Path


REPO_ROOT = Path(__file__).resolve().parents[1]
SWEEP_SQL = REPO_ROOT / "tests" / "sql" / "zero_grant_default_deny_sweep.sql"
MIGRATION_0037 = REPO_ROOT / "supabase" / "migrations" / "0037_pre_permission_guard_wrappers.sql"
VALIDATION_DOC = REPO_ROOT / "docs" / "validacao_zero_grant_sweep_completo.md"
RECIPE_DOC = REPO_ROOT / "docs" / "receita_rls_rpc_auditada.md"
SECURITY_DOC = REPO_ROOT / "docs" / "decisao_seguranca_admin_rpcs.md"


class ZeroGrantDefaultDenySweepTests(unittest.TestCase):
    def test_sweep_sql_uses_catalog_discovery_not_manual_rpc_list(self) -> None:
        sql = SWEEP_SQL.read_text(encoding="utf-8")

        self.assertIn("pg_proc", sql)
        self.assertIn("pg_get_functiondef", sql)
        self.assertIn("regexp_matches", sql)
        self.assertIn("zero_grant_sweep_targets", sql)
        self.assertNotIn("array['create_cad_cliente'", sql)
        self.assertIn("proname not like '%_impl_0037'", sql)

    def test_sweep_sql_builds_true_zero_grant_actor(self) -> None:
        sql = SWEEP_SQL.read_text(encoding="utf-8")

        self.assertIn("Zero Grant Sweep Actor", sql)
        self.assertIn("delete from public.user_permission_overrides", sql)
        self.assertIn("set default_allowed = false", sql)
        self.assertIn("request.jwt.claim.sub", sql)

    def test_sweep_scope_excludes_security_but_includes_finished_operational_domains(self) -> None:
        sql = SWEEP_SQL.read_text(encoding="utf-8")

        for domain in ("cadastros", "estoque", "pcp", "faturamento", "financeiro", "pedidos"):
            self.assertIn(domain, sql)

        self.assertIn("romaneios", sql)
        self.assertIn("importacao", sql)
        self.assertIn("metas", sql)
        self.assertIn("proname not like 'list_security_%'", sql)
        self.assertIn("proname not like '%security_%'", sql)
        self.assertNotIn("security.manage_users", sql)
        self.assertNotIn("security.manage_permissions", sql)

    def test_sweep_requires_permission_denial_log_and_no_operational_writes(self) -> None:
        sql = SWEEP_SQL.read_text(encoding="utf-8")

        self.assertIn("log_permission_denied", sql)
        self.assertIn("origin = 'zero_grant_sweep'", sql)
        self.assertIn("permission_denied_log_not_persisted", sql)
        self.assertIn("non_audit_table_count_changed_after_denied_call", sql)
        self.assertIn("rpc_returned_success_for_zero_grant_actor", sql)
        self.assertIn("unexpected_exception_before_permission_denial", sql)
        self.assertIn("ZERO_GRANT_SWEEP_FAILED", sql)
        self.assertIn("ZERO_GRANT_SWEEP_OK", sql)

    def test_0037_wraps_pre_permission_debt_without_exposing_impl_functions(self) -> None:
        sql = MIGRATION_0037.read_text(encoding="utf-8")

        for function_name in (
            "cancelar_com_pedido",
            "create_com_pedido_operacional",
            "create_com_pedido_troca",
            "emitir_fat_nota_fiscal",
            "finalizar_pcp_op",
            "registrar_com_pedido_estorno_pos_pagamento",
            "registrar_fin_recebimento_alocado",
            "upsert_com_meta_periodo",
        ):
            with self.subTest(function=function_name):
                self.assertIn(f"rename to {function_name}_impl_0037", sql)
                self.assertIn(f"create or replace function public.{function_name}", sql)
                self.assertIn(f"public.{function_name}_impl_0037", sql)

        self.assertIn("revoke all on function public.cancelar_com_pedido_impl_0037", sql)
        self.assertIn("from public, authenticated", sql)
        self.assertIn("perform public.require_current_user_permission('pedidos.cancel')", sql)
        self.assertIn("perform public.require_current_user_permission('pcp.op.finish')", sql)
        self.assertIn("perform public.require_current_user_permission('financeiro.receipts.register')", sql)

    def test_docs_record_sweep_contract_and_security_invite_decision(self) -> None:
        docs = "\n".join(
            (
                VALIDATION_DOC.read_text(encoding="utf-8"),
                RECIPE_DOC.read_text(encoding="utf-8"),
                SECURITY_DOC.read_text(encoding="utf-8"),
            )
        )

        self.assertIn("zero grant", docs.lower())
        self.assertIn("`seguranca` fica fora", docs)
        self.assertIn("PostgreSQL descartavel", docs)
        self.assertIn("inviteUserByEmail", docs)
        self.assertIn("nao senha temporaria", docs)
        self.assertIn("Nenhuma senha, token de convite ou credencial", docs)


if __name__ == "__main__":
    unittest.main()
