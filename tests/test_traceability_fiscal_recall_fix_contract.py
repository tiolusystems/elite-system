from __future__ import annotations

from pathlib import Path
import unittest


ROOT = Path(__file__).resolve().parents[1]
MIGRATION = ROOT / "supabase" / "migrations" / "0113_fix_traceability_fiscal_direction_and_recall.sql"
SMOKE = ROOT / "tests" / "sql" / "production_end_to_end_chain.sql"


class TraceabilityFiscalRecallFixContractTests(unittest.TestCase):
    def test_external_fiscal_reference_is_a_document_destination(self) -> None:
        text = MIGRATION.read_text(encoding="utf-8")

        self.assertIn(
            "case when nota.romaneio_id is null then 'PEDIDO' else 'ROMANEIO' end",
            text,
        )
        self.assertIn(
            "'REFERENCIA_FISCAL', nota.id, concat_ws('-', nota.numero",
            text,
        )
        self.assertNotIn(
            "'REFERENCIA_FISCAL', nota.id, concat_ws('-', nota.numero, nullif(nota.serie, '')),\n"
            "  case when nota.romaneio_id is null then 'PEDIDO' else 'ROMANEIO' end",
            text,
        )

    def test_recall_appends_one_node_to_the_recursive_path(self) -> None:
        text = MIGRATION.read_text(encoding="utf-8")

        self.assertIn("array_append(", text)
        self.assertIn(
            "edge.destino_tipo || ':' || edge.destino_id::text",
            text,
        )
        self.assertNotIn(
            "descendentes.caminho || edge.destino_tipo || ':' || edge.destino_id",
            text,
        )

    def test_permissions_remain_minimal(self) -> None:
        text = MIGRATION.read_text(encoding="utf-8")

        self.assertIn(
            "revoke all on public.rel_rastreabilidade_arestas from public, anon, authenticated;",
            text,
        )
        self.assertIn(
            "revoke all on function public.simular_rel_recolhimento(text, bigint)",
            text,
        )
        self.assertIn(
            "grant execute on function public.simular_rel_recolhimento(text, bigint)",
            text,
        )
        self.assertNotIn("grant all", text.lower())

    def test_integrated_smoke_covers_fiscal_lookup_and_recall(self) -> None:
        text = SMOKE.read_text(encoding="utf-8")

        for contract in (
            "traceability did not reach external fiscal reference",
            "external fiscal reference did not trace back to PA",
            "recall simulation did not return the active shipment",
        ):
            self.assertIn(contract, text)


if __name__ == "__main__":
    unittest.main()
