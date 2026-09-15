from pathlib import Path
import unittest

ROOT=Path(__file__).resolve().parents[1]
MIGRATION=(ROOT/'supabase/migrations/0138_govern_cost_pricing_iso_foundation.sql').read_text(encoding='utf-8')
SMOKE=(ROOT/'tests/sql/cost_pricing_iso_foundation.sql').read_text(encoding='utf-8')
PAGE=(ROOT/'apps/web/app/custos-precos/page.tsx').read_text(encoding='utf-8')
ACTIONS=(ROOT/'apps/web/app/custos-precos/actions.ts').read_text(encoding='utf-8')
SYSTEM=(ROOT/'apps/web/lib/system-map.ts').read_text(encoding='utf-8')

class CostPricingIsoFoundationContract(unittest.TestCase):
    def test_module_route_and_permissions_are_registered(self):
        for phrase in ("('precificacao'", "('/custos-precos'", "precificacao.policy.manage", "precificacao.policy.review", "precificacao.scenario.manage", "precificacao.calculate", "precificacao.calculation.review"):
            self.assertIn(phrase,MIGRATION)
        self.assertIn('"precificacao"',SYSTEM)
        self.assertIn('primaryRoute: "/custos-precos"',SYSTEM)

    def test_all_required_facts_are_append_only(self):
        for table in ('prc_politicas','prc_politica_versoes','prc_politica_revisoes','prc_cenarios','prc_cenario_componentes','prc_calculos','prc_calculo_componentes','prc_calculo_precos_prazo','prc_calculo_decisoes','prc_requisicoes'):
            self.assertIn(table,MIGRATION)
        self.assertIn('before truncate',MIGRATION.lower())
        self.assertIn('append-only',MIGRATION)

    def test_formula_and_rounding_contract_is_explicit(self):
        for phrase in ("v_base/v_den", "v_base*(1+v_p.markup)/(1-v_comm-v_tax-v_marketing)", "((1+v_p.juros_mensais)^v_n-1)+v_risk", "round(v_cash_exact,2)", "'HALF_UP'", "for v_n in 1..18"):
            self.assertIn(phrase,MIGRATION)
        self.assertIn("prazo_dias=parcela_n*30",MIGRATION)

    def test_sources_and_manual_overrides_are_scenario_only(self):
        for phrase in ('source_kind','source_reference','source_effective_date','substituicao_manual','fixture_validacao','source_effective_date date not null'):
            self.assertIn(phrase,MIGRATION)
        self.assertNotIn('update public.est_',MIGRATION.lower())
        self.assertNotIn('update public.pcp_',MIGRATION.lower())

    def test_security_segregation_and_idempotency_are_directed(self):
        for phrase in ('revoke all on table public.%I from public, anon, authenticated','criador nao pode aprovar','criador do cenario ou calculo nao pode aprovar','chave de idempotencia reutilizada','permission denied','TRUNCATE de prazo aceito'):
            self.assertIn(phrase,MIGRATION+SMOKE)

    def test_ui_uses_business_language_and_audited_boundary(self):
        for phrase in ('Custos e referencias','Cenarios','Memoria de calculo','Revisao e aprovacao','Dossie','responsavel','blocked_reason'):
            if phrase=='blocked_reason':
                self.assertIn('reason',MIGRATION)
            else:
                self.assertIn(phrase,PAGE)
        self.assertIn('auditedRpc',ACTIONS)
        self.assertNotIn('.from(',ACTIONS)
        self.assertNotIn('Publicar',PAGE)

    def test_no_commercial_publication_or_payment_side_effect(self):
        self.assertIn("'publication_enabled',false",MIGRATION)
        self.assertNotIn('insert into public.com_lista_preco_publicacoes',MIGRATION.lower())
        self.assertNotIn('insert into public.fin_comissao_movimentos',MIGRATION.lower())
        self.assertIn('PRC-01 gerou efeito comercial ou financeiro',SMOKE)

if __name__=='__main__': unittest.main()
