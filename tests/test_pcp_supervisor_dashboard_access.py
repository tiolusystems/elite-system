from __future__ import annotations

import unittest
from pathlib import Path


ROOT = Path(__file__).resolve().parents[1]
MIGRATION = ROOT / "supabase" / "migrations" / "0107_pcp_supervisor_dashboard_access.sql"
PAGE = ROOT / "apps" / "web" / "app" / "producao" / "page.tsx"
SHELL = ROOT / "apps" / "web" / "app" / "producao" / "production-shell.tsx"
PCP = ROOT / "apps" / "web" / "lib" / "pcp.ts"
MANUAL = ROOT / "apps" / "web" / "app" / "producao" / "manual" / "page.tsx"


class PcpSupervisorDashboardAccessTests(unittest.TestCase):
    def test_atomic_permission_is_read_only_and_blocked_by_default(self) -> None:
        sql = MIGRATION.read_text(encoding="utf-8")

        self.assertIn("'pcp.dashboard.view'", sql)
        self.assertIn("'pcp'", sql)
        self.assertIn("'read'", sql)
        self.assertRegex(
            sql,
            r"'Consultar painel supervisor da produção',\s*false,",
        )
        self.assertNotIn("role =", sql)
        self.assertNotIn("tipo_comercial", sql)

    def test_database_dashboard_is_guarded_and_not_public(self) -> None:
        sql = MIGRATION.read_text(encoding="utf-8")

        self.assertIn("security definer", sql.lower())
        self.assertIn("set search_path = public", sql.lower())
        self.assertIn(
            "require_current_user_permission('pcp.dashboard.view')",
            sql,
        )
        self.assertIn(
            "revoke all on function public.get_pcp_supervisor_dashboard() from public",
            sql,
        )
        self.assertIn(
            "revoke all on function public.get_pcp_supervisor_dashboard() from anon",
            sql,
        )
        self.assertIn(
            "grant execute on function public.get_pcp_supervisor_dashboard() to authenticated",
            sql,
        )

    def test_direct_route_denies_before_dashboard_query(self) -> None:
        page = PAGE.read_text(encoding="utf-8")

        permission_position = page.index(
            "const canViewDashboard = await canCurrentUserViewPcpDashboard()"
        )
        redirect_position = page.index('redirect("/producao/ordens")')
        query_position = page.index(
            "const dashboard = await getPcpSupervisorDashboard()"
        )
        self.assertLess(permission_position, redirect_position)
        self.assertLess(redirect_position, query_position)
        self.assertNotIn("getPcpDashboard", page)
        self.assertIn('dynamic = "force-dynamic"', page)

    def test_shell_omits_overview_without_atomic_permission(self) -> None:
        shell = SHELL.read_text(encoding="utf-8")

        self.assertIn("canCurrentUserViewPcpDashboard", shell)
        self.assertIn('item.key !== "overview"', shell)
        self.assertNotIn("role ===", shell)
        self.assertNotIn("tipo_comercial", shell)

    def test_frontend_uses_only_governed_dashboard_rpc(self) -> None:
        pcp = PCP.read_text(encoding="utf-8")

        self.assertIn('p_action_key: "pcp.dashboard.view"', pcp)
        self.assertIn('supabase.rpc("get_pcp_supervisor_dashboard")', pcp)
        self.assertNotIn(
            '.from("pcp_ordens_producao")',
            pcp[
                pcp.index("export async function getPcpSupervisorDashboard"):
                pcp.index("export async function getPcpDashboard")
            ],
        )

    def test_didactic_flow_lives_only_in_manual(self) -> None:
        page = PAGE.read_text(encoding="utf-8")
        manual = MANUAL.read_text(encoding="utf-8")

        self.assertNotIn("8 etapas", page)
        self.assertNotIn("StageCard", page)
        self.assertIn('title="Transformações e reprocessamentos"', manual)
        self.assertIn("A transformação é uma OP governada, não um ajuste manual de saldo.", manual)
        self.assertIn('title="Visão geral"', manual)
        self.assertIn("Mostrar para a supervisão onde existem pendências.", manual)


if __name__ == "__main__":
    unittest.main()
