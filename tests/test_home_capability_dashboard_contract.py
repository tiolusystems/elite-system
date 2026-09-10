from pathlib import Path
import unittest


ROOT = Path(__file__).resolve().parents[1]
HOME = (ROOT / "apps" / "web" / "app" / "page.tsx").read_text(encoding="utf-8")


class HomeCapabilityDashboardContractTests(unittest.TestCase):
    def component(self, name: str, next_name: str) -> str:
        return HOME[HOME.index(f"function {name}"):HOME.index(f"function {next_name}")]

    def test_commercial_home_contains_only_capability_gated_commercial_shortcuts(self) -> None:
        commercial_home = self.component("CommercialHome", "CommercialShortcut")

        for expected in [
            "Meus pedidos", "Meu Kanban", "Novo pedido", 'href="/pedidos?nova=1"',
            'href="/pedidos"', 'href="/kanban"', 'href="/cadastros"',
        ]:
            self.assertIn(expected, commercial_home)

        for forbidden in [
            "getPcpDashboard", "getRomaneioDashboard", "getImportacaoXmlDashboard",
            "getSecurityDashboard", "getModuleRuntimeDashboard", "getReportsDashboard",
            "Centro de controle", "Trilha de auditoria", "Modulos ativos", "XML MP",
            "Producao", "Romaneio", "Seguranca",
        ]:
            self.assertNotIn(forbidden, commercial_home)

    def test_operational_getters_are_called_only_after_capability_access_is_confirmed(self) -> None:
        dashboard_loader = self.component("getOperationalDashboard", "CommercialHome")
        for pathname, getter in [
            ("/cadastros", "getMasterDataDashboard"), ("/pedidos", "getOrdersDashboard"),
            ("/relatorios", "getReportsDashboard"), ("/importacao-xml", "getImportacaoXmlDashboard"),
            ("/kanban", "getKanbanDashboard"), ("/producao", "getPcpDashboard"),
            ("/romaneios", "getRomaneioDashboard"), ("/seguranca", "getSecurityDashboard"),
            ("/modulos", "getModuleRuntimeDashboard"),
        ]:
            self.assertIn(f'navigationAccess["{pathname}"] ? {getter}() : Promise.resolve(null)', dashboard_loader)

    def test_capability_lookup_fails_closed_to_the_commercial_or_limited_home(self) -> None:
        self.assertIn("const navigationAccess = auth.isAuthenticated ? await getNavigationAccess() : {};", HOME)
        self.assertIn("if (!hasOperationalHomeAccess(navigationAccess))", HOME)
        self.assertIn("? <CommercialHome auth={auth} navigationAccess={navigationAccess} />", HOME)
        self.assertIn(": <LimitedHome />", HOME)


if __name__ == "__main__":
    unittest.main()
