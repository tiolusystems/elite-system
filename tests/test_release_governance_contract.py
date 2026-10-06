from pathlib import Path
import unittest


ROOT = Path(__file__).resolve().parents[1]
ADR = (ROOT / "docs/decisoes-arquiteturais/ADR-018_GOVERNANCA_AMBIENTES_RELEASE.md").read_text(encoding="utf-8")
AGENTS = (ROOT / "AGENTS.md").read_text(encoding="utf-8")
PROFILE = (ROOT / "docs/agent-protocol/ELITE_AGENT_PROFILE.md").read_text(encoding="utf-8")
CURRENT_STATE = (ROOT / "docs/01_ESTADO_ATUAL.md").read_text(encoding="utf-8")


class ReleaseGovernanceContract(unittest.TestCase):
    def test_canonical_release_topology_is_documented(self):
        self.assertIn("Status: APPROVED", ADR)
        self.assertIn("staging` e a branch permanente de integracao e homologacao", ADR)
        self.assertIn("`main` e a branch permanente de producao", ADR)
        self.assertIn("feature/* -> PR -> staging -> homologation -> release PR -> main", ADR)
        self.assertIn("Vercel `READY` nao e equivalente a deploy canonico.", ADR)
        self.assertIn("## Staged production release", ADR)
        self.assertIn("deployment Vercel com `target=production`", ADR)
        self.assertIn("nao uma versao publicada no dominio canonico", ADR)
        self.assertIn("`Auto-assign Custom Production Domains` permanece desabilitado", ADR)
        self.assertIn("promocao explicita do exato\ndeployment validado", ADR)
        self.assertIn("compatibilidade de\nbanco, ledger de migration, CI, smoke, SHA de release", ADR)

    def test_agent_contract_requires_the_canonical_path(self):
        self.assertIn("PRs ordinarias devem ter `staging` como destino.", AGENTS)
        self.assertIn("Preview de deploy nao e ambiente canonico", AGENTS)
        self.assertIn("essa geracao nao publica trafego de producao", AGENTS)
        self.assertIn("Agentes nunca executam `vercel promote` sem autorizacao humana explicita", AGENTS)
        self.assertLess(PROFILE.index("PR para staging"), PROFILE.index("PR de release staging -> main"))

    def test_current_state_identifies_the_governance_transition(self):
        self.assertIn("`ENG-ENV-01` estabelece", CURRENT_STATE)
        self.assertIn("elite-system-production", CURRENT_STATE)
        self.assertIn("oncssgiocivoknwwcuuz", CURRENT_STATE)
        self.assertIn("foi inicializado com 151\n  migrations", CURRENT_STATE)
        self.assertIn("ledger mais recente a `0152`", CURRENT_STATE)
        self.assertIn("dpl_CzQhTtzoNtGeQdpHwL8gJYM91DSh", CURRENT_STATE)
        self.assertIn("nenhuma promocao Vercel ocorreu", CURRENT_STATE)
        self.assertIn("nao ha usuario humano\n  em producao", CURRENT_STATE)
        self.assertIn("DEC-004 esta autorizada", CURRENT_STATE)
        self.assertIn("Production Domains desabilitado", CURRENT_STATE)
        self.assertIn("deployment staged mais\n  promocao explicita", CURRENT_STATE)
        self.assertIn("configuracao Auth de producao", CURRENT_STATE)
        self.assertIn("pipeline governado de release de producao", ADR)


if __name__ == "__main__":
    unittest.main()
