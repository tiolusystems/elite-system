from pathlib import Path


ROOT = Path(__file__).resolve().parents[1]
SQL = (ROOT / "supabase/migrations/0129_govern_commercial_pricing_units.sql").read_text(encoding="utf-8")


def test_generic_unit_contract_is_additive_and_preserves_liter_compatibility() -> None:
    assert "add column if not exists unidade_precificacao_id" in SQL
    assert "quantidade_unidade_precificacao_por_apresentacao" in SQL
    assert "valor_centavos_por_unidade_precificacao" in SQL
    assert "alter column valor_centavos_por_litro drop not null" in SQL
    assert "preco generico em litro exige espelho legado identico" in SQL
    assert "normalize_com_lista_preco_item_unidade_comercial" in SQL
    assert "item legado exige capacidade positiva da apresentacao para congelar a unidade comercial L" in SQL
    assert "set valor_centavos_por_unidade_precificacao = price.valor_centavos_por_litro" in SQL
    assert "'valor_centavos_por_litro', price.valor_centavos_por_litro" in SQL
    assert "_ord_0129_versoes_normalizadas" in SQL
    assert "set conteudo_hash = md5(public.com_lista_preco_versao_documento(publication.versao_id)::text)" in SQL
    assert "trg_com_lista_preco_publicacoes_append_only" in SQL


def test_generic_resolver_and_snapshot_are_governed() -> None:
    assert "resolver_com_referencia_comercial_unidade" in SQL
    assert "pedidos.price_reference.resolve" in SQL
    assert "snapshot comercial exige unidade, fator e preco genericos congelados" in SQL
    assert "revoke all on function public.resolver_com_referencia_comercial_unidade" in SQL
    assert "referencia comercial historica sem unidade e fator genericos congelados" in SQL
    resolver_body = SQL.split("create or replace function public.resolver_com_referencia_comercial_unidade", 1)[1]
    assert "embalagem.volume_litros" not in resolver_body.split("create or replace function public.resolver_com_referencia_comercial", 1)[0]


def test_xlsx_remains_explicitly_liter_based() -> None:
    assert "importacao R$/L exige capacidade positiva da apresentacao" in SQL
    assert "'unidade_comercial', 'L'" in SQL


def test_canonical_draft_normalizes_legacy_payload_without_creating_legacy_only_items() -> None:
    draft_body = SQL.split("create or replace function public.replace_com_lista_preco_rascunho_idempotente", 1)[1]
    assert "select unidade.id, embalagem.volume_litros" in draft_body
    assert "values (p_versao_id, v_produto_embalagem_id, v_unidade_id, v_fator, v_actor)" in draft_body
    assert "case when lower(v_codigo_unidade) = 'l' then v_valor else null end, v_valor" in draft_body
    assert "jsonb_array_length(v_item->'precos') = 0 or exists" in draft_body
    assert "or price.value ? 'valor_centavos_por_unidade_precificacao'" in draft_body
