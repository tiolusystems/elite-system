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

    def test_agent_contract_requires_the_canonical_path(self):
        self.assertIn("PRs ordinarias devem ter `staging` como destino.", AGENTS)
        self.assertIn("Preview de deploy nao e ambiente canonico", AGENTS)
        self.assertLess(PROFILE.index("PR para staging"), PROFILE.index("PR de release staging -> main"))

    def test_current_state_identifies_the_governance_transition(self):
        self.assertIn("`ENG-ENV-01` esta em execucao", CURRENT_STATE)
        self.assertIn("banco de producao ainda nao identificado", CURRENT_STATE)


if __name__ == "__main__":
    unittest.main()
