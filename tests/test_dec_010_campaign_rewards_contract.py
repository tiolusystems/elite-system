from __future__ import annotations

from pathlib import Path
import re
import unittest


ROOT = Path(__file__).resolve().parents[1]
MIGRATION = ROOT / "supabase" / "migrations" / "0053_dec_010_campaign_rewards_contract.sql"
SMOKE = ROOT / "tests" / "sql" / "dec_010_campaign_rewards.sql"
ADR = ROOT / "docs" / "decisoes-arquiteturais" / "ADR-010-campanhas-pontos-premios.md"
CI = ROOT / ".github" / "workflows" / "ci.yml"
UPGRADE_BEFORE = ROOT / "tests" / "sql" / "upgrade" / "dec_010_pre_0053_fixture.sql"
UPGRADE_AFTER = ROOT / "tests" / "sql" / "upgrade" / "dec_010_post_0053_verify.sql"


class Dec010CampaignRewardsContractTest(unittest.TestCase):
    @classmethod
    def setUpClass(cls) -> None:
        cls.sql = MIGRATION.read_text(encoding="utf-8").lower()
        cls.adr = ADR.read_text(encoding="utf-8").lower()

    def test_configuration_and_ledgers_are_relational(self) -> None:
        for table in (
            "cad_grupos_produto",
            "com_campanhas",
            "com_campanha_versoes",
            "com_campanha_regras",
            "com_campanha_regra_recompensas",
            "com_campanha_elegibilidades",
            "com_campanha_pontos_movimentos",
            "com_campanha_premios",
            "com_campanha_vouchers",
            "fin_campanha_premio_pagamentos",
        ):
            self.assertIn(f"create table public.{table}", self.sql)

        rule_block = re.search(
            r"create table public\.com_campanha_regras\s*\((.*?)\n\);",
            self.sql,
            re.DOTALL,
        )
        self.assertIsNotNone(rule_block)
        self.assertNotIn("json", rule_block.group(1))

    def test_campaign_activation_is_human_and_fail_closed(self) -> None:
        for fragment in (
            "only active human profiles can activate campaign versions",
            "campaign activation requires a proven start and end date",
            "campaign activation requires an approved rule with reward",
            "campaign activation requires approved eligibility",
        ):
            self.assertIn(fragment, self.sql)

    def test_points_prizes_and_commissions_are_separate(self) -> None:
        self.assertIn("ledger append-only de pontos. nao e ledger de comissao", self.sql)
        self.assertIn("premios de campanha separados da conta corrente de comissoes", self.sql)
        self.assertNotIn("insert into public.fin_comissao_movimentos", self.sql)
        self.assertIn("campanha_versao_id bigint references", self.sql)

    def test_historical_facts_are_pending_and_idempotent(self) -> None:
        for fragment in (
            "idx_com_campanhas_source_once",
            "idx_com_campanha_regras_source_once",
            "idx_com_campanha_pontos_source_once",
            "idx_com_campanha_premios_source_once",
            "enforce_historical_record_contract",
            "movement.origem_dados = 'sistema'",
        ):
            self.assertIn(fragment, self.sql)

    def test_versioned_configuration_and_event_ledgers_are_append_only(self) -> None:
        self.assertIn("prevent_campaign_fact_changes", self.sql)
        for table in (
            "com_campanha_versoes",
            "com_campanha_pontos_movimentos",
            "com_campanha_premio_eventos",
            "com_campanha_voucher_eventos",
            "fin_campanha_premio_pagamentos",
        ):
            self.assertIn(f"'{table}'", self.sql)

    def test_smoke_upgrade_and_ci_are_wired(self) -> None:
        self.assertTrue(SMOKE.exists())
        self.assertTrue(UPGRADE_BEFORE.exists())
        self.assertTrue(UPGRADE_AFTER.exists())
        self.assertIn(
            "tests/sql/dec_010_campaign_rewards.sql",
            CI.read_text(encoding="utf-8"),
        )

    def test_adr_documents_required_decision_elements(self) -> None:
        for heading in (
            "## chaves naturais e idempotencia",
            "## campos obrigatorios",
            "## campos opcionais",
            "## pendentes de revisao",
            "## backfill",
            "## rollback",
        ):
            self.assertIn(heading, self.adr)
        self.assertIn("## separacao de comissao", self.adr)


if __name__ == "__main__":
    unittest.main()
