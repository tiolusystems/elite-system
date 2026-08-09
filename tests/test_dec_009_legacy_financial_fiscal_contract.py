from __future__ import annotations

from pathlib import Path
import re
import unittest


ROOT = Path(__file__).resolve().parents[1]
MIGRATION = ROOT / "supabase" / "migrations" / "0055_dec_009_legacy_financial_fiscal_contract.sql"
SMOKE = ROOT / "tests" / "sql" / "dec_009_legacy_financial_fiscal.sql"
ADR = ROOT / "docs" / "decisoes-arquiteturais" / "ADR-012-financeiro-fiscal-legado.md"
CI = ROOT / ".github" / "workflows" / "ci.yml"
UPGRADE_BEFORE = ROOT / "tests" / "sql" / "upgrade" / "dec_009_pre_0055_fixture.sql"
UPGRADE_AFTER = ROOT / "tests" / "sql" / "upgrade" / "dec_009_post_0055_verify.sql"


class Dec009LegacyFinancialFiscalContractTest(unittest.TestCase):
    @classmethod
    def setUpClass(cls) -> None:
        cls.sql = MIGRATION.read_text(encoding="utf-8").lower()
        cls.adr = ADR.read_text(encoding="utf-8").lower()

    def test_financial_and_fiscal_contracts_are_relational(self) -> None:
        for table in (
            "fin_pedido_planos_pagamento",
            "fin_pedido_parcelas",
            "fin_recebimento_posicoes_historicas",
            "fin_comissao_posicoes_historicas",
            "fat_referencias_fiscais_historicas",
        ):
            self.assertIn(f"create table public.{table}", self.sql)

        for block in re.findall(r"create table public\.[^(]+\s*\((.*?)\n\);", self.sql, re.DOTALL):
            self.assertNotIn(" json", block)

    def test_historical_facts_require_lineage_and_migration_actor(self) -> None:
        for fragment in (
            "source_batch_id bigint not null",
            "source_row_id bigint not null",
            "origem_dados = 'excel_legado'",
            "enforce_historical_record_contract",
            "migracao historica system actor is required by dec-009",
        ):
            self.assertIn(fragment, self.sql)

    def test_legacy_positions_do_not_create_operational_events(self) -> None:
        for forbidden in (
            "insert into public.com_recebimentos",
            "insert into public.fin_recebimento_alocacoes",
            "insert into public.fin_comissao_movimentos",
            "insert into public.fat_notas_fiscais",
        ):
            self.assertNotIn(forbidden, self.sql)
        self.assertIn("sem criar recebimento, data ou valor inexistente", self.sql)
        self.assertIn("sem promocao automatica para fat_notas_fiscais", self.sql)

    def test_payment_schedule_is_versioned_and_not_repeating_columns(self) -> None:
        self.assertIn("constraint fin_pedido_planos_key unique (pedido_id, versao)", self.sql)
        self.assertIn("numero_parcela", self.sql)
        self.assertNotIn("vencimento_01", self.sql)
        self.assertIn("fin_pedido_parcelas_atuais", self.sql)

    def test_facts_are_append_only_and_direct_write_is_revoked(self) -> None:
        self.assertIn("prevent_dec009_fact_changes", self.sql)
        self.assertIn(
            "revoke insert, update, delete, truncate on public.%i from public, anon, authenticated",
            self.sql,
        )

    def test_smoke_upgrade_and_ci_are_wired(self) -> None:
        self.assertTrue(SMOKE.exists())
        self.assertTrue(UPGRADE_BEFORE.exists())
        self.assertTrue(UPGRADE_AFTER.exists())
        self.assertIn(
            "tests/sql/dec_009_legacy_financial_fiscal.sql",
            CI.read_text(encoding="utf-8"),
        )

    def test_adr_documents_required_decision_elements(self) -> None:
        for heading in (
            "## ownership e dependencias",
            "## chaves naturais e idempotencia",
            "## campos obrigatorios",
            "## campos opcionais",
            "## pendentes de revisao",
            "## backfill",
            "## rollback",
        ):
            self.assertIn(heading, self.adr)


if __name__ == "__main__":
    unittest.main()
