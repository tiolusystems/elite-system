from __future__ import annotations

from dataclasses import dataclass
from enum import StrEnum


class CadastroStatus(StrEnum):
    ACTIVE = "active"
    INACTIVE = "inactive"
    PENDING_REVIEW = "pending_review"


class TipoDocumento(StrEnum):
    CPF = "cpf"
    CNPJ = "cnpj"
    IE = "ie"
    OUTRO = "outro"


class TipoEndereco(StrEnum):
    ENTREGA = "entrega"
    COBRANCA = "cobranca"
    OPERACIONAL = "operacional"
    OUTRO = "outro"


class PapelPessoa(StrEnum):
    FUNCIONARIO = "funcionario"
    VENDEDOR = "vendedor"
    AGENTE = "agente"
    TECNICO_CAMPO = "tecnico_campo"
    ENTREGADOR = "entregador"
    GERENTE = "gerente"
    COMISSIONADO = "comissionado"


class TipoComercial(StrEnum):
    FUNCIONARIO_ELITE = "funcionario_elite"
    AGENTE_VINCULADO = "agente_vinculado"
    AGENTE_DIRETO_ELITE = "agente_direto_elite"
    VENDEDOR_DIRETO_ELITE = "vendedor_direto_elite"
    TECNICO_CAMPO = "tecnico_campo"
    ENTREGADOR = "entregador"
    GERENTE = "gerente"
    VENDEDOR_GERENTE = "vendedor_gerente"


class TipoLimiteGarantia(StrEnum):
    MINIMO = "minimo"
    MAXIMO = "maximo"
    FAIXA = "faixa"
    DECLARADO = "declarado"


class FonteGarantia(StrEnum):
    MAPA = "mapa"
    MANUAL = "manual"
    LABORATORIO = "laboratorio"
    FORNECEDOR = "fornecedor"
    CALCULADO = "calculado"


class StatusCredito(StrEnum):
    LIBERADO = "liberado"
    REDUZIDO = "reduzido"
    BLOQUEADO = "bloqueado"
    PENDENTE_APROVACAO = "pendente_aprovacao"


class PedidoVendedorStatus(StrEnum):
    RASCUNHO = "rascunho"
    ENVIADO = "enviado"
    BLOQUEADO_CREDITO = "bloqueado_credito"
    BLOQUEADO_INADIMPLENCIA = "bloqueado_inadimplencia"
    PENDENTE_APROVACAO = "pendente_aprovacao"
    APROVADO = "aprovado"
    REJEITADO = "rejeitado"
    CANCELADO = "cancelado"


@dataclass(frozen=True)
class Cliente:
    nome: str
    cidade: str
    uf: str
    codigo_legado: str | None = None
    status: CadastroStatus | str = CadastroStatus.ACTIVE
    apelidos: tuple[str, ...] = ()
    valor_total_compras: float | None = None
    source_row_id: int | None = None
    source_batch_id: int | None = None

    def __post_init__(self) -> None:
        _validate_required(self.nome, "nome")
        _validate_required(self.cidade, "cidade")
        uf = _normalize_uf(self.uf)
        object.__setattr__(self, "uf", uf)
        object.__setattr__(self, "status", _coerce_enum(CadastroStatus, self.status, "status"))
        object.__setattr__(self, "apelidos", _coerce_text_tuple(self.apelidos, "apelidos"))
        _validate_optional_text(self.codigo_legado, "codigo_legado")
        _validate_non_negative_optional(self.valor_total_compras, "valor_total_compras")


@dataclass(frozen=True)
class ClientePropriedade:
    cliente_id: str
    nome: str
    cnpj: str | None = None
    cidade: str | None = None
    uf: str | None = None
    status: CadastroStatus | str = CadastroStatus.ACTIVE

    def __post_init__(self) -> None:
        _validate_required(self.cliente_id, "cliente_id")
        _validate_required(self.nome, "nome")
        _validate_optional_text(self.cnpj, "cnpj")
        if self.uf is not None:
            object.__setattr__(self, "uf", _normalize_uf(self.uf))
        object.__setattr__(self, "status", _coerce_enum(CadastroStatus, self.status, "status"))


@dataclass(frozen=True)
class ClienteDocumento:
    cliente_id: str
    tipo: TipoDocumento | str
    numero: str
    propriedade_id: str | None = None

    def __post_init__(self) -> None:
        _validate_required(self.cliente_id, "cliente_id")
        _validate_required(self.numero, "numero")
        object.__setattr__(self, "tipo", _coerce_enum(TipoDocumento, self.tipo, "tipo"))
        _validate_optional_text(self.propriedade_id, "propriedade_id")


@dataclass(frozen=True)
class ClienteEndereco:
    cliente_id: str
    tipo: TipoEndereco | str
    cidade: str
    uf: str
    logradouro: str | None = None
    numero: str | None = None
    complemento: str | None = None
    bairro: str | None = None
    cep: str | None = None
    propriedade_id: str | None = None

    def __post_init__(self) -> None:
        _validate_required(self.cliente_id, "cliente_id")
        _validate_required(self.cidade, "cidade")
        object.__setattr__(self, "uf", _normalize_uf(self.uf))
        object.__setattr__(self, "tipo", _coerce_enum(TipoEndereco, self.tipo, "tipo"))


@dataclass(frozen=True)
class ClienteContato:
    cliente_id: str
    nome: str
    papel: str
    telefone: str | None = None
    email: str | None = None
    propriedade_id: str | None = None

    def __post_init__(self) -> None:
        _validate_required(self.cliente_id, "cliente_id")
        _validate_required(self.nome, "nome")
        _validate_required(self.papel, "papel")
        if not _has_text(self.telefone) and not _has_text(self.email):
            raise ValueError("telefone or email is required")


@dataclass(frozen=True)
class ClienteVendedor:
    cliente_id: str
    pessoa_id: str
    status: CadastroStatus | str = CadastroStatus.ACTIVE
    vigencia_inicio: str | None = None
    vigencia_fim: str | None = None

    def __post_init__(self) -> None:
        _validate_required(self.cliente_id, "cliente_id")
        _validate_required(self.pessoa_id, "pessoa_id")
        object.__setattr__(self, "status", _coerce_enum(CadastroStatus, self.status, "status"))


@dataclass(frozen=True)
class PessoaComercial:
    nome: str
    papeis: tuple[PapelPessoa | str, ...]
    tipo_comercial: TipoComercial | str | None = None
    codigo_legado: str | None = None
    status: CadastroStatus | str = CadastroStatus.ACTIVE
    vendedor_responsavel_id: str | None = None
    apelidos: tuple[str, ...] = ()
    grafias_incorretas: tuple[str, ...] = ()

    def __post_init__(self) -> None:
        _validate_required(self.nome, "nome")
        if not self.papeis:
            raise ValueError("papeis must have at least one item")
        papeis = tuple(_coerce_enum(PapelPessoa, papel, "papeis") for papel in self.papeis)
        object.__setattr__(self, "papeis", papeis)
        object.__setattr__(self, "status", _coerce_enum(CadastroStatus, self.status, "status"))
        object.__setattr__(self, "apelidos", _coerce_text_tuple(self.apelidos, "apelidos"))
        object.__setattr__(self, "grafias_incorretas", _coerce_text_tuple(self.grafias_incorretas, "grafias_incorretas"))
        if self.tipo_comercial is not None:
            tipo = _coerce_enum(TipoComercial, self.tipo_comercial, "tipo_comercial")
            object.__setattr__(self, "tipo_comercial", tipo)
            if tipo == TipoComercial.AGENTE_VINCULADO:
                _validate_required(self.vendedor_responsavel_id, "vendedor_responsavel_id")
        _validate_optional_text(self.codigo_legado, "codigo_legado")


@dataclass(frozen=True)
class MateriaPrima:
    nome: str
    sku_corrigido: str
    unidade_base_estoque: str
    codigo_legado: str | None = None
    status: CadastroStatus | str = CadastroStatus.ACTIVE
    tipo: str | None = None
    densidade: float | None = None
    estoque_minimo: float | None = None
    ncm: str | None = None
    ibama: str | None = None
    codigo_ads: str | None = None

    def __post_init__(self) -> None:
        _validate_required(self.nome, "nome")
        _validate_required(self.sku_corrigido, "sku_corrigido")
        _validate_required(self.unidade_base_estoque, "unidade_base_estoque")
        object.__setattr__(self, "status", _coerce_enum(CadastroStatus, self.status, "status"))
        _validate_positive_optional(self.densidade, "densidade")
        _validate_non_negative_optional(self.estoque_minimo, "estoque_minimo")


@dataclass(frozen=True)
class ConversaoUnidadeMP:
    materia_prima_id: str
    unidade_origem: str
    unidade_destino: str
    fator: float
    vigencia_inicio: str | None = None
    vigencia_fim: str | None = None

    def __post_init__(self) -> None:
        _validate_required(self.materia_prima_id, "materia_prima_id")
        _validate_required(self.unidade_origem, "unidade_origem")
        _validate_required(self.unidade_destino, "unidade_destino")
        _validate_positive(self.fator, "fator")


@dataclass(frozen=True)
class ProdutoBase:
    codigo_produto: str
    nome: str
    status: CadastroStatus | str = CadastroStatus.ACTIVE
    grupo: str | None = None
    densidade_kg_l: float | None = None
    prazo_validade_meses: int | None = None
    reg_mapa: str | None = None
    ncm: str | None = None
    ibama: str | None = None
    ads: str | None = None

    def __post_init__(self) -> None:
        _validate_required(self.codigo_produto, "codigo_produto")
        _validate_required(self.nome, "nome")
        object.__setattr__(self, "status", _coerce_enum(CadastroStatus, self.status, "status"))
        _validate_positive_optional(self.densidade_kg_l, "densidade_kg_l")
        if self.prazo_validade_meses is not None and not 1 <= self.prazo_validade_meses <= 240:
            raise ValueError("prazo_validade_meses must be between 1 and 240")


@dataclass(frozen=True)
class Embalagem:
    descricao: str
    unidade: str
    volume_litros: float | None = None
    controla_estoque: bool = False
    materia_prima_id: str | None = None
    codigo_legado: str | None = None
    status: CadastroStatus | str = CadastroStatus.ACTIVE

    def __post_init__(self) -> None:
        _validate_required(self.descricao, "descricao")
        _validate_required(self.unidade, "unidade")
        object.__setattr__(self, "status", _coerce_enum(CadastroStatus, self.status, "status"))
        _validate_positive_optional(self.volume_litros, "volume_litros")
        if self.controla_estoque:
            _validate_required(self.materia_prima_id, "materia_prima_id")


@dataclass(frozen=True)
class ProdutoEmbalagem:
    produto_id: str
    embalagem_id: str
    codigo_item: str
    status: CadastroStatus | str = CadastroStatus.ACTIVE

    def __post_init__(self) -> None:
        _validate_required(self.produto_id, "produto_id")
        _validate_required(self.embalagem_id, "embalagem_id")
        _validate_required(self.codigo_item, "codigo_item")
        object.__setattr__(self, "status", _coerce_enum(CadastroStatus, self.status, "status"))


@dataclass(frozen=True)
class Veiculo:
    descricao: str
    placa: str | None = None
    status: CadastroStatus | str = CadastroStatus.ACTIVE
    codigo_legado: str | None = None
    capacidade: float | None = None

    def __post_init__(self) -> None:
        _validate_required(self.descricao, "descricao")
        _validate_optional_text(self.placa, "placa")
        object.__setattr__(self, "status", _coerce_enum(CadastroStatus, self.status, "status"))
        _validate_positive_optional(self.capacidade, "capacidade")


@dataclass(frozen=True)
class GarantiaProdutoMapa:
    produto_id: str
    nutriente: str
    tipo_limite: TipoLimiteGarantia | str
    valor: float
    unidade: str
    fonte: FonteGarantia | str = FonteGarantia.MAPA
    vigencia_inicio: str | None = None
    vigencia_fim: str | None = None

    def __post_init__(self) -> None:
        _validate_required(self.produto_id, "produto_id")
        _validate_required(self.nutriente, "nutriente")
        _validate_required(self.unidade, "unidade")
        _validate_non_negative(self.valor, "valor")
        object.__setattr__(self, "tipo_limite", _coerce_enum(TipoLimiteGarantia, self.tipo_limite, "tipo_limite"))
        object.__setattr__(self, "fonte", _coerce_enum(FonteGarantia, self.fonte, "fonte"))


@dataclass(frozen=True)
class GarantiaLoteMateriaPrima:
    materia_prima_id: str
    lote_mp_id: str
    nutriente: str
    valor: float
    unidade: str
    fonte: FonteGarantia | str
    documento_referencia: str | None = None
    created_by: int | None = None

    def __post_init__(self) -> None:
        _validate_required(self.materia_prima_id, "materia_prima_id")
        _validate_required(self.lote_mp_id, "lote_mp_id")
        _validate_required(self.nutriente, "nutriente")
        _validate_required(self.unidade, "unidade")
        _validate_non_negative(self.valor, "valor")
        object.__setattr__(self, "fonte", _coerce_enum(FonteGarantia, self.fonte, "fonte"))
        if self.fonte in {FonteGarantia.MANUAL, FonteGarantia.LABORATORIO} and self.created_by is None:
            raise ValueError("created_by is required for manual or laboratory guarantees")


@dataclass(frozen=True)
class LimiteCreditoCliente:
    cliente_id: str
    limite_disponivel: float
    status_credito: StatusCredito | str
    updated_by: int
    limite_manual: float | None = None
    limite_calculado: float | None = None
    motivo: str | None = None

    def __post_init__(self) -> None:
        _validate_required(self.cliente_id, "cliente_id")
        _validate_non_negative(self.limite_disponivel, "limite_disponivel")
        _validate_non_negative_optional(self.limite_manual, "limite_manual")
        _validate_non_negative_optional(self.limite_calculado, "limite_calculado")
        object.__setattr__(self, "status_credito", _coerce_enum(StatusCredito, self.status_credito, "status_credito"))
        if self.updated_by is None:
            raise ValueError("updated_by is required")
        if self.status_credito != StatusCredito.LIBERADO:
            _validate_required(self.motivo, "motivo")


@dataclass(frozen=True)
class AnaliseCreditoPedido:
    pedido_id: str
    cliente_id: str
    vendedor_id: str
    valor_pedido: float
    limite_credito: LimiteCreditoCliente
    status_pedido: PedidoVendedorStatus | str
    titulos_vencidos: float = 0.0
    pedidos_em_aberto: float = 0.0

    def __post_init__(self) -> None:
        _validate_required(self.pedido_id, "pedido_id")
        _validate_required(self.cliente_id, "cliente_id")
        _validate_required(self.vendedor_id, "vendedor_id")
        _validate_non_negative(self.valor_pedido, "valor_pedido")
        _validate_non_negative(self.titulos_vencidos, "titulos_vencidos")
        _validate_non_negative(self.pedidos_em_aberto, "pedidos_em_aberto")
        object.__setattr__(self, "status_pedido", _coerce_enum(PedidoVendedorStatus, self.status_pedido, "status_pedido"))

    @property
    def excede_limite(self) -> bool:
        return self.valor_pedido > self.limite_credito.limite_disponivel

    @property
    def tem_inadimplencia(self) -> bool:
        return self.titulos_vencidos > 0


def _has_text(value: str | None) -> bool:
    return value is not None and bool(value.strip())


def _validate_required(value: str | None, field_name: str) -> None:
    if not _has_text(value):
        raise ValueError(f"{field_name} is required")


def _validate_optional_text(value: str | None, field_name: str) -> None:
    if value is not None and not value.strip():
        raise ValueError(f"{field_name} cannot be blank")


def _validate_positive(value: float, field_name: str) -> None:
    if value <= 0:
        raise ValueError(f"{field_name} must be positive")


def _validate_positive_optional(value: float | None, field_name: str) -> None:
    if value is not None:
        _validate_positive(value, field_name)


def _validate_non_negative(value: float, field_name: str) -> None:
    if value < 0:
        raise ValueError(f"{field_name} cannot be negative")


def _validate_non_negative_optional(value: float | None, field_name: str) -> None:
    if value is not None:
        _validate_non_negative(value, field_name)


def _normalize_uf(value: str) -> str:
    _validate_required(value, "uf")
    uf = value.strip().upper()
    if len(uf) != 2 or not uf.isalpha():
        raise ValueError("uf must have exactly two letters")
    return uf


def _coerce_enum(enum_type: type[StrEnum], value: StrEnum | str, field_name: str) -> StrEnum:
    try:
        return value if isinstance(value, enum_type) else enum_type(str(value))
    except ValueError as exc:
        allowed = ", ".join(item.value for item in enum_type)
        raise ValueError(f"{field_name} must be one of: {allowed}") from exc


def _coerce_text_tuple(values: tuple[str, ...], field_name: str) -> tuple[str, ...]:
    result: list[str] = []
    for value in values:
        _validate_required(value, field_name)
        result.append(value.strip())
    return tuple(result)
