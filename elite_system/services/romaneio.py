from __future__ import annotations

from dataclasses import replace

from elite_system.domain.romaneio import (
    EventoRomaneio,
    LotePADisponivel,
    MovimentoPA,
    MovimentoPATipo,
    PedidoItemPendente,
    Romaneio,
    RomaneioItem,
    RomaneioResultado,
    RomaneioStatus,
    SeparacaoTipo,
)


def criar_romaneio_rascunho(
    *,
    numero: str,
    pedido_item: PedidoItemPendente,
    lotes_disponiveis: list[LotePADisponivel] | tuple[LotePADisponivel, ...],
    quantidade_solicitada: float | None = None,
) -> RomaneioResultado:
    itens = _planejar_itens(pedido_item, lotes_disponiveis, quantidade_solicitada)
    romaneio = Romaneio(numero=numero, status=RomaneioStatus.RASCUNHO, itens=tuple(itens))
    return RomaneioResultado(
        romaneio=romaneio,
        movimentos_pa=(),
        eventos=(
            _evento(
                "romaneio.draft_created",
                romaneio,
                {
                    "id_pedido": pedido_item.id_pedido,
                    "produto": pedido_item.produto,
                    "quantidade_romaneada": romaneio.quantidade_total,
                    "tipo_separacao": _tipo_separacao(pedido_item, romaneio.quantidade_total).value,
                },
            ),
        ),
    )


def iniciar_separacao(romaneio: Romaneio, *, reservar_lotes: bool = False) -> RomaneioResultado:
    _ensure_status(romaneio, {RomaneioStatus.RASCUNHO}, "iniciar separacao")
    atualizado = replace(romaneio, status=RomaneioStatus.EM_SEPARACAO, reserva_lotes=reservar_lotes)
    movimentos = _movimentos(atualizado, MovimentoPATipo.RESERVA) if reservar_lotes else ()
    return RomaneioResultado(
        romaneio=atualizado,
        movimentos_pa=movimentos,
        eventos=(
            _evento(
                "romaneio.separation_started",
                atualizado,
                {"reserva_lotes": reservar_lotes, "quantidade_total": atualizado.quantidade_total},
            ),
        ),
    )


def confirmar_romaneio(romaneio: Romaneio) -> RomaneioResultado:
    _ensure_status(romaneio, {RomaneioStatus.RASCUNHO, RomaneioStatus.EM_SEPARACAO}, "confirmar romaneio")
    atualizado = replace(romaneio, status=RomaneioStatus.CONFIRMADO)
    movimentos = _movimentos(atualizado, MovimentoPATipo.BAIXA)
    return RomaneioResultado(
        romaneio=atualizado,
        movimentos_pa=movimentos,
        eventos=(
            _evento(
                "romaneio.confirmed",
                atualizado,
                {
                    "quantidade_total": atualizado.quantidade_total,
                    "gera_baixa_pa": True,
                    "reserva_lotes": atualizado.reserva_lotes,
                },
            ),
        ),
    )


def cancelar_romaneio(romaneio: Romaneio) -> RomaneioResultado:
    _ensure_status(romaneio, {RomaneioStatus.RASCUNHO, RomaneioStatus.EM_SEPARACAO}, "cancelar romaneio")
    atualizado = replace(romaneio, status=RomaneioStatus.CANCELADO)
    movimentos = _movimentos(atualizado, MovimentoPATipo.LIBERACAO_RESERVA) if romaneio.reserva_lotes else ()
    return RomaneioResultado(
        romaneio=atualizado,
        movimentos_pa=movimentos,
        eventos=(
            _evento(
                "romaneio.cancelled",
                atualizado,
                {
                    "libera_reserva": romaneio.reserva_lotes,
                    "quantidade_total": atualizado.quantidade_total,
                },
            ),
        ),
    )


def estornar_romaneio(romaneio: Romaneio) -> RomaneioResultado:
    _ensure_status(romaneio, {RomaneioStatus.CONFIRMADO}, "estornar romaneio")
    atualizado = replace(romaneio, status=RomaneioStatus.ESTORNADO)
    movimentos = _movimentos(atualizado, MovimentoPATipo.REVERSAO_BAIXA)
    return RomaneioResultado(
        romaneio=atualizado,
        movimentos_pa=movimentos,
        eventos=(
            _evento(
                "romaneio.reversed",
                atualizado,
                {"reverte_baixa_pa": True, "quantidade_total": atualizado.quantidade_total},
            ),
        ),
    )


def saldo_pendente_pedido(pedido_item: PedidoItemPendente, romaneio: Romaneio) -> float:
    quantidade_romaneada = sum(
        item.quantidade
        for item in romaneio.itens
        if item.id_pedido == pedido_item.id_pedido and item.produto == pedido_item.produto
    )
    saldo = pedido_item.quantidade_pendente - quantidade_romaneada
    return 0.0 if abs(saldo) < 0.000001 else saldo


def _planejar_itens(
    pedido_item: PedidoItemPendente,
    lotes_disponiveis: list[LotePADisponivel] | tuple[LotePADisponivel, ...],
    quantidade_solicitada: float | None,
) -> list[RomaneioItem]:
    quantidade = pedido_item.quantidade_pendente if quantidade_solicitada is None else quantidade_solicitada
    if quantidade <= 0:
        raise ValueError("quantidade_solicitada must be positive")
    if quantidade > pedido_item.quantidade_pendente:
        raise ValueError("quantidade_solicitada cannot exceed pedido pending quantity")

    lotes = sorted(
        [lote for lote in lotes_disponiveis if lote.produto == pedido_item.produto],
        key=lambda item: (item.prioridade, item.lote),
    )
    if not lotes:
        raise ValueError("no available lots for product")

    restante = quantidade
    tipo = _tipo_separacao(pedido_item, quantidade)
    itens: list[RomaneioItem] = []
    for lote in lotes:
        if restante <= 0:
            break
        separado = min(restante, lote.quantidade_disponivel)
        itens.append(
            RomaneioItem(
                id_pedido=pedido_item.id_pedido,
                produto=pedido_item.produto,
                lote=lote.lote,
                quantidade=separado,
                tipo_separacao=tipo,
                cliente=pedido_item.cliente,
                pedido_item_id=pedido_item.item_id,
            )
        )
        restante -= separado

    if restante > 0.000001:
        raise ValueError("available lots do not cover requested quantity")
    return itens


def _tipo_separacao(pedido_item: PedidoItemPendente, quantidade: float) -> SeparacaoTipo:
    if abs(quantidade - pedido_item.quantidade_pendente) < 0.000001:
        return SeparacaoTipo.TOTAL
    return SeparacaoTipo.PARCIAL


def _movimentos(romaneio: Romaneio, tipo: MovimentoPATipo) -> tuple[MovimentoPA, ...]:
    return tuple(
        MovimentoPA(
            tipo=tipo,
            id_pedido=item.id_pedido,
            produto=item.produto,
            lote=item.lote,
            quantidade=item.quantidade,
            romaneio_numero=romaneio.numero,
        )
        for item in romaneio.itens
    )


def _evento(action: str, romaneio: Romaneio, metadata: dict[str, object]) -> EventoRomaneio:
    return EventoRomaneio(
        action=action,
        entity_type="romaneios",
        entity_id=romaneio.numero,
        metadata={"status": romaneio.status.value, **metadata},
    )


def _ensure_status(romaneio: Romaneio, allowed: set[RomaneioStatus], operation: str) -> None:
    if romaneio.status not in allowed:
        allowed_text = ", ".join(sorted(status.value for status in allowed))
        raise ValueError(f"cannot {operation} from status {romaneio.status.value}; expected {allowed_text}")
