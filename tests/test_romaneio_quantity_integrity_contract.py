from __future__ import annotations

from pathlib import Path
import re
import unittest


ROOT = Path(__file__).resolve().parents[1]
MIGRATION = ROOT / "supabase" / "migrations" / "0060_romaneio_quantity_integrity_contract.sql"
READ_MODEL = ROOT / "apps" / "web" / "lib" / "romaneios.ts"
PAGE = ROOT / "apps" / "web" / "app" / "romaneios" / "page.tsx"
ACTIONS = ROOT / "apps" / "web" / "app" / "romaneios" / "actions.ts"
SMOKE = ROOT / "tests" / "sql" / "romaneio_quantity_integrity_contract.sql"
CI = ROOT / ".github" / "workflows" / "ci.yml"
VALIDATION = ROOT / "docs" / "validacao_romaneio_integridade_quantitativa_0060.md"


class RomaneioQuantityIntegrityContractTests(unittest.TestCase):
    @classmethod
    def setUpClass(cls) -> None:
        cls.sql = MIGRATION.read_text(encoding="utf-8").lower()
        cls.read_model = READ_MODEL.read_text(encoding="utf-8")
        cls.page = PAGE.read_text(encoding="utf-8")

    def function_body(self, name: str) -> str:
        match = re.search(
            rf"create or replace function public\.{name}\(.*?\)\s*returns bigint.*?as \$\$(.*?)\$\$;",
            self.sql,
            re.DOTALL,
        )
        self.assertIsNotNone(match, name)
        return match.group(1)

    def test_view_separates_fulfilment_pending_from_free_allocation(self) -> None:
        for column in (
            "quantidade_confirmada",
            "quantidade_em_separacao",
            "quantidade_pendente",
            "quantidade_comprometida",
            "quantidade_disponivel_romaneio",
            "quantidade_excedente",
        ):
            self.assertIn(column, self.sql)
        self.assertIn("with (security_invoker = true)", self.sql)
        self.assertIn("romaneio.status in ('draft', 'separacao', 'confirmado')", self.sql)
        self.assertIn("item.quantidade - coalesce(quantities.quantidade_comprometida, 0)", self.sql)

    def test_database_trigger_locks_parent_item_and_rejects_overcommit(self) -> None:
        self.assertIn("create trigger trg_exp_romaneio_item_quantity", self.sql)
        body = re.search(
            r"create or replace function public\.enforce_exp_romaneio_item_quantity\(\).*?as \$\$(.*?)\$\$;",
            self.sql,
            re.DOTALL,
        )
        self.assertIsNotNone(body)
        trigger_body = body.group(1)
        self.assertIn("from public.com_pedido_itens", trigger_body)
        self.assertIn("for update", trigger_body)
        self.assertIn("v_other_committed + new.quantidade_romaneada > v_order_quantity", trigger_body)
        self.assertIn("errcode = '23514'", trigger_body)

    def test_create_and_add_rpc_deny_before_validation_and_use_free_balance(self) -> None:
        for function_name in ("create_exp_romaneio", "add_exp_romaneio_item"):
            body = self.function_body(function_name)
            self.assertLess(body.index("public.begin_audited_rpc"), body.index("is required"))
            self.assertIn("quantidade_disponivel_romaneio", body)
            self.assertIn("public.log_audited_rpc_change", body)
            self.assertIn("correlation_id", body)
        self.assertIn("romaneio must start as draft", self.sql)
        self.assertIn("pa lot must be reserved after romaneio creation", self.sql)

    def test_api_surface_is_authenticated_only_and_legacy_path_is_closed(self) -> None:
        signatures = (
            "create_exp_romaneio(bigint, bigint, numeric, text, text, text, text)",
            "add_exp_romaneio_item(bigint, bigint, numeric, text)",
            "registrar_est_reserva_pa(bigint, bigint, numeric, text)",
            "confirmar_exp_romaneio(bigint, text)",
            "cancelar_exp_romaneio(bigint, text)",
            "estornar_exp_romaneio(bigint, text)",
        )
        for signature in signatures:
            self.assertIn(f"revoke all on function public.{signature}", self.sql)
            self.assertIn(f"grant execute on function public.{signature}", self.sql)
        self.assertIn(
            "revoke all on function public.registrar_exp_romaneio_separacao(bigint, text, text)",
            self.sql,
        )
        self.assertNotIn(
            "grant execute on function public.registrar_exp_romaneio_separacao(bigint, text, text)",
            self.sql,
        )
        self.assertNotIn("disable row level security", self.sql)

    def test_web_only_offers_items_with_free_quantity(self) -> None:
        for field in (
            "quantidade_comprometida",
            "quantidade_disponivel_romaneio",
            "quantidade_excedente",
        ):
            self.assertIn(field, self.read_model)
        self.assertIn(
            "pendingItems.filter((item) => item.quantidadeDisponivelRomaneio > 0)",
            self.read_model,
        )
        self.assertIn("Livre para novo romaneio", self.page)
        self.assertIn("Nenhum item com saldo livre", self.page)
        self.assertIn("disabled={dashboard.lookups.pendingItems.length === 0}", self.page)
        self.assertIn('auditedRpc(supabase, "create_exp_romaneio"', ACTIONS.read_text(encoding="utf-8"))

    def test_transactional_smoke_and_documentation_are_wired(self) -> None:
        smoke = SMOKE.read_text(encoding="utf-8")
        self.assertIn("PG_VALIDATE_0060_WITH_SMOKE_OK", smoke)
        self.assertIn("RPC accepted quantity above the free order balance", smoke)
        self.assertIn("table trigger accepted an overcommitted romaneio item", smoke)
        self.assertIn("cancelled romaneio did not release allocation", smoke)
        self.assertIn("tests/sql/romaneio_quantity_integrity_contract.sql", CI.read_text(encoding="utf-8"))
        self.assertIn("PG_VALIDATE_0060_WITH_SMOKE_OK", VALIDATION.read_text(encoding="utf-8"))


if __name__ == "__main__":
    unittest.main()
