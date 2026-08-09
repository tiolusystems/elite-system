from __future__ import annotations

from pathlib import Path
import re
import unittest


ROOT = Path(__file__).resolve().parents[1]
AGENT_CONTRACT = ROOT / "AGENTS.md"
ARCHITECTURE_MAP = ROOT / "docs" / "arquitetura" / "ARQUITETURA_GERAL.md"
EXECUTIVE_MAP = ROOT / "docs" / "00_MAPA_EXECUTIVO.md"
CURRENT_STATUS = ROOT / "docs" / "01_ESTADO_ATUAL.md"
PENDING_DECISIONS = ROOT / "docs" / "02_DECISOES_PENDENTES.md"
SYSTEM_MAP = ROOT / "apps" / "web" / "lib" / "system-map.ts"
MODULES_LIB = ROOT / "apps" / "web" / "lib" / "modules.ts"
MODULES_PAGE = ROOT / "apps" / "web" / "app" / "modulos" / "page.tsx"
IMPLEMENTATION_MAP = ROOT / "docs" / "implantacao" / "00_MAPA_IMPLANTACAO_MODULOS.md"
HOME_PAGE = ROOT / "apps" / "web" / "app" / "page.tsx"
MODULE_MIGRATION = ROOT / "supabase" / "migrations" / "0041_module_rollout_runtime.sql"

EXPECTED_MODULE_KEYS = {
    "core",
    "seguranca",
    "cadastros",
    "pedidos",
    "estoque",
    "pcp",
    "expedicao",
    "importacao",
    "faturamento",
    "financeiro",
    "metas",
    "relatorios",
    "auditoria",
}


class ArchitectureNavigationContractTest(unittest.TestCase):
    def test_agent_contract_starts_from_the_authoritative_map(self) -> None:
        contract = AGENT_CONTRACT.read_text(encoding="utf-8")

        self.assertIn("docs/00_MAPA_EXECUTIVO.md", contract)
        self.assertIn("docs/01_ESTADO_ATUAL.md", contract)
        self.assertIn("docs/02_DECISOES_PENDENTES.md", contract)
        self.assertIn("docs/arquitetura/ARQUITETURA_GERAL.md", contract)
        self.assertIn("Nao refaca inventario geral", contract)
        self.assertIn("Nao repita comando", contract)
        self.assertIn("Validacao proporcional", contract)
        self.assertIn("Git recebe somente codigo e documentacao", contract)
        self.assertIn("Ao concluir cada tarefa", contract)
        self.assertIn("autorizacao previa do usuario", contract)

    def test_operational_documents_define_status_and_next_task(self) -> None:
        executive = EXECUTIVE_MAP.read_text(encoding="utf-8")
        status = CURRENT_STATUS.read_text(encoding="utf-8")
        decisions = PENDING_DECISIONS.read_text(encoding="utf-8")

        self.assertIn("## Classificacao da tarefa", executive)
        self.assertIn("## Gate de arquitetura", executive)
        self.assertIn("## Tarefa em execucao", status)
        self.assertIn("## Validacao vigente", status)
        self.assertIn("## Proxima tarefa", status)
        self.assertIn("OPS-GATE-01", status)
        self.assertIn("DEC-002", decisions)
        self.assertIn("DEC-012", decisions)
        self.assertNotIn("| implementada |", decisions)
        self.assertIn("decisoes ainda dependentes de Luciano", decisions)

    def test_human_map_covers_every_runtime_module(self) -> None:
        document = ARCHITECTURE_MAP.read_text(encoding="utf-8")
        catalog = document.split("## Catalogo de modulos", 1)[1].split("## Grafo de dependencias", 1)[0]
        documented = set(re.findall(r"^\| `([a-z_]+)` \|", catalog, re.MULTILINE))

        self.assertEqual(documented, EXPECTED_MODULE_KEYS)
        self.assertGreaterEqual(document.count("```mermaid"), 5)
        self.assertIn("Gates ainda necessarios para producao profissional", document)
        self.assertIn("Localizador rapido por tipo de mudanca", document)

    def test_executable_catalog_and_database_catalog_use_the_same_keys(self) -> None:
        system_map = SYSTEM_MAP.read_text(encoding="utf-8")
        migration = MODULE_MIGRATION.read_text(encoding="utf-8")

        key_list_match = re.search(
            r"SYSTEM_MODULE_KEYS\s*=\s*\[(.*?)\]\s*as const",
            system_map,
            re.DOTALL,
        )
        self.assertIsNotNone(key_list_match)
        executable_keys = set(re.findall(r'"([a-z_]+)"', key_list_match.group(1)))

        insert_match = re.search(
            r"insert into public\.sys_modules.*?values(.*?)on conflict \(module_key\)",
            migration,
            re.DOTALL | re.IGNORECASE,
        )
        self.assertIsNotNone(insert_match)
        database_keys = set(re.findall(r"\('([a-z_]+)'\s*,", insert_match.group(1)))

        self.assertEqual(executable_keys, EXPECTED_MODULE_KEYS)
        self.assertEqual(database_keys, EXPECTED_MODULE_KEYS)

    def test_runtime_fallback_and_visual_page_consume_the_catalog(self) -> None:
        modules_lib = MODULES_LIB.read_text(encoding="utf-8")
        page = MODULES_PAGE.read_text(encoding="utf-8")

        self.assertIn("SYSTEM_MODULE_CATALOG.map", modules_lib)
        self.assertIn("SYSTEM_MAP_LANES.map", page)
        self.assertIn("SYSTEM_FLOWS.map", page)
        self.assertIn("moduleMaturityPercent", page)
        self.assertIn('id="mapa"', page)

    def test_visual_roadmap_translates_the_authoritative_runtime(self) -> None:
        page = MODULES_PAGE.read_text(encoding="utf-8")
        system_map = SYSTEM_MAP.read_text(encoding="utf-8")
        implementation = IMPLEMENTATION_MAP.read_text(encoding="utf-8")

        self.assertIn("SYSTEM_DEPLOYMENT_GATES", system_map)
        self.assertIn("SYSTEM_DEPLOYMENT_GATES.map", page)
        self.assertIn("deploymentGateState", page)
        self.assertIn('id="implantacao"', page)
        self.assertIn("Proxima validacao:", page)
        self.assertIn("PostgreSQL", implementation)
        self.assertIn("nao cria uma segunda fonte de status", implementation)

    def test_home_progress_uses_runtime_maturity_not_invented_percentages(self) -> None:
        page = HOME_PAGE.read_text(encoding="utf-8")

        self.assertIn("moduleMaturityPercent", page)
        self.assertNotRegex(page, r'width:\s*"\d+%"')


if __name__ == "__main__":
    unittest.main()
