from pathlib import Path
import re
import unittest

ROOT = Path(__file__).resolve().parents[1]


class SecuritySqlSurfaceContractTests(unittest.TestCase):
    EXPECTED_SIGNATURES = {
        'public.prevent_com_lista_preco_import_fact_changes()',
        'public.normalizar_com_lista_preco_valor_bruto(text)',
        'public.ord01_comparacao_original_persistida(bigint)',
        'public.ord01_revision_current_pre_effective_state(bigint)',
        'public.ord01_revision_impact_mask(jsonb,jsonb)',
        'public.avaliar_com_pedido_efetividade(bigint)',
        'public.ord01_contract_genesis_state(bigint)',
        'public.resolver_cad_pessoa_cadeia_comercial(bigint,date)',
    }

    def setUp(self) -> None:
        self.migrations = '\n'.join(
            (ROOT / 'supabase/migrations' / name).read_text(encoding='utf-8').lower()
            for name in (
                '0141_harden_list_price_internal_helpers.sql',
                '0142_harden_ord01_internal_helpers.sql',
                '0143_harden_commercial_resolvers.sql',
                '0144_canonicalize_governed_read_security.sql',
            )
        )
        self.migrations_compact = re.sub(r'\s+', '', self.migrations)
        self.migration = (ROOT / 'supabase/migrations/0144_canonicalize_governed_read_security.sql').read_text(encoding='utf-8').lower()
        self.smoke = (ROOT / 'tests/sql/security_0141_0144_canonical_surfaces.sql').read_text(encoding='utf-8').lower()
        self.gate = (ROOT / 'tests/sql/security_zero_direct_write_gate.sql').read_text(encoding='utf-8').lower()

    def test_additive_migrations_and_smoke_exist(self) -> None:
        migrations = ROOT / 'supabase' / 'migrations'
        self.assertEqual(len(list(migrations.glob('014[1-4]_*.sql'))), 4)
        self.assertTrue((ROOT / 'tests/sql/security_0141_0144_canonical_surfaces.sql').exists())

    def test_exact_private_inventory_and_orphan_guard(self) -> None:
        for signature in self.EXPECTED_SIGNATURES:
            self.assertIn(re.sub(r'\s+', '', signature), self.migrations_compact)
            self.assertIn(signature, self.smoke)
        self.assertIn('to_regprocedure(v_signature) is null', self.migration)
        self.assertIn('canonical sql surface references missing function', self.migration)

    def test_gate_uses_explicit_surface_metadata(self) -> None:
        for text in ('security_sql_surface_contracts', 'governed_read_invoker_rls', 'rls_preserved'):
            self.assertIn(text, self.gate)
            self.assertIn(text, self.migration)
        for text in ('read_only', 'explicit_contract', 'contains a write operation', 'dependency lacks rls'):
            self.assertIn(text, self.gate)

    def test_invoker_read_and_acl_contract_is_explicit(self) -> None:
        for signature in (
            'public.consultar_cad_clientes_paginada(text,text,text,integer,integer)',
            'public.buscar_exp_romaneios_paginada(text,bigint,bigint,bigint,bigint,text,date,date,text[],bigint,bigint,bigint,bigint,integer,integer)',
            'public.consultar_est_estoque_pa_posicao(date)',
        ):
            self.assertIn(signature, self.migration)
            self.assertIn(signature, self.smoke)
        for text in ('prosecdef', 'has_function_privilege', "'public'", "'anon'", "'authenticated'"):
            self.assertIn(text, self.smoke)

    def test_ci_registers_canonical_smoke(self) -> None:
        ci = (ROOT / '.github/workflows/ci.yml').read_text(encoding='utf-8').lower()
        self.assertIn('security_0141_0144_canonical_surfaces.sql', ci)

    def test_resolver_volatility_is_documented_and_tested(self) -> None:
        resolver = (ROOT / 'supabase/migrations/0143_harden_commercial_resolvers.sql').read_text(encoding='utf-8').lower()
        security_doc = (ROOT / 'docs/decisoes-arquiteturais/SECURITY_SQL_SURFACES.md').read_text(encoding='utf-8').lower()
        self.assertIn('volatile security definer', resolver)
        self.assertIn('volatile', security_doc)
        self.assertIn('resolver_com_referencia_comercial', security_doc)


if __name__ == '__main__':
    unittest.main()
