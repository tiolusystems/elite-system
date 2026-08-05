from pathlib import Path
import unittest


ROOT = Path(__file__).resolve().parents[1]
PAGE = ROOT / "apps/web/app/romaneios/page.tsx"
DATA = ROOT / "apps/web/lib/romaneios.ts"
PREPARATION = ROOT / "apps/web/app/romaneios/romaneio-preparation.tsx"
ACTIONS = ROOT / "apps/web/app/romaneios/actions.ts"
MANUALS = ROOT / "apps/web/lib/manuals.ts"
STYLES = ROOT / "apps/web/app/globals.css"
SEARCH_MIGRATION = ROOT / "supabase/migrations/0119_corporate_search_and_romaneio_filters.sql"


class RomaneioWorkbenchUxContractTests(unittest.TestCase):
    @classmethod
    def setUpClass(cls) -> None:
        cls.page = PAGE.read_text(encoding="utf-8")
        cls.data = DATA.read_text(encoding="utf-8")
        cls.preparation = PREPARATION.read_text(encoding="utf-8")
        cls.actions = ACTIONS.read_text(encoding="utf-8")
        cls.manuals = MANUALS.read_text(encoding="utf-8")
        cls.styles = STYLES.read_text(encoding="utf-8")

    def test_workbench_starts_from_orders_and_does_not_render_global_stock(self) -> None:
        self.assertIn("Pedidos com saldo", self.page)
        self.assertIn("Escolha o pedido", self.preparation)
        self.assertIn("O estoque só será consultado para esse produto", self.preparation)
        self.assertNotIn("Lotes PA disponiveis", self.page)
        self.assertNotIn("Livre para novo romaneio", self.page)
        self.assertNotIn("legacy-romaneio-ui", self.page)
        self.assertNotIn("legacy-romaneio-ui", self.styles)

    def test_planning_and_consultation_are_distinct_modes(self) -> None:
        self.assertIn('const mode = singleValue(params.modo) === "consulta"', self.page)
        self.assertIn('mode === "planejar"', self.page)
        self.assertIn("RomaneioPreparation", self.page)
        self.assertIn("RomaneioConsultationTable", self.page)
        self.assertIn("romaneio-workflow-tabs", self.page)
        self.assertIn("Consultar Romaneios", self.page)

    def test_consultation_is_compact_and_hides_technical_ids(self) -> None:
        self.assertIn("DataTable", self.page)
        self.assertIn("PrimarySecondaryCell", self.page)
        self.assertIn("StatusBadge", self.page)
        self.assertIn("Abra somente a situação e o Romaneio", self.page)
        self.assertNotIn("item {item.id}", self.page)
        self.assertNotIn("id {lot.id}", self.page)
        self.assertIn("Lote ainda não reservado", self.page)

    def test_actions_return_to_the_operational_context(self) -> None:
        self.assertIn("result=romaneio_created#reservar-lote", self.actions)
        self.assertIn("result=lot_reserved#reservar-lote", self.actions)
        self.assertIn("modo=consulta&result=logistics_assigned#romaneios", self.actions)
        self.assertIn("modo=consulta&result=romaneio_confirmed#romaneios", self.actions)

    def test_manual_separates_fiscal_reference_from_physical_issue(self) -> None:
        self.assertIn("consultar não grava", self.manuals)
        self.assertIn("Grave o rascunho do Romaneio", self.manuals)
        self.assertIn("Registrar a referência fiscal não baixa estoque", self.manuals)
        self.assertIn("Confirme o Romaneio para registrar a saída física", self.manuals)

    def test_historical_reservations_and_movements_have_pt_br_labels(self) -> None:
        self.assertIn('estornada: "Estornada"', self.page)
        self.assertIn('baixa: "Baixa física"', self.page)
        self.assertIn('estorno: "Estorno da baixa"', self.page)

    def test_consultation_is_server_paginated_and_scopes_relations_to_the_page(self) -> None:
        self.assertIn('name="busca"', self.page)
        self.assertIn("params.pagina", self.page)
        self.assertIn('rpc("buscar_exp_romaneios_paginada"', self.data)
        self.assertIn("p_offset: from", self.data)
        self.assertIn('.in("romaneio_id", selectedRomaneioFilter)', self.data)
        self.assertNotIn('.from("exp_romaneios")\n        .select(\n          "id,codigo_romaneio', self.data.split('const [', 1)[1])

    def test_paginated_search_rpc_is_read_only_and_not_public(self) -> None:
        migration = SEARCH_MIGRATION.read_text(encoding="utf-8")
        self.assertIn("security invoker", migration.lower())
        self.assertIn("revoke all on function public.buscar_exp_romaneios_paginada", migration.lower())
        self.assertIn("from public.exp_romaneios", migration.lower())
        self.assertNotIn("insert into", migration.lower())
        self.assertNotIn("update public.", migration.lower())


if __name__ == "__main__":
    unittest.main()
