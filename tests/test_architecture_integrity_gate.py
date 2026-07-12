from __future__ import annotations

import json
from pathlib import Path
import re
import unittest


ROOT = Path(__file__).resolve().parents[1]
MIGRATIONS = ROOT / "supabase" / "migrations"
RLS_GATE = MIGRATIONS / "0039_rls_direct_write_gate.sql"
RELATIONAL_GATE = MIGRATIONS / "0040_relational_integrity_normalization.sql"
CI_WORKFLOW = ROOT / ".github" / "workflows" / "ci.yml"
WEB_PACKAGE = ROOT / "apps" / "web" / "package.json"


class ArchitectureIntegrityGateTest(unittest.TestCase):
    def test_web_dependencies_are_exact_and_package_manager_is_pinned(self) -> None:
        package = json.loads(WEB_PACKAGE.read_text(encoding="utf-8"))

        self.assertEqual(package["packageManager"], "pnpm@11.11.0")
        for section in ("dependencies", "devDependencies"):
            for dependency, version in package[section].items():
                self.assertNotEqual(version, "latest", dependency)
                self.assertNotRegex(version, r"^[\^~*><=]", dependency)

    def test_ci_executes_python_web_and_disposable_database_contracts(self) -> None:
        workflow = CI_WORKFLOW.read_text(encoding="utf-8")

        for expected in (
            "python-tests:",
            "web-contract:",
            "database-contract:",
            "pnpm install --frozen-lockfile",
            "pnpm lint",
            "pnpm build",
            "supabase db reset",
            "supabase db lint --local",
            "supabase gen types --local --schema public",
            "elite-database-types",
            "tests/sql/architecture_integrity_gate.sql",
            "tests/sql/historical_mp_import_foundation.sql",
        ):
            self.assertIn(expected, workflow)

    def test_rls_gate_removes_direct_write_and_truncate_paths(self) -> None:
        sql = RLS_GATE.read_text(encoding="utf-8")

        for legacy_policy in (
            "authenticated full romaneio access",
            "authenticated full PCP order access",
            "authenticated full NFe XML access",
            "authenticated full source workbook access",
        ):
            self.assertIn(f'drop policy if exists "{legacy_policy}"', sql)

        self.assertIn("revoke insert, update, delete, truncate, references, trigger", sql)
        self.assertIn("alter default privileges for role postgres", sql)
        self.assertIn("public.current_actor_id() is not null", sql)

    def test_no_legacy_full_write_policy_survives_the_migration_chain(self) -> None:
        policies: dict[tuple[str, str], str] = {}
        event_pattern = re.compile(
            r'(drop\s+policy\s+if\s+exists\s+"([^"]+)"\s+on\s+public\.([a-z0-9_]+)\s*;'
            r'|create\s+policy\s+"([^"]+)"\s+on\s+public\.([a-z0-9_]+)(.*?)\s*;)',
            re.IGNORECASE | re.DOTALL,
        )

        for migration in sorted(MIGRATIONS.glob("*.sql")):
            text = migration.read_text(encoding="utf-8")
            for match in event_pattern.finditer(text):
                if match.group(2):
                    policies.pop((match.group(3), match.group(2)), None)
                else:
                    policies[(match.group(5), match.group(4))] = match.group(6)

        write_capable = {
            key: body
            for key, body in policies.items()
            if re.search(r"\bfor\s+all\b|\bfor\s+(?:insert|update|delete)\b", body, re.IGNORECASE)
        }
        self.assertEqual(write_capable, {})

    def test_operational_multivalues_and_weak_lot_link_are_relationalized(self) -> None:
        sql = RELATIONAL_GATE.read_text(encoding="utf-8")

        for expected in (
            "create table if not exists public.cad_pessoa_papeis",
            "create table if not exists public.pcp_op_cq_participantes",
            "rename column lote_mp_id to lote_mp_ref_legado",
            "add column if not exists lote_mp_id bigint",
            "foreign key (lote_mp_id) references public.est_lotes_mp(id)",
            "prevent_mp_base_unit_change_after_movement",
            "source_row_id does not belong to source_batch_id",
        ):
            self.assertIn(expected, sql)

    def test_cross_domain_repeated_ids_have_database_constraints(self) -> None:
        sql = RELATIONAL_GATE.read_text(encoding="utf-8")

        for constraint in (
            "est_movimentos_mp_lote_materia_fk",
            "est_reservas_pa_romaneio_item_fk",
            "exp_romaneio_itens_pedido_item_fk",
            "exp_mov_pa_romaneio_item_identity_fk",
            "fat_nf_itens_pedido_item_fk",
            "fat_nf_itens_romaneio_item_fk",
            "pcp_formula_ativacoes_identity_fk",
            "pcp_consumos_reserva_identity_fk",
        ):
            self.assertIn(constraint, sql)

    def test_every_created_business_table_declares_a_primary_key(self) -> None:
        without_primary_key: list[str] = []
        pattern = re.compile(
            r"create\s+table\s+if\s+not\s+exists\s+public\.([a-z0-9_]+)\s*\((.*?)\n\);",
            re.IGNORECASE | re.DOTALL,
        )

        for migration in sorted(MIGRATIONS.glob("*.sql")):
            text = migration.read_text(encoding="utf-8")
            for table, body in pattern.findall(text):
                if not re.search(r"\bprimary\s+key\b", body, re.IGNORECASE):
                    without_primary_key.append(table)

        self.assertEqual(without_primary_key, [])


if __name__ == "__main__":
    unittest.main()
