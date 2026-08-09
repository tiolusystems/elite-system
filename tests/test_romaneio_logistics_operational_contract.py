from __future__ import annotations

from pathlib import Path
import re
import unittest


ROOT = Path(__file__).resolve().parents[1]
MIGRATION = ROOT / "supabase" / "migrations" / "0059_romaneio_logistics_operational_contract.sql"
PAGE = ROOT / "apps" / "web" / "app" / "romaneios" / "page.tsx"
PREPARATION = ROOT / "apps" / "web" / "app" / "romaneios" / "romaneio-preparation.tsx"
ACTIONS = ROOT / "apps" / "web" / "app" / "romaneios" / "actions.ts"
READ_MODEL = ROOT / "apps" / "web" / "lib" / "romaneios.ts"
STYLES = ROOT / "apps" / "web" / "app" / "globals.css"
SMOKE = ROOT / "tests" / "sql" / "romaneio_logistics_operational_contract.sql"
CI = ROOT / ".github" / "workflows" / "ci.yml"
SECURITY_MATRIX = ROOT / "docs" / "matriz_seguranca_alcadas.md"
VALIDATION = ROOT / "docs" / "validacao_romaneio_logistica_operacional_0059.md"
SYSTEM_MAP = ROOT / "apps" / "web" / "lib" / "system-map.ts"


class RomaneioLogisticsOperationalContractTests(unittest.TestCase):
    @classmethod
    def setUpClass(cls) -> None:
        cls.sql = MIGRATION.read_text(encoding="utf-8").lower()
        cls.page = PAGE.read_text(encoding="utf-8")
        cls.preparation = PREPARATION.read_text(encoding="utf-8")
        cls.actions = ACTIONS.read_text(encoding="utf-8")
        cls.read_model = READ_MODEL.read_text(encoding="utf-8")

    def function_body(self, name: str) -> str:
        match = re.search(
            rf"create or replace function public\.{name}\(.*?\)\s*returns bigint.*?as \$\$(.*?)\$\$;",
            self.sql,
            re.DOTALL,
        )
        self.assertIsNotNone(match, name)
        return match.group(1)

    def test_permission_actions_belong_to_expedicao_and_are_write_actions(self) -> None:
        for action in ("romaneios.logistics.assign", "romaneios.logistics.remove"):
            self.assertIn(f"'{action}'", self.sql)
        self.assertGreaterEqual(self.sql.count("'expedicao'"), 4)
        self.assertGreaterEqual(self.sql.count("'write'"), 2)

    def test_each_rpc_denies_before_reading_operational_state(self) -> None:
        for function_name, action_key in (
            ("registrar_exp_romaneio_logistica_atribuicao", "romaneios.logistics.assign"),
            ("registrar_exp_romaneio_logistica_remocao", "romaneios.logistics.remove"),
        ):
            body = self.function_body(function_name)
            permission_index = body.index("public.begin_audited_rpc")
            lookup_index = body.index("from public.exp_romaneios")
            validation_index = body.index("romaneio_id is required")
            self.assertLess(permission_index, validation_index)
            self.assertLess(permission_index, lookup_index)
            self.assertIn(action_key, body)
            self.assertIn("public.log_audited_rpc_change", body)
            self.assertIn("correlation_id", body)

    def test_logistics_change_is_append_only_and_validated_relationally(self) -> None:
        self.assertEqual(self.sql.count("insert into public.exp_romaneio_logistica_eventos"), 2)
        self.assertNotIn("update public.exp_romaneio_logistica_eventos", self.sql)
        self.assertNotIn("delete from public.exp_romaneio_logistica_eventos", self.sql)
        for fragment in (
            "join public.cad_pessoa_papeis",
            "papel.papel = 'entregador'",
            "pessoa.status = 'active'",
            "veiculo.status = 'active'",
            "for update",
            "romaneio status does not allow logistics assignment",
            "motivo is required",
        ):
            self.assertIn(fragment, self.sql)

    def test_rpc_surface_is_authenticated_only(self) -> None:
        for signature in (
            "registrar_exp_romaneio_logistica_atribuicao(bigint, bigint, bigint, text)",
            "registrar_exp_romaneio_logistica_remocao(bigint, text)",
        ):
            self.assertIn(f"revoke all on function public.{signature}", self.sql)
            self.assertIn(f"grant execute on function public.{signature}", self.sql)
        self.assertNotIn("disable row level security", self.sql)
        self.assertIsNone(re.search(r"grant\s+execute.*?\s+to\s+(public|anon)\b", self.sql, re.DOTALL))

    def test_web_uses_structured_ids_and_audited_server_actions(self) -> None:
        web = self.page + self.preparation
        self.assertNotIn("<datalist", web)
        self.assertNotIn("lookupValue", web)
        for field in ("pedido_item_id", "romaneio_id", "romaneio_item_id", "lote_pa_id"):
            self.assertIn(f'name="{field}"', web)
        for rpc in (
            "registrar_exp_romaneio_logistica_atribuicao",
            "registrar_exp_romaneio_logistica_remocao",
        ):
            self.assertIn(f'auditedRpc(supabase, "{rpc}"', self.actions)
        self.assertNotIn(".rpc(", self.actions)
        self.assertNotIn("value.match", self.actions)

    def test_read_model_and_screen_expose_current_assignment(self) -> None:
        for source in (
            "exp_romaneio_logistica_atual",
            "cad_pessoas_comerciais_papeis_ativos",
            "cad_veiculos",
            "fat_notas_fiscais",
        ):
            self.assertIn(f'.from("{source}")', self.read_model)
        for text in (
            "Entrega e expedicao",
            "Atribuir entrega",
            "Atualizar entrega",
            "Remover atribuicao",
            "Referências fiscais externas",
            "Registrar o número não baixa estoque nem libera comissão.",
        ):
            self.assertIn(text, self.page)
        self.assertIn(".compact-action-form select", STYLES.read_text(encoding="utf-8"))

    def test_transactional_smoke_is_wired_into_ci(self) -> None:
        self.assertTrue(SMOKE.exists())
        smoke = SMOKE.read_text(encoding="utf-8")
        self.assertIn("PG_VALIDATE_0059_WITH_SMOKE_OK", smoke)
        self.assertIn("not allowed: romaneios.logistics.assign", smoke)
        self.assertIn("expected two append-only logistics events", smoke)
        self.assertIn(
            "tests/sql/romaneio_logistics_operational_contract.sql",
            CI.read_text(encoding="utf-8"),
        )

    def test_ownership_permissions_and_validation_are_documented(self) -> None:
        matrix = SECURITY_MATRIX.read_text(encoding="utf-8")
        validation = VALIDATION.read_text(encoding="utf-8")
        for action in ("romaneios.logistics.assign", "romaneios.logistics.remove"):
            self.assertIn(action, matrix)
            self.assertIn(action, validation)
        self.assertIn("NF permanece propriedade de faturamento", matrix)
        self.assertIn("PG_VALIDATE_0059_WITH_SMOKE_OK", validation)
        system_map = SYSTEM_MAP.read_text(encoding="utf-8")
        self.assertIn('"Entregador e veiculo"', system_map)
        self.assertIn('"Situacao fiscal"', system_map)


if __name__ == "__main__":
    unittest.main()
