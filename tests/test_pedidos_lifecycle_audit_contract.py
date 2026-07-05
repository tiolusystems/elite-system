from __future__ import annotations

import re
import unittest
from pathlib import Path


REPO_ROOT = Path(__file__).resolve().parents[1]
MIGRATION_0028 = REPO_ROOT / "supabase" / "migrations" / "0028_pedidos_lifecycle_audit_contract.sql"
PEDIDOS_ACTIONS = REPO_ROOT / "apps" / "web" / "app" / "pedidos" / "actions.ts"
MATRIX_DOC = REPO_ROOT / "docs" / "matriz_seguranca_alcadas.md"
RECIPE_DOC = REPO_ROOT / "docs" / "receita_rls_rpc_auditada.md"
VALIDATION_DOC = REPO_ROOT / "docs" / "validacao_pedidos_lifecycle_audit_contract.md"


class PedidosLifecycleAuditContractTests(unittest.TestCase):
    def test_0028_defines_status_transition_matrix_and_action_keys(self) -> None:
        text = MIGRATION_0028.read_text(encoding="utf-8")

        self.assertIn("create table if not exists public.com_pedido_status_transicoes", text)
        self.assertIn("'pedidos.create.own'", text)
        self.assertIn("'pedidos.create.any'", text)
        self.assertIn("'pedidos.credit.review'", text)
        self.assertIn("'pedidos.status.transition'", text)
        self.assertIn("'pedidos.cancel'", text)
        for event in ("credit_liberado", "credit_bloqueado", "credit_pendente", "cancel", "romaneio_fulfilled"):
            self.assertIn(event, text)

    def test_0028_blocks_direct_order_writes_and_keeps_read_policies(self) -> None:
        text = MIGRATION_0028.read_text(encoding="utf-8")

        for policy in (
            'drop policy if exists "authenticated full order access"',
            'drop policy if exists "authenticated full order item access"',
            'drop policy if exists "authenticated full order commission access"',
            'drop policy if exists "authenticated full order credit access"',
            'drop policy if exists "authenticated full order sequence access"',
        ):
            self.assertIn(policy, text)

        for table in (
            "public.com_pedidos",
            "public.com_pedido_itens",
            "public.com_pedido_comissionados",
            "public.com_pedido_credito_decisoes",
            "public.com_pedido_sequencias_propriedade",
        ):
            self.assertIn(table, text)

        self.assertIn("revoke insert, update, delete on", text)
        self.assertIn("create policy \"authenticated read com_pedidos\"", text)
        self.assertIn("public.current_actor_id() is not null", text)

    def test_create_credit_and_cancel_rpcs_use_audited_contract(self) -> None:
        text = MIGRATION_0028.read_text(encoding="utf-8")

        for function_name, action_key, axis in (
            ("create_com_pedido_operacional", "pedidos.create.", "own_any"),
            ("registrar_com_pedido_decisao_credito", "pedidos.credit.review", "status_transition"),
            ("cancelar_com_pedido", "pedidos.cancel", "status_transition"),
        ):
            body = self._function_body(text, function_name)
            self.assertIn("public.begin_audited_rpc(", body)
            self.assertIn("perform public.log_audited_rpc_change(", body)
            self.assertIn(axis, body)
            self.assertIn(action_key, body)
            self.assertNotIn("perform public.log_action(", body)

        self.assertIn("return public.create_com_pedido_operacional(", self._function_body(text, "create_com_pedido_rascunho"))

    def test_credit_and_cancel_lock_order_before_transition(self) -> None:
        text = MIGRATION_0028.read_text(encoding="utf-8")

        for function_name in ("registrar_com_pedido_decisao_credito", "cancelar_com_pedido"):
            body = self._function_body(text, function_name)
            self.assertIn("from public.com_pedidos", body)
            self.assertIn("for update", body)
            self.assertIn("public.validate_com_pedido_status_transition", body)
            self.assertIn("public.com_pedido_audit_snapshot", body)

        cancel_body = self._function_body(text, "cancelar_com_pedido")
        self.assertIn("pedido has active romaneio; cancel romaneio first", cancel_body)
        self.assertIn("pedido has active nota fiscal; cancel fiscal document first", cancel_body)
        self.assertIn("pedido has active receipt; reverse receipt first", cancel_body)

    def test_sequence_helper_is_not_executable_directly(self) -> None:
        text = MIGRATION_0028.read_text(encoding="utf-8")

        self.assertIn("revoke all on function public.next_com_pedido_sequencia(bigint, bigint) from public", text)
        self.assertIn("revoke all on function public.next_com_pedido_sequencia(bigint, bigint) from authenticated", text)
        self.assertNotIn("grant execute on function public.next_com_pedido_sequencia(bigint, bigint) to authenticated", text)

    def test_pedidos_server_actions_supply_failure_contract_metadata(self) -> None:
        text = PEDIDOS_ACTIONS.read_text(encoding="utf-8")

        for expected in (
            'action_key: "pedidos.create"',
            'axis: "own_any"',
            'domain: "pedidos"',
            'entity: "com_pedidos"',
            'failure_action: "pedidos.create_failed"',
            'action_key: "pedidos.credit.review"',
            'axis: "status_transition"',
            'entity: "com_pedido_credito_decisoes"',
            'failure_action: "pedidos.credit_review_failed"',
        ):
            self.assertIn(expected, text)

    def test_docs_record_pedidos_status_transition_pattern(self) -> None:
        matrix = MATRIX_DOC.read_text(encoding="utf-8")
        recipe = RECIPE_DOC.read_text(encoding="utf-8")
        validation = VALIDATION_DOC.read_text(encoding="utf-8")

        self.assertIn("tabela de transicoes criada na `0028`", matrix)
        self.assertIn("O registro tem ciclo de vida operacional por status?", recipe)
        self.assertIn("axis = status_transition", recipe)
        self.assertIn("Cancelamento de pedido nao tenta desfazer romaneio", validation)
        self.assertNotIn("liberaÃ", recipe)

    def _function_body(self, text: str, function_name: str) -> str:
        pattern = re.compile(
            rf"create or replace function public\.{re.escape(function_name)}\b.*?\n\$\$;",
            re.DOTALL | re.IGNORECASE,
        )
        match = pattern.search(text)
        self.assertIsNotNone(match, f"Function {function_name} not found")
        return match.group(0).lower()


if __name__ == "__main__":
    unittest.main()
