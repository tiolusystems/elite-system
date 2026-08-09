from __future__ import annotations

from pathlib import Path
import unittest


ROOT = Path(__file__).resolve().parents[1]
MIGRATION = ROOT / "supabase" / "migrations" / "0068_govern_products_packaging_per_liter.sql"
ADR = ROOT / "docs" / "decisoes-arquiteturais" / "ADR-013-base-unica-por-litro-custos-garantias-lote.md"
DECISIONS = ROOT / "docs" / "historico" / "02_DECISOES_ATE_2026-07-28.md"
MANUAL_INDEX = ROOT / "docs" / "manuais" / "README.md"
OPERATING_MANUAL = ROOT / "docs" / "manuais" / "cadastros" / "PRODUTOS_APRESENTACOES_EMBALAGENS.md"


class ProductsPackagingPerLiterContractTests(unittest.TestCase):
    def test_architecture_uses_one_liter_basis_and_keeps_0068_bounded(self) -> None:
        text = ADR.read_text(encoding="utf-8")
        for contract in (
            "produzir `1 L`",
            "`kg/L produzido`",
            "`L/L produzido`",
            "`UN/L produzido`",
            "Formula nunca referencia lote",
            "Garantia ausente nao equivale a zero",
            "A 0068 implementa somente Produtos",
            "Nao modifica formula, OP",
        ):
            self.assertIn(contract, text)

    def test_dec_013_is_implemented(self) -> None:
        text = DECISIONS.read_text(encoding="utf-8")
        row = next(line for line in text.splitlines() if line.startswith("| `DEC-013`"))
        self.assertTrue(row.rstrip().endswith("| implementada |"))
        self.assertIn("Formula, FIFO, custos e garantias por lote foram implementados", text)

    def test_migration_adds_normalized_un_l_without_legacy_backfill(self) -> None:
        text = MIGRATION.read_text(encoding="utf-8")
        self.assertIn("unidades_embalagem_por_litro", text)
        self.assertIn("quantidade_un_l", text)
        self.assertIn("1 / v_capacity", text)
        self.assertIn("'normalized_basis', 'UN/L'", text)
        self.assertNotIn("update public.cad_embalagem_versoes\n+     set unidades_embalagem_por_litro", text)
        self.assertNotIn("kg/kg", text.lower())

    def test_every_governed_write_uses_audited_rpc_contract(self) -> None:
        text = MIGRATION.read_text(encoding="utf-8")
        functions = (
            "update_cad_produto_identity",
            "update_cad_produto_technical",
            "update_cad_produto_regulatory",
            "set_cad_produto_active_state",
            "update_cad_embalagem_identity",
            "update_cad_embalagem_physical",
            "set_cad_embalagem_active_state",
            "set_cad_apresentacao_active_state",
            "create_cad_embalagem_versao_un_l",
            "add_cad_embalagem_componente_un_l",
            "remove_cad_embalagem_componente",
            "review_cad_embalagem_versao",
            "activate_cad_embalagem_versao",
        )
        for index, function in enumerate(functions):
            start = text.index(f"create or replace function public.{function}")
            following = [text.find("create or replace function public.", start + 1)]
            end = min((position for position in following if position >= 0), default=len(text))
            body = text[start:end]
            self.assertIn("public.begin_audited_rpc", body, function)
            self.assertIn("public.log_audited_rpc_change", body, function)

    def test_direct_writes_and_anonymous_execution_remain_denied(self) -> None:
        text = MIGRATION.read_text(encoding="utf-8")
        for table in (
            "cad_produtos_base",
            "cad_embalagens",
            "cad_produto_embalagens",
            "cad_embalagem_versoes",
            "cad_embalagem_componentes",
            "cad_embalagem_versao_ativacoes",
            "cad_embalagem_versao_revisoes",
            "cad_embalagem_componente_eventos",
        ):
            self.assertIn(
                f"revoke insert, update, delete, truncate on public.{table} from public, anon, authenticated;",
                text,
            )
        self.assertNotIn("grant execute on function public.", "\n".join(
            line for line in text.splitlines() if line.rstrip().endswith("to anon;")
        ))

    def test_codes_are_normalized_and_package_unit_is_governed(self) -> None:
        text = MIGRATION.read_text(encoding="utf-8")
        self.assertIn("idx_cad_produtos_codigo_norm", text)
        self.assertIn("idx_cad_produto_embalagens_codigo_norm", text)
        self.assertIn("upper(v_unit.codigo) <> 'UN'", text)
        self.assertIn("active UN unit not found", text)

    def test_review_and_component_removal_are_append_only_events(self) -> None:
        text = MIGRATION.read_text(encoding="utf-8")
        self.assertIn("create table public.cad_embalagem_versao_revisoes", text)
        self.assertIn("create table public.cad_embalagem_componente_eventos", text)
        self.assertIn("trg_cad_embalagem_versao_revisoes_append_only", text)
        self.assertIn("trg_cad_embalagem_componente_eventos_append_only", text)
        self.assertNotIn("update public.cad_embalagem_versoes set review_status", text)
        self.assertNotIn("update public.cad_embalagem_componentes set status", text)

    def test_current_flow_has_an_operating_manual_without_promising_future_features(self) -> None:
        index = MANUAL_INDEX.read_text(encoding="utf-8")
        manual = OPERATING_MANUAL.read_text(encoding="utf-8")
        self.assertIn("PRODUTOS_APRESENTACOES_EMBALAGENS.md", index)
        self.assertIn("Para vender o mesmo produto em outra", manual)
        self.assertIn("crie outra apresentacao; nao duplique o produto", manual)
        self.assertIn("O que nao pertence a esta entrega", manual)
        self.assertIn("integracao com `gov.br`", manual)


if __name__ == "__main__":
    unittest.main()
