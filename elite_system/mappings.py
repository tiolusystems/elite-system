from __future__ import annotations

from datetime import date, timedelta
import math
import re
import unicodedata


NORMALIZED_TABLES = {
    "CADASTRO_MATERIA_PRIMA",
    "RELACAO_PRODUTOS",
    "CLIENTES",
    "Tabela153241",
    "Tabela153",
    "GESTÃO_PEDIDOS",
    "ENTRADAS_MP",
    "PRODUCAO_LOTES",
    "SAÍDAS_MP",
    "SAIDAS_PA",
}


ENTITY_BY_TABLE = {
    "CADASTRO_MATERIA_PRIMA": ("materias_primas", "nome"),
    "RELACAO_PRODUTOS": ("produtos", "nome"),
    "CLIENTES": ("clientes", "nome"),
    "Tabela153241": ("vendedores", "nome"),
    "Tabela153": ("veiculos", "veiculo"),
    "GESTÃO_PEDIDOS": ("pedidos_linhas", "id_pedido"),
    "ENTRADAS_MP": ("entradas_mp", "materia_prima"),
    "PRODUCAO_LOTES": ("lotes_producao", "lote"),
    "SAÍDAS_MP": ("saidas_mp", "lote_op"),
    "SAIDAS_PA": ("saidas_pa", "id_pedido"),
}


def normalize_table_row(table_name: str, row: dict[str, object]) -> tuple[str, dict[str, object]] | None:
    if table_name == "CADASTRO_MATERIA_PRIMA":
        data = {
            "nome": text(row.get("MATÉRIA PRIMA")),
            "ibama": text(row.get("IBAMA")),
            "sku": text(row.get("id_sku_mp")),
            "tipo": text(row.get("TIPO")),
            "estoque_minimo": number(row.get("ESTOQUE MÍNIMO")),
            "valor_estoque_minimo": number(row.get("R$ Estoque Mínimo")),
            "custo_unitario": number(row.get("R$/Und")),
            "densidade": number(row.get("Densidade")),
            "codigo_ads": text(row.get("Código ADS")),
            "status": text(row.get("Ativo/Inativo")),
            "ncm": text(row.get("NCM")),
            "unidade_adotada": text(row.get("UNIDADE ADOTADA")),
        }
        return ("materias_primas", data) if data["nome"] else None

    if table_name == "RELACAO_PRODUTOS":
        data = {
            "grupo": text(row.get("Grupo")),
            "nome": text(row.get("RELAÇÃO DE PRODUTOS")),
            "densidade_kg_l": number(row.get("DENSIDADE Kg/L")),
            "custo_mp": number(row.get("CUSTO MP")),
            "reg_mapa": text(row.get("Reg MAPA")),
            "ph": text(row.get("pH")),
            "ibama": text(row.get("IBAMA")),
            "ads": text(row.get("ADS")),
            "ncm": text(row.get("NCM")),
        }
        return ("produtos", data) if data["nome"] else None

    if table_name == "CLIENTES":
        data = {
            "nome": text(row.get("CLIENTES")),
            "codigo": text(row.get("CÓDIGO")),
            "vendedor_cadastrou": text(row.get("Vendedor que Cadastrou")),
            "vendedor_atende": text(row.get("Vendedor que Atende")),
            "status": text(row.get("A/I")),
            "contato": text(row.get("CONTATO")),
            "cidade": text(row.get("CIDADE")),
            "uf": text(row.get("UF")),
            "valor_total_compras": number(row.get("VALOR TOTAL DE COMPRAS")),
        }
        return ("clientes", data) if data["nome"] else None

    if table_name == "Tabela153241":
        data = {
            "nome": text(row.get("FUNCIONÁRIO")),
            "funcao": text(row.get("Função")),
            "status": text(row.get("Ativo/Inativo")),
            "admissao": excel_date(row.get("Admissão")),
            "demissao": excel_date(row.get("Demissão")),
            "vendas": number(row.get("Vendas")),
            "bonificacoes": number(row.get("Bonificações")),
        }
        return ("vendedores", data) if data["nome"] else None

    if table_name == "Tabela153":
        data = {"veiculo": text(row.get("VEÍCULO")), "placa": text(row.get("PLACA"))}
        return ("veiculos", data) if data["veiculo"] else None

    if table_name == "GESTÃO_PEDIDOS":
        data = {
            "data_pedido": excel_date(row.get("DATA PEDIDO")),
            "data_entrega": excel_date(row.get("DATA DA ENTREGA")),
            "numero_pedido": text(row.get("Nº PEDIDO")),
            "id_pedido": text(row.get("ID_pedido")),
            "nf": text(row.get("NF")),
            "status_recebimento": text(row.get("STATUS RECEBIMENTO")),
            "status_entrega": text(row.get("STATUS ENTREGA")),
            "tipo": text(row.get("TIPO")),
            "cliente": text(row.get("CLIENTE")),
            "produto": text(row.get("PRODUTO")),
            "embalagem": text(row.get("EMB.")),
            "entregar_litros": number(row.get("ENTREGAR LITROS")),
            "litros": number(row.get("LITROS")),
            "entregue_litros": number(row.get("ENTREGUE LITROS")),
            "preco_litro": number(row.get("R$/L")),
            "valor_total": number(row.get("R$ TOTAL")),
            "vendedor_1": text(row.get("VENDEDOR 1")),
            "comissao_1": number(row.get("%COMISSÃO 1")),
        }
        return ("pedidos_linhas", data) if data["id_pedido"] or data["cliente"] or data["produto"] else None

    if table_name == "ENTRADAS_MP":
        data = {
            "data": excel_date(row.get("DATA")),
            "origem_nf": text(row.get("ORIGEM (NF)")),
            "materia_prima": text(row.get("MATÉRIA PRIMA")),
            "lote": text(row.get("LOTE")),
            "quantidade": number(row.get("QUANTIDADE")),
            "densidade": number(row.get("Densidade")),
            "unidade_padrao": text(row.get("UNIDADE PADRÃO")),
            "custo": number(row.get("CUSTO")),
            "frete": number(row.get("FRETE R$/Kg(L)(UND)")),
            "dif_icms": number(row.get("Dif. ICMS")),
            "valor": number(row.get("VALOR")),
            "custo_total": number(row.get("Custo Total (MP+IMP+Frete)")),
            "saldo_lote": number(row.get("SALDO LOTE")),
            "custo_medio_ponderado": number(row.get("R$/UND Média Ponderada")),
            "tipo": text(row.get("TIPO")),
        }
        return ("entradas_mp", data) if data["materia_prima"] else None

    if table_name == "PRODUCAO_LOTES":
        data = {
            "data": excel_date(row.get("DATA")),
            "lote": text(row.get("LOTE")),
            "produto": text(row.get("PRODUTO")),
            "quantidade_produzida": number(row.get("QUANTIDADE PRODUZIDA")),
            "custo_mp": number(row.get("CUSTO MP")),
            "preco_litro": number(row.get("R$/L")),
            "densidade_op": number(row.get("Densidade OP")),
            "ph": text(row.get("Ph")),
            "status_mp": text(row.get("STATUS MP")),
            "op_impressa": text(row.get("OP IMPRESSA")),
            "tipo_op": text(row.get("TIPO OP")),
            "reg_mapa": text(row.get("REG MAPA")),
            "ibama": text(row.get("IBAMA")),
        }
        return ("lotes_producao", data) if data["lote"] or data["produto"] else None

    if table_name == "SAÍDAS_MP":
        data = {
            "data": excel_date(row.get("DATA")),
            "lote_op": text(row.get("LOTE OP")),
            "materia_prima": text(row.get("MATÉRIA PRIMA")),
            "quantidade": number(row.get("QUANTIDADE")),
            "lote": text(row.get("LOTE")),
            "nome_produto": text(row.get("NOME PRODUTO")),
            "qt_prod": number(row.get("Qt_Prod")),
            "und_l": number(row.get("Und_L")),
            "anotacao": text(row.get("ANOTAÇÃO")),
        }
        return ("saidas_mp", data) if data["lote_op"] or data["materia_prima"] else None

    if table_name == "SAIDAS_PA":
        data = {
            "data_saida": excel_date(row.get("DATA SAÍDA")),
            "id_pedido": text(row.get("ID_pedido")),
            "nome_cliente": text(row.get("NOME CLIENTE")),
            "produto": text(row.get("PRODUTO")),
            "embalagem": text(row.get("EMBALAGEM")),
            "quantidade_baixada": number(row.get("QUANTIDADE BAIXADA")),
            "lote": text(row.get("LOTE")),
            "entregador": text(row.get("Entregador")),
            "tipo": text(row.get("Tipo")),
            "reg_mapa": text(row.get("REG MAPA")),
        }
        return ("saidas_pa", data) if data["id_pedido"] or data["produto"] else None

    return None


def text(value: object) -> str | None:
    if value is None:
        return None
    if isinstance(value, float) and math.isnan(value):
        return None
    result = str(value).strip()
    if result in {"", "#N/A", "#VALUE!", "#REF!", "#DIV/0!", "N E", "NE", "n e"}:
        return None
    return result


def number(value: object) -> float | None:
    if value is None or value == "":
        return None
    if isinstance(value, (int, float)) and not isinstance(value, bool):
        if isinstance(value, float) and math.isnan(value):
            return None
        return float(value)
    value_text = text(value)
    if value_text is None:
        return None
    normalized = value_text.replace("R$", "").replace("%", "").strip()
    normalized = re.sub(r"\s+", "", normalized)
    if "," in normalized and "." in normalized:
        normalized = normalized.replace(".", "").replace(",", ".")
    elif "," in normalized:
        normalized = normalized.replace(",", ".")
    try:
        return float(normalized)
    except ValueError:
        return None


def excel_date(value: object) -> str | None:
    numeric = number(value)
    if numeric is None:
        return text(value)
    if numeric < 1 or numeric > 60000:
        return text(value)
    base = date(1899, 12, 30)
    return (base + timedelta(days=int(numeric))).isoformat()


def table_key(table_name: str) -> str:
    return _slug(table_name)


def _slug(value: str) -> str:
    normalized = unicodedata.normalize("NFKD", value)
    ascii_text = "".join(ch for ch in normalized if not unicodedata.combining(ch))
    ascii_text = re.sub(r"[^a-zA-Z0-9]+", "_", ascii_text).strip("_").lower()
    return ascii_text or "sem_nome"
