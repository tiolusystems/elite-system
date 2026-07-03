from __future__ import annotations

from dataclasses import dataclass
from enum import StrEnum


class RomaneioStatus(StrEnum):
    RASCUNHO = "rascunho"
    EM_SEPARACAO = "em_separacao"
    CONFIRMADO = "confirmado"
    CANCELADO = "cancelado"
    ESTORNADO = "estornado"


class SeparacaoTipo(StrEnum):
    TOTAL = "total"
    PARCIAL = "parcial"


class MovimentoPATipo(StrEnum):
    RESERVA = "reserva"
    LIBERACAO_RESERVA = "liberacao_reserva"
    BAIXA = "baixa"
    REVERSAO_BAIXA = "reversao_baixa"


@dataclass(frozen=True)
class PedidoItemPendente:
    id_pedido: str
    produto: str
    quantidade_pendente: float
    cliente: str | None = None
    item_id: str | None = None

    def __post_init__(self) -> None:
        _validate_required(self.id_pedido, "id_pedido")
        _validate_required(self.produto, "produto")
        _validate_positive(self.quantidade_pendente, "quantidade_pendente")


@dataclass(frozen=True)
class LotePADisponivel:
    produto: str
    lote: str
    quantidade_disponivel: float
    prioridade: int = 100

    def __post_init__(self) -> None:
        _validate_required(self.produto, "produto")
        _validate_required(self.lote, "lote")
        _validate_positive(self.quantidade_disponivel, "quantidade_disponivel")


@dataclass(frozen=True)
class RomaneioItem:
    id_pedido: str
    produto: str
    lote: str
    quantidade: float
    tipo_separacao: SeparacaoTipo
    cliente: str | None = None
    pedido_item_id: str | None = None

    def __post_init__(self) -> None:
        _validate_required(self.id_pedido, "id_pedido")
        _validate_required(self.produto, "produto")
        _validate_required(self.lote, "lote")
        _validate_positive(self.quantidade, "quantidade")


@dataclass(frozen=True)
class Romaneio:
    numero: str
    status: RomaneioStatus
    itens: tuple[RomaneioItem, ...]
    reserva_lotes: bool = False

    def __post_init__(self) -> None:
        _validate_required(self.numero, "numero")
        if not self.itens:
            raise ValueError("romaneio must have at least one item")

    @property
    def quantidade_total(self) -> float:
        return sum(item.quantidade for item in self.itens)


@dataclass(frozen=True)
class MovimentoPA:
    tipo: MovimentoPATipo
    id_pedido: str
    produto: str
    lote: str
    quantidade: float
    romaneio_numero: str

    def __post_init__(self) -> None:
        _validate_positive(self.quantidade, "quantidade")


@dataclass(frozen=True)
class EventoRomaneio:
    action: str
    entity_type: str
    entity_id: str
    metadata: dict[str, object]


@dataclass(frozen=True)
class RomaneioResultado:
    romaneio: Romaneio
    movimentos_pa: tuple[MovimentoPA, ...]
    eventos: tuple[EventoRomaneio, ...]


def _validate_required(value: str, field_name: str) -> None:
    if not value or not value.strip():
        raise ValueError(f"{field_name} is required")


def _validate_positive(value: float, field_name: str) -> None:
    if value <= 0:
        raise ValueError(f"{field_name} must be positive")
