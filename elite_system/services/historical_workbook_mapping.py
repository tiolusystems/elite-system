from __future__ import annotations

from dataclasses import asdict, dataclass
import re
import unicodedata


@dataclass(frozen=True)
class ColumnMapping:
    source_code: str
    status: str
    domain: str
    target: str
    rule: str
    warning: str | None = None

    def to_dict(self) -> dict[str, str | None]:
        return asdict(self)


FORMULA_TARGETS = {
    "materia prima": ("T", "transform", "pcp", "pcp_formula_itens.materia_prima_id", "Resolver MP por SKU, nome ou alias aprovado."),
    "unidade": ("T", "transform", "pcp", "pcp_formula_itens.unidade_id", "Canonicalizar pela unidade vigente."),
    "und/l": ("T", "transform", "pcp", "pcp_formula_rendimentos + pcp_formula_itens.quantidade", "Interpretar concentracao pela base de rendimento historica."),
    "seq": ("T", "transform", "pcp", "pcp_formula_etapas.ordem", "Converter numero ou fase textual sem inventar sequencia."),
    "obs": ("T", "transform", "pcp", "pcp_formula_etapas.instrucao", "Preservar instrucao e resolver sua etapa."),
}

FORMULA_RECONCILIATION = {
    "quantidade",
    "producao",
    "simula",
    "produzir",
    "lote",
    "r$/l",
    "r$/batelada",
    "r$/und",
    "% partic. form.",
    "% partic. r$/l",
    "estoque mp",
    "estoque materia prima",
    "status",
    "status mp",
}

CONTEXT_RULES: tuple[tuple[tuple[str, ...], str, dict[str, tuple[str, str, str, str, str]]], ...] = (
    (("cadastro materia prima", "cadastro_materia_prima"), "cadastros", {
        "materia prima": ("D", "defined", "cadastros", "cad_materias_primas.nome", "Destino direto; deduplicar por identidade."),
        "ibama": ("D", "defined", "cadastros", "cad_materias_primas.ibama", "Preservar formato original e validar."),
        "id_sku_mp": ("T", "transform", "cadastros", "cad_materias_primas.codigo_legado + cad_materia_prima_aliases", "Manter codigo legado e gerar SKU canonico unico."),
        "tipo": ("T", "transform", "cadastros", "cad_materias_primas.tipo", "Mapear para dominio fechado."),
        "estoque minimo": ("D", "defined", "cadastros", "cad_materias_primas.estoque_minimo", "Aplicar na unidade-base vigente."),
        "r$ estoque minimo": ("R", "out_of_scope", "auditoria", "reconciliation.mp_minimum_value", "Recalcular; nao importar como fato."),
        "r$/und": ("R", "out_of_scope", "auditoria", "est_mp_historico_precos", "Reconciliar com aquisicoes historicas."),
        "densidade": ("D", "defined", "cadastros", "cad_materias_primas.densidade", "Validar valor positivo quando informado."),
        "codigo ads": ("D", "defined", "cadastros", "cad_materias_primas.codigo_ads", "Normalizar sem perder o original."),
        "ativo/inativo": ("T", "transform", "cadastros", "cad_materias_primas.status", "Mapear para status canonico."),
        "ncm": ("T", "transform", "cadastros", "cad_materias_primas.ncm", "Preservar zeros e validar oito digitos."),
        "unidade adotada": ("T", "transform", "cadastros", "cad_materias_primas.unidade_base_id", "Resolver no catalogo tecnico de unidades."),
    }),
    (("relacao_produtos", "tbl_cadastro_pa", "relacao de produtos"), "cadastros", {
        "grupo": ("D", "defined", "cadastros", "cad_produtos_base.grupo", "Normalizar rotulo do grupo."),
        "relacao de produtos": ("D", "defined", "cadastros", "cad_produtos_base.nome", "Resolver identidade e gerar codigo canonico."),
        "densidade kg/l": ("T", "transform", "cadastros", "cad_produto_especificacoes", "Criar especificacao historica pendente de revisao."),
        "custo mp": ("R", "out_of_scope", "auditoria", "reconciliation.formula_cost", "Recalcular pela formula e custos vigentes."),
        "reg mapa": ("D", "defined", "cadastros", "cad_produtos_base.reg_mapa", "Preservar identificador documental."),
        "ph": ("T", "transform", "cadastros", "cad_produto_especificacoes", "Classificar faixa e finalidade da especificacao."),
        "ibama": ("D", "defined", "cadastros", "cad_produtos_base.ibama", "Preservar e validar formato."),
        "ads": ("D", "defined", "cadastros", "cad_produtos_base.ads", "Preservar zeros e formato original."),
        "ncm": ("T", "transform", "cadastros", "cad_produtos_base.ncm", "Validar formato quando informado."),
    }),
    (("relacao clientes", "clientes"), "cadastros", {
        "clientes": ("D", "defined", "cadastros", "cad_clientes.nome", "Deduplicar antes de aplicar."),
        "codigo": ("D", "defined", "cadastros", "cad_clientes.codigo_legado", "Duplicidade exige revisao."),
        "vendedor que cadastrou": ("T", "transform", "comercial", "cad_cliente_vendedores.papel_vinculo", "Criar vinculo temporal do tipo cadastrou."),
        "vendedor que atende": ("T", "transform", "comercial", "cad_cliente_vendedores.pessoa_id", "Resolver pessoa e vigencia do atendimento."),
        "a/i": ("T", "transform", "cadastros", "cad_clientes.status", "Mapear status canonico."),
        "contato": ("P", "pending", "cadastros", "cad_cliente_contatos", "Separar nome, papel, telefone e e-mail somente quando seguro."),
        "cidade": ("T", "transform", "cadastros", "cad_clientes.cidade", "Normalizar municipio."),
        "uf": ("P", "pending", "cadastros", "cad_clientes.uf", "Nao inferir UF sem fonte confiavel."),
        "valor total de compras": ("R", "out_of_scope", "auditoria", "reconciliation.customer_sales", "Recalcular pelos pedidos ativos."),
    }),
    (("vendedores",), "cadastros", {
        "funcionario": ("D", "defined", "cadastros", "cad_pessoas_comerciais.nome", "Resolver identidade unica da pessoa."),
        "funcao": ("T", "transform", "cadastros", "cad_pessoa_papeis", "Mapear papel comercial; nao e role de autenticacao."),
        "ativo/inativo": ("T", "transform", "cadastros", "cad_pessoas_comerciais.status", "Mapear status canonico."),
        "admissao": ("T", "transform", "cadastros", "cad_pessoa_papeis.vigencia_inicio", "Preservar vigencia historica."),
        "demissao": ("T", "transform", "cadastros", "cad_pessoa_papeis.vigencia_fim", "Preservar vigencia historica."),
    }),
    (("veiculos",), "logistica", {
        "veiculo": ("D", "defined", "logistica", "cad_veiculos.descricao", "Preservar descricao e codigo legado."),
        "placa": ("T", "transform", "logistica", "cad_veiculos.placa", "Normalizar e validar placa."),
    }),
    (("entradas_mp", "entradas mp"), "estoque", {
        "data": ("D", "defined", "estoque", "est_movimentos_mp.data_evento", "Preservar data historica."),
        "origem (nf)": ("T", "transform", "faturamento", "fat_referencias_fiscais_legadas.documento_ref", "Resolver referencia fiscal sem inventar chave."),
        "materia prima": ("T", "transform", "estoque", "est_movimentos_mp.materia_prima_id", "Resolver MP por identidade aprovada."),
        "lote": ("T", "transform", "estoque", "est_lotes_mp.codigo_lote_legado", "Preservar lote legado e gerar chave canonica."),
        "quantidade": ("T", "transform", "estoque", "est_movimentos_mp.quantidade", "Converter para unidade-base."),
        "densidade": ("T", "transform", "estoque", "est_movimentos_mp_valores.densidade_origem", "Preservar snapshot da aquisicao."),
        "unidade padrao": ("T", "transform", "estoque", "est_movimentos_mp_valores.unidade_origem_id", "Resolver unidade e conversao vigente."),
        "custo": ("T", "transform", "financeiro", "est_movimentos_mp_valores.valor_materia_prima", "Normalizar componente de aquisicao."),
        "frete r$/kg(l)(und)": ("T", "transform", "financeiro", "est_movimentos_mp_valores.frete", "Recompor valor pela quantidade de origem."),
        "dif. icms": ("D", "defined", "financeiro", "est_movimentos_mp_valores.difal_icms", "Componente do custo de MP fora de SP."),
        "custo total (mp+imp+frete)": ("D", "defined", "auditoria", "est_movimentos_mp_valores.custo_total_legado", "Preservar para reconciliacao."),
        "saldo lote": ("D", "defined", "auditoria", "est_movimentos_mp_valores.saldo_lote_legado", "Snapshot somente para reconciliacao."),
        "r$/und media ponderada": ("D", "defined", "auditoria", "est_movimentos_mp_valores.custo_medio_ponderado_legado", "Snapshot somente para reconciliacao."),
    }),
    (("saidas_mp", "saidas mp"), "estoque", {
        "data": ("T", "transform", "estoque", "est_movimentos_mp.data_evento", "Preservar data do consumo."),
        "lote op": ("T", "transform", "pcp", "pcp_ordens_producao.codigo_legado", "Resolver OP historica."),
        "materia prima": ("T", "transform", "estoque", "est_movimentos_mp.materia_prima_id", "Resolver MP por identidade aprovada."),
        "quantidade": ("D", "defined", "estoque", "est_movimentos_mp.quantidade", "Registrar consumo append-only."),
        "lote": ("T", "transform", "estoque", "est_movimentos_mp.lote_mp_id", "Resolver lote historico."),
        "anotacao": ("D", "defined", "estoque", "est_movimentos_mp.observacao", "Preservar anotacao operacional."),
    }),
    (("lotes_producao", "producao_lotes", "lotes producao"), "pcp", {
        "data": ("D", "defined", "pcp", "pcp_ordens_producao.data_historica", "Preservar data historica."),
        "lote": ("T", "transform", "estoque", "est_lotes_pa.codigo_lote_legado", "Resolver familia PA ou PI sem inferencia silenciosa."),
        "produto": ("T", "transform", "pcp", "cad_produtos_base.id", "Resolver produto por nome ou alias."),
        "quantidade produzida": ("T", "transform", "pcp", "pcp_op_produtos_gerados.quantidade", "Resolver unidade e natureza PA/PI."),
        "densidade op": ("P", "pending", "pcp", "pcp_op_cq_resultados.densidade_kg_l", "CQ historico parcial; requer revisao."),
        "ph": ("P", "pending", "pcp", "pcp_op_cq_resultados.ph", "CQ historico parcial; requer revisao."),
        "tipo op": ("T", "transform", "pcp", "pcp_ordens_producao.tipo_op", "Mapear para tipo fechado."),
    }),
    (("saidas pa", "saidas_pa"), "estoque", {
        "data saida": ("D", "defined", "estoque", "est_movimentos_pa.data_evento", "Preservar data da expedicao."),
        "id_pedido": ("T", "transform", "pedidos", "com_pedidos.codigo_legado", "Resolver pedido por codigo legado."),
        "nome cliente": ("R", "out_of_scope", "auditoria", "reconciliation.order_customer", "Conferir contra o cliente do pedido."),
        "produto": ("T", "transform", "estoque", "cad_produtos_base.id", "Resolver produto por identidade aprovada."),
        "embalagem": ("T", "transform", "estoque", "cad_produto_embalagens.id", "Resolver configuracao produto e embalagem."),
        "quantidade baixada": ("D", "defined", "estoque", "est_movimentos_pa.quantidade", "Registrar saida append-only."),
        "lote": ("T", "transform", "estoque", "est_lotes_pa.codigo_lote_legado", "Resolver lote historico."),
        "entregador": ("T", "transform", "logistica", "exp_romaneio_entregadores.pessoa_id", "Resolver vinculo historico do entregador."),
    }),
)


def classify_reference(
    *,
    sheet_name: str,
    table_name: str,
    header: str,
    source_kind: str,
    table_headers: list[str] | None = None,
) -> ColumnMapping:
    if source_kind == "worksheet_outside_table":
        return ColumnMapping(
            source_code="S",
            status="out_of_scope",
            domain="auditoria",
            target="migration.source_rows.source_payload",
            rule="Preservar a coluna externa a tabelas somente na camada bruta auditavel.",
            warning="Coluna usada fora de tabela estruturada; sem promocao automatica.",
        )

    header_key = normalize_label(header)
    context = normalize_label(f"{sheet_name} {table_name}")
    normalized_headers = {normalize_label(value) for value in (table_headers or [])}

    if _is_formula_table(normalized_headers):
        if header_key in FORMULA_TARGETS:
            return _mapping(FORMULA_TARGETS[header_key])
        if header_key in FORMULA_RECONCILIATION:
            return ColumnMapping("R", "out_of_scope", "auditoria", "reconciliation.formula_metrics", "Recalcular e usar somente na reconciliacao.")

    if _is_guarantee_table(normalized_headers, header_key):
        if header_key in {"pp (%/l)", "pv (kg/l)"}:
            return ColumnMapping("T", "transform", "pcp", "cad_produto_garantias", "Classificar fonte, finalidade e limite da garantia.")
        if header_key.startswith("garantias"):
            return ColumnMapping("T", "transform", "cadastros", "cad_nutrientes + cad_produto_garantias.nutriente_id", "Resolver nutriente no catalogo tecnico.")
        return ColumnMapping("R", "out_of_scope", "auditoria", "reconciliation.guarantee_metrics", "Recalcular e preservar somente para reconciliacao.")

    if _is_packaging_table(context, normalized_headers):
        if header_key == "material":
            return ColumnMapping("T", "transform", "cadastros", "cad_embalagem_componentes", "Resolver componente, quantidade e vigencia.")
        if header_key in {"embalagens", "embalagem"}:
            return ColumnMapping("T", "transform", "cadastros", "cad_embalagens", "Resolver embalagem canonica.")
        if header_key in {"kg", "peso"}:
            return ColumnMapping("T", "transform", "logistica", "cad_embalagem_versoes.peso_kg", "Criar versao historica pendente de revisao.")
        if "volume" in header_key:
            return ColumnMapping("T", "transform", "logistica", "cad_embalagem_versoes.volume_m3", "Normalizar cubagem e unidade.")
        return ColumnMapping("R", "out_of_scope", "auditoria", "reconciliation.packaging_cost", "Recalcular custo pela composicao e aquisicoes.")

    for markers, _domain, rules in CONTEXT_RULES:
        if any(marker in context for marker in markers) and header_key in rules:
            return _mapping(rules[header_key])

    generic = _generic_mapping(context, header_key)
    if generic is not None:
        return generic

    return ColumnMapping(
        source_code="S",
        status="out_of_scope",
        domain="auditoria",
        target="migration.source_rows.source_payload",
        rule="Preservar na camada bruta; nao promover sem regra relacional aprovada.",
        warning="Referencia classificada por fallback seguro; revisar antes da carga I2.",
    )


def normalize_label(value: str) -> str:
    normalized = unicodedata.normalize("NFKD", value)
    ascii_value = "".join(char for char in normalized if not unicodedata.combining(char))
    return re.sub(r"\s+", " ", ascii_value.strip().casefold())


def _mapping(values: tuple[str, str, str, str, str]) -> ColumnMapping:
    return ColumnMapping(*values)


def _is_formula_table(headers: set[str]) -> bool:
    return "materia prima" in headers and bool({"und/l", "seq", "r$/batelada"}.intersection(headers))


def _is_guarantee_table(headers: set[str], header: str) -> bool:
    return {"pp (%/l)", "pv (kg/l)"}.intersection(headers) or header.startswith("garantias")


def _is_packaging_table(context: str, headers: set[str]) -> bool:
    return "peso_embalagens" in context or "custo_" in context or ("material" in headers and "r$/und" in headers)


def _generic_mapping(context: str, header: str) -> ColumnMapping | None:
    if header.startswith("coluna") or not header:
        return ColumnMapping("S", "out_of_scope", "auditoria", "migration.source_rows.source_payload", "Preservar cabecalho residual sem promocao operacional.")
    if any(token in context for token in ("pedido", "vendas")):
        if header in {"cliente", "clientes"}:
            return ColumnMapping("T", "transform", "pedidos", "com_pedidos.cliente_id", "Resolver cliente por codigo, identidade e propriedade.")
        if header in {"produto", "produtos"}:
            return ColumnMapping("T", "transform", "pedidos", "com_pedido_itens.produto_id", "Resolver produto e embalagem comercial.")
        if "vendedor" in header:
            return ColumnMapping("T", "transform", "comercial", "com_pedido_comissionados.pessoa_id", "Resolver pessoa e papel comercial vigente.")
        if "comissao" in header and "%" in header:
            return ColumnMapping("D", "defined", "financeiro", "com_pedido_comissionados.percentual_comissao", "Preservar taxa congelada no pedido historico.")
        if "comissao" in header:
            return ColumnMapping("T", "transform", "financeiro", "fin_comissao_saldos_historicos", "Classificar prevista, liberada, paga ou saldo de abertura.")
        if "nota fiscal" in header or header == "nf":
            return ColumnMapping("T", "transform", "faturamento", "fat_referencias_fiscais_legadas", "Resolver modalidade e referencia fiscal.")
    if any(token in context for token in ("campanha", "premiacao", "premio")):
        return ColumnMapping("T", "transform", "comercial", "com_campanhas + com_campanha_movimentos", "Resolver campanha, vigencia, regra e beneficiario.")
    if any(token in header for token in ("saldo", "estoque", "total", "diferenca", "media ponderada", "r$/")):
        return ColumnMapping("R", "out_of_scope", "auditoria", "reconciliation.derived_value", "Valor derivado; recalcular e reconciliar.")
    return None
