import Link from "next/link";

import {
  addRomaneioItemAction,
  cancelRomaneioAction,
  confirmRomaneioAction,
  createRomaneioAction,
  reserveRomaneioPaLotAction,
  reverseRomaneioAction
} from "@/app/romaneios/actions";
import {
  getRomaneioDashboard,
  type RomaneioItem,
  type RomaneioLookupOption,
  type RomaneioLookups,
  type RomaneioPendingItem,
  type RomaneioRecord
} from "@/lib/romaneios";
import { getRuntimeStatus } from "@/lib/runtime";

type SearchParams = Record<string, string | string[] | undefined>;

export default async function RomaneiosPage({ searchParams }: { searchParams?: SearchParams | Promise<SearchParams> }) {
  const params = searchParams ? await searchParams : {};
  const runtime = getRuntimeStatus();
  const dashboard = await getRomaneioDashboard();
  const result = singleValue(params.result);
  const formMessage = messageForResult(result);

  return (
    <main className="app-shell">
      <header className="topbar">
        <div className="brand">
          <strong>Elite System</strong>
          <span>Romaneio</span>
        </div>
        <nav className="topnav" aria-label="Modulos principais">
          <Link href="/">Inicio</Link>
          <a href="/modulos">Modulos</a>
          <a href="/cadastros">Cadastros</a>
          <a href="/pedidos">Pedidos</a>
          <a href="/kanban">Kanban</a>
          <a href="/importacao-xml">XML MP</a>
          <a href="/producao">Producao</a>
          <a href="/romaneios" aria-current="page">
            Romaneio
          </a>
          <a href="/relatorios">Relatorios</a>
          <a href="/seguranca">Seguranca</a>
          <a href="/login">Login</a>
        </nav>
      </header>

      <aside className={`db-banner ${runtime.isOperationalDatabase ? "operational" : ""}`}>
        <strong>{runtime.databaseLabel}</strong>
        <span>{runtime.databaseWarning}</span>
        <span className="pill">{runtime.databaseMode}</span>
      </aside>

      <section className="workspace dashboard-workspace">
        <div className="dashboard-header">
          <div>
            <span className="eyebrow">baixa PA controlada</span>
            <h1>Romaneio e separacao por lote</h1>
            <p className="muted">
              Pedido aberto nao baixa estoque. Romaneio reserva lote PA em separacao e confirma a baixa apenas no
              fechamento.
            </p>
          </div>
          <div className="toolbar-actions" aria-label="Acoes de romaneio">
            <a className="secondary-button" href="#novo-romaneio">
              Novo romaneio
            </a>
            <a className="secondary-button" href="#reservar-lote">
              Reservar lote
            </a>
            <a className="primary-button" href="#romaneios">
              Operar
            </a>
          </div>
        </div>

        <LookupDatalists lookups={dashboard.lookups} />

        <section className="kpi-grid" aria-label="Resumo romaneio">
          <article className="kpi-card accent-blue">
            <span>Pedidos com pendencia</span>
            <strong>{valueOrDash(dashboard.metrics.pedidosComPendencia)}</strong>
            <p>{valueOrDash(dashboard.metrics.itensPendentes)} item(ns) com saldo a separar.</p>
          </article>
          <article className="kpi-card accent-amber">
            <span>Em rascunho</span>
            <strong>{valueOrDash(dashboard.metrics.romaneiosRascunho)}</strong>
            <p>Ainda sem baixa de estoque.</p>
          </article>
          <article className="kpi-card accent-green">
            <span>Em separacao</span>
            <strong>{valueOrDash(dashboard.metrics.romaneiosSeparacao)}</strong>
            <p>Com lote reservado ou aguardando completar reserva.</p>
          </article>
          <article className="kpi-card accent-red">
            <span>Qtd pendente</span>
            <strong>{valueOrDash(dashboard.metrics.quantidadePendente)}</strong>
            <p>Saldo agregado dos itens pendentes carregados.</p>
          </article>
        </section>

        {dashboard.error ? (
          <section className="notice-panel warning" role="status">
            <strong>Conexao pendente</strong>
            <span>{dashboard.error}</span>
          </section>
        ) : null}

        {formMessage ? (
          <section className={`notice-panel ${formMessage.kind}`} role="status">
            <strong>{formMessage.title}</strong>
            <span>{formMessage.detail}</span>
          </section>
        ) : null}

        <section className="two-column">
          <section className="panel form-panel" id="novo-romaneio" aria-labelledby="novo-romaneio-title">
            <div className="panel-header">
              <h2 id="novo-romaneio-title">Novo romaneio</h2>
              <span className="pill">sem baixa</span>
            </div>
            <form action={createRomaneioAction}>
              <div className="form-grid">
                <label className="wide-field">
                  Item pendente do pedido
                  <input name="pedido_item_id" list="romaneio-pending-items-options" placeholder="Buscar item pendente" required />
                </label>
                <label>
                  Separacao
                  <select name="tipo_separacao" defaultValue="parcial">
                    <option value="parcial">parcial</option>
                    <option value="total">total</option>
                  </select>
                </label>
                <label>
                  Quantidade
                  <input name="quantidade_romaneada" inputMode="decimal" required />
                </label>
                <label className="full-field">
                  Observacao
                  <input name="observacao" placeholder="Opcional" />
                </label>
              </div>
              <div className="form-footer">
                <span>Cria cabecalho e primeiro item. Use adicionar item para romaneio com varios produtos.</span>
                <button className="primary-button" type="submit">
                  Criar romaneio
                </button>
              </div>
            </form>
          </section>

          <section className="panel form-panel" id="adicionar-item" aria-labelledby="adicionar-item-title">
            <div className="panel-header">
              <h2 id="adicionar-item-title">Adicionar item</h2>
              <span className="pill">multi-item</span>
            </div>
            <form action={addRomaneioItemAction}>
              <div className="form-grid">
                <label className="wide-field">
                  Romaneio aberto
                  <input name="romaneio_id" list="romaneios-abertos-options" placeholder="Buscar romaneio" required />
                </label>
                <label className="wide-field">
                  Item pendente
                  <input name="pedido_item_id" list="romaneio-pending-items-options" placeholder="Mesmo pedido do romaneio" required />
                </label>
                <label>
                  Quantidade
                  <input name="quantidade_romaneada" inputMode="decimal" required />
                </label>
                <label className="wide-field">
                  Observacao
                  <input name="observacao" placeholder="Opcional" />
                </label>
              </div>
              <div className="form-footer">
                <span>Permite varios itens no mesmo romaneio, preservando o pedido vinculado.</span>
                <button className="primary-button" type="submit">
                  Adicionar item
                </button>
              </div>
            </form>
          </section>
        </section>

        <section className="two-column">
          <section className="panel form-panel" id="reservar-lote" aria-labelledby="reservar-lote-title">
            <div className="panel-header">
              <h2 id="reservar-lote-title">Reservar lote PA</h2>
              <span className="pill">multilote</span>
            </div>
            <form action={reserveRomaneioPaLotAction}>
              <div className="form-grid">
                <label className="wide-field">
                  Item do romaneio
                  <input name="romaneio_item_id" list="romaneio-items-abertos-options" placeholder="Buscar item" required />
                </label>
                <label className="wide-field">
                  Lote PA
                  <input name="lote_pa_id" list="lotes-pa-options" placeholder="Buscar lote disponivel" required />
                </label>
                <label>
                  Quantidade
                  <input name="quantidade_reservada" inputMode="decimal" placeholder="opcional" />
                </label>
                <label className="wide-field">
                  Observacao
                  <input name="observacao" placeholder="Opcional" />
                </label>
              </div>
              <div className="form-footer">
                <span>A reserva reduz disponibilidade, mas a baixa fisica so ocorre ao confirmar o romaneio.</span>
                <button className="primary-button" type="submit">
                  Reservar
                </button>
              </div>
            </form>
          </section>

          <section className="panel" aria-labelledby="pendencias-title">
            <div className="panel-header">
              <h2 id="pendencias-title">Itens pendentes</h2>
              <span className="pill">{dashboard.pendingItems.length} item(ns)</span>
            </div>
            {dashboard.pendingItems.length > 0 ? (
              <div className="module-list">
                {dashboard.pendingItems.slice(0, 10).map((item) => (
                  <PendingItemCard key={item.pedidoItemId} item={item} />
                ))}
              </div>
            ) : (
              <div className="empty-state">
                <strong>Sem pendencias carregadas</strong>
                <span>Pedidos abertos com saldo a separar aparecerao aqui.</span>
              </div>
            )}
          </section>
        </section>

        <section className="panel" id="romaneios" aria-labelledby="romaneios-title">
          <div className="panel-header">
            <h2 id="romaneios-title">Romaneios recentes</h2>
            <span className="pill">{dashboard.romaneios.length} registro(s)</span>
          </div>
          {dashboard.romaneios.length > 0 ? (
            <div className="romaneio-list">
              {dashboard.romaneios.slice(0, 18).map((romaneio) => (
                <RomaneioCard key={romaneio.id} romaneio={romaneio} />
              ))}
            </div>
          ) : (
            <div className="empty-state">
              <strong>Sem romaneios</strong>
              <span>Crie um romaneio a partir de um item pendente de pedido.</span>
            </div>
          )}
        </section>

        <section className="panel" aria-labelledby="lotes-pa-title">
          <div className="panel-header">
            <h2 id="lotes-pa-title">Lotes PA disponiveis</h2>
            <span className="pill">{dashboard.availableLots.length} lote(s)</span>
          </div>
          {dashboard.availableLots.length > 0 ? (
            <div className="table-scroll">
              <table className="data-table">
                <thead>
                  <tr>
                    <th>Lote</th>
                    <th>Produto</th>
                    <th>Status</th>
                    <th>Saldo</th>
                    <th>Reservado</th>
                    <th>Disponivel</th>
                    <th>Validade</th>
                  </tr>
                </thead>
                <tbody>
                  {dashboard.availableLots.slice(0, 80).map((lot) => (
                    <tr key={lot.id}>
                      <td>
                        <strong>{lot.codigoLote}</strong>
                        <span className="table-subtext">id {lot.id}</span>
                      </td>
                      <td>{lot.itemLabel}</td>
                      <td>
                        <span className={`status-chip ${lot.status}`}>{lot.status}</span>
                      </td>
                      <td>{numberOrDash(lot.saldoFisico)}</td>
                      <td>{numberOrDash(lot.quantidadeReservada)}</td>
                      <td>{numberOrDash(lot.saldoDisponivel)}</td>
                      <td>{lot.dataValidade ?? "-"}</td>
                    </tr>
                  ))}
                </tbody>
              </table>
            </div>
          ) : (
            <div className="empty-state">
              <strong>Sem lote PA carregado</strong>
              <span>Lotes disponiveis aparecem apos producao ou entrada PA.</span>
            </div>
          )}
        </section>
      </section>
    </main>
  );
}

function PendingItemCard({ item }: { item: RomaneioPendingItem }) {
  return (
    <article className="module-card">
      <div className="module-card-main">
        <h3>{item.codigoPedido}</h3>
        <span>{item.clienteNome}</span>
      </div>
      <div className="module-card-meta">
        <span>pendente</span>
        <strong>{numberOrDash(item.quantidadePendente)}</strong>
      </div>
      <p>{item.itemLabel}</p>
      <div className="tag-row">
        <span className="tag">pedido: {numberOrDash(item.quantidadePedido)}</span>
        <span className="tag">confirmado: {numberOrDash(item.quantidadeConfirmada)}</span>
        <span className="tag">separacao: {numberOrDash(item.quantidadeEmSeparacao)}</span>
      </div>
    </article>
  );
}

function RomaneioCard({ romaneio }: { romaneio: RomaneioRecord }) {
  const canConfirm = romaneio.status === "draft" || romaneio.status === "separacao";
  const canCancel = romaneio.status === "draft" || romaneio.status === "separacao";
  const canReverse = romaneio.status === "confirmado";

  return (
    <article className={`romaneio-card romaneio-${romaneio.status}`}>
      <div className="romaneio-header">
        <div>
          <h3>{romaneio.codigoRomaneio}</h3>
          <p>{romaneio.pedidoLabel}</p>
        </div>
        <div className="romaneio-meta">
          <span className={`status-chip ${romaneio.status}`}>{romaneio.status}</span>
          <strong>{romaneio.tipoSeparacao}</strong>
        </div>
      </div>
      <div className="tag-row">
        <span className="tag">cliente: {romaneio.clienteNome}</span>
        <span className="tag">data: {romaneio.dataRomaneio}</span>
        <span className="tag">itens: {romaneio.items.length}</span>
      </div>

      <section className="romaneio-subsection">
        <div className="romaneio-subsection-title">
          <strong>Itens</strong>
          <span>romaneado x reservado</span>
        </div>
        {romaneio.items.length > 0 ? (
          <div className="romaneio-item-list">
            {romaneio.items.map((item) => (
              <RomaneioItemRow key={item.id} item={item} />
            ))}
          </div>
        ) : (
          <div className="empty-state compact-empty">
            <strong>Sem item</strong>
            <span>Adicione itens pendentes ao romaneio.</span>
          </div>
        )}
      </section>

      {romaneio.movements.length > 0 ? (
        <section className="romaneio-subsection">
          <div className="romaneio-subsection-title">
            <strong>Movimentos PA</strong>
            <span>{romaneio.movements.length} movimento(s)</span>
          </div>
          <div className="tag-row">
            {romaneio.movements.slice(0, 8).map((movement) => (
              <span className="tag" key={movement.id}>
                {movement.tipoMovimento}: {numberOrDash(movement.quantidade)} / {movement.loteLabel}
              </span>
            ))}
          </div>
        </section>
      ) : null}

      <div className="romaneio-actions">
        {canConfirm ? (
          <form className="compact-action-form" action={confirmRomaneioAction}>
            <input type="hidden" name="romaneio_id" value={romaneio.id} />
            <input name="observacao" placeholder="Observacao da confirmacao" />
            <button className="primary-button" type="submit">
              Confirmar
            </button>
          </form>
        ) : null}
        {canCancel ? (
          <form className="compact-action-form" action={cancelRomaneioAction}>
            <input type="hidden" name="romaneio_id" value={romaneio.id} />
            <input name="motivo" placeholder="Motivo do cancelamento" required />
            <button className="secondary-button" type="submit">
              Cancelar
            </button>
          </form>
        ) : null}
        {canReverse ? (
          <form className="compact-action-form" action={reverseRomaneioAction}>
            <input type="hidden" name="romaneio_id" value={romaneio.id} />
            <input name="motivo" placeholder="Motivo do estorno" required />
            <button className="secondary-button" type="submit">
              Estornar
            </button>
          </form>
        ) : null}
      </div>
    </article>
  );
}

function RomaneioItemRow({ item }: { item: RomaneioItem }) {
  return (
    <div className="romaneio-item-row">
      <div>
        <strong>{item.itemLabel}</strong>
        <span>
          item {item.id} / lote {item.lotePaRef ?? "-"}
        </span>
      </div>
      <span className={`status-chip ${item.status}`}>{item.status}</span>
      <div className="tag-row">
        <span className="tag">romaneado: {numberOrDash(item.quantidadeRomaneada)}</span>
        <span className="tag">reservado: {numberOrDash(item.quantidadeReservada)}</span>
        {item.reservations.map((reservation) => (
          <span className="tag" key={reservation.id}>
            {reservation.loteLabel}: {numberOrDash(reservation.quantidadeReservada)} / {reservation.status}
          </span>
        ))}
      </div>
    </div>
  );
}

function LookupDatalists({ lookups }: { lookups: RomaneioLookups }) {
  return (
    <>
      <LookupDatalist id="romaneio-pending-items-options" options={lookups.pendingItems} />
      <LookupDatalist id="romaneios-abertos-options" options={lookups.romaneiosAbertos} />
      <LookupDatalist id="romaneio-items-abertos-options" options={lookups.romaneioItemsAbertos} />
      <LookupDatalist id="lotes-pa-options" options={lookups.lotesPa} />
    </>
  );
}

function LookupDatalist({ id, options }: { id: string; options: RomaneioLookupOption[] }) {
  return (
    <datalist id={id}>
      {options.map((option) => (
        <option key={`${id}-${option.id}-${option.label}`} value={lookupValue(option)} />
      ))}
    </datalist>
  );
}

function lookupValue(option: RomaneioLookupOption): string {
  return option.detail ? `${option.id} | ${option.label} | ${option.detail}` : `${option.id} | ${option.label}`;
}

function singleValue(value: string | string[] | undefined): string | undefined {
  return Array.isArray(value) ? value[0] : value;
}

function valueOrDash(value: number | null): string {
  return value === null ? "sem conexao" : numberOrDash(value);
}

function numberOrDash(value: number | null): string {
  if (value === null) {
    return "-";
  }
  return new Intl.NumberFormat("pt-BR", { maximumFractionDigits: 4 }).format(value);
}

function messageForResult(result: string | undefined): { kind: "ok" | "warning"; title: string; detail: string } | null {
  if (!result) {
    return null;
  }
  const messages: Record<string, { kind: "ok" | "warning"; title: string; detail: string }> = {
    romaneio_created: {
      kind: "ok",
      title: "Romaneio criado",
      detail: "O romaneio foi criado em rascunho, sem baixa de estoque."
    },
    romaneio_item_added: {
      kind: "ok",
      title: "Item adicionado",
      detail: "O item foi incluido no romaneio sem movimentar PA."
    },
    lot_reserved: {
      kind: "ok",
      title: "Lote reservado",
      detail: "A reserva foi registrada. A baixa fisica ainda depende da confirmacao."
    },
    romaneio_confirmed: {
      kind: "ok",
      title: "Romaneio confirmado",
      detail: "A baixa de PA foi registrada por lote reservado."
    },
    romaneio_cancelled: {
      kind: "ok",
      title: "Romaneio cancelado",
      detail: "Reservas ativas foram liberadas antes da confirmacao."
    },
    romaneio_reversed: {
      kind: "ok",
      title: "Romaneio estornado",
      detail: "A reversao auditada devolveu o saldo ao lote PA."
    },
    not_configured: {
      kind: "warning",
      title: "Supabase nao configurado",
      detail: "Configure o banco antes de operar romaneios."
    },
    missing_romaneio_required: {
      kind: "warning",
      title: "Romaneio incompleto",
      detail: "Informe item pendente, separacao e quantidade."
    },
    missing_add_item_required: {
      kind: "warning",
      title: "Item incompleto",
      detail: "Informe romaneio, item do pedido e quantidade."
    },
    missing_reservation_required: {
      kind: "warning",
      title: "Reserva incompleta",
      detail: "Informe item do romaneio e lote PA."
    },
    duplicated_item: {
      kind: "warning",
      title: "Item duplicado",
      detail: "Este item ja existe neste romaneio."
    },
    exceeds_pending: {
      kind: "warning",
      title: "Quantidade excede pendente",
      detail: "A quantidade romaneada nao pode ultrapassar o saldo do pedido."
    },
    reservation_mismatch: {
      kind: "warning",
      title: "Reserva nao fecha",
      detail: "A soma das reservas precisa fechar a quantidade romaneada antes de confirmar."
    },
    insufficient_stock: {
      kind: "warning",
      title: "Saldo PA insuficiente",
      detail: "O lote escolhido nao tem disponibilidade suficiente."
    },
    lot_product_mismatch: {
      kind: "warning",
      title: "Lote incompativel",
      detail: "O lote PA precisa ser do mesmo produto/embalagem do item."
    },
    invalid_status: {
      kind: "warning",
      title: "Status nao permite",
      detail: "O status atual do pedido, romaneio ou lote nao permite esta acao."
    },
    permission_denied: {
      kind: "warning",
      title: "Alcada bloqueada",
      detail: "O usuario atual nao tem permissao para esta acao."
    },
    save_failed: {
      kind: "warning",
      title: "Falha ao salvar",
      detail: "A acao nao foi concluida. Verifique banco, permissao e logs."
    }
  };
  return messages[result] ?? messages.save_failed;
}
