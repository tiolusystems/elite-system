from __future__ import annotations

from pathlib import Path
import re
import unittest


ROOT = Path(__file__).resolve().parents[1]
AGENT_CONTRACT = ROOT / "AGENTS.md"
ARCHITECTURE_MAP = ROOT / "docs" / "arquitetura" / "ARQUITETURA_GERAL.md"
SYSTEM_MAP = ROOT / "apps" / "web" / "lib" / "system-map.ts"
MODULES_LIB = ROOT / "apps" / "web" / "lib" / "modules.ts"
MODULES_PAGE = ROOT / "apps" / "web" / "app" / "modulos" / "page.tsx"
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

        self.assertIn("docs/arquitetura/ARQUITETURA_GERAL.md", contract)
        self.assertIn("Nao refaca inventario geral", contract)
        self.assertIn("Nao repita comando", contract)
        self.assertIn("Validacao proporcional", contract)
        self.assertIn("Git recebe somente codigo e documentacao", contract)

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

    def test_home_progress_uses_runtime_maturity_not_invented_percentages(self) -> None:
        page = HOME_PAGE.read_text(encoding="utf-8")

        self.assertIn("moduleMaturityPercent", page)
        self.assertNotRegex(page, r'width:\s*"\d+%"')


if __name__ == "__main__":
    unittest.main()
