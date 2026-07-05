from __future__ import annotations

import unittest
from pathlib import Path


REPO_ROOT = Path(__file__).resolve().parents[1]
MIGRATION_0023 = REPO_ROOT / "supabase" / "migrations" / "0023_importacao_xml_mp_lot_contract.sql"


class ImportacaoXmlMpLotContractTests(unittest.TestCase):
    def test_0023_documents_romaneio_reservation_lock_invariant(self) -> None:
        text = MIGRATION_0023.read_text(encoding="utf-8")

        self.assertIn("comment on function public.confirmar_exp_romaneio(bigint, text)", text)
        self.assertIn("PA reservations for a romaneio item must only be changed", text)
        self.assertIn("lock the parent exp_romaneio_itens row first", text)

    def test_0023_generate_mp_lot_uses_importacao_audit_contract(self) -> None:
        text = MIGRATION_0023.read_text(encoding="utf-8")

        self.assertIn("create or replace function public.gerar_lote_mp_from_imp_nfe_item", text)
        self.assertIn("v_permission_context := public.begin_audited_rpc(", text)
        self.assertIn("'importacao.nfe_xml.generate_mp_lot'", text)
        self.assertIn("'importacao_xml'", text)
        self.assertIn("'imp_nfe_xml_itens'", text)
        self.assertIn("'movement_event'", text)
        self.assertIn("'familia', 'MP'", text)
        self.assertIn("'event', 'entry'", text)
        self.assertIn("'origem', 'nfe_xml'", text)
        self.assertIn("'stock_action_key', 'estoque.mp.lots.create'", text)

    def test_0023_generate_mp_lot_keeps_stock_entry_rpc_and_composite_snapshots(self) -> None:
        text = MIGRATION_0023.read_text(encoding="utf-8")

        self.assertIn("v_lote_id := public.create_est_lote_mp(", text)
        self.assertIn("'entrada_compra'", text)
        self.assertIn("'nfe'", text)
        self.assertIn("'item'", text)
        self.assertIn("'resolucoes'", text)
        self.assertIn("'lotes_mp'", text)
        self.assertIn("'item_lote_mp'", text)
        self.assertIn("'lote_mp'", text)
        self.assertIn("'mp_saldo'", text)
        self.assertIn("left join public.est_lotes_mp_saldos saldo", text)
        self.assertIn("perform public.log_audited_rpc_change(", text)
        self.assertIn("'importacao.nfe_xml_item_lote_mp_generated'", text)
        self.assertIn("'estoque_action_key', 'estoque.mp.lots.create'", text)
        self.assertNotIn("perform public.log_action(", text)

    def test_0023_generate_mp_lot_grants_only_authenticated_execute(self) -> None:
        text = MIGRATION_0023.read_text(encoding="utf-8")

        self.assertIn("revoke all on function public.gerar_lote_mp_from_imp_nfe_item(bigint, text, text) from public", text)
        self.assertIn("grant execute on function public.gerar_lote_mp_from_imp_nfe_item(bigint, text, text) to authenticated", text)


if __name__ == "__main__":
    unittest.main()
