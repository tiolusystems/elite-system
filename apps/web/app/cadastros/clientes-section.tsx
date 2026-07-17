import Link from "next/link";

import {
  createClienteAction,
  deactivateClienteAction,
  updateClienteAction
} from "@/app/cadastros/actions";
import {
  UF_OPTIONS,
  cadastroStatusLabel,
  formatLegacyCode,
  formatLocation
} from "@/lib/master-data-governance";
import type {
  MasterDataClient,
  MasterDataClientSeller,
  MasterDataProperty,
  LookupOption
} from "@/lib/master-data";

type ClientesSectionProps = {
  clientes: MasterDataClient[];
  propriedades: MasterDataProperty[];
  vinculos: MasterDataClientSeller[];
  pessoas: LookupOption[];
  busca: string;
  clienteSelecionadoId: number | null;
  modoNovo: boolean;
  gravacaoDisponivel: boolean;
};

export function ClientesSection({
  clientes,
  propriedades,
  vinculos,
  pessoas,
  busca,
  clienteSelecionadoId,
  modoNovo,
  gravacaoDisponivel
}: ClientesSectionProps) {
  const consulta = busca.trim().toLocaleLowerCase("pt-BR");
  const clientesFiltrados = clientes.filter((cliente) => {
    if (!consulta) return true;
    return [cliente.nome, cliente.codigoLegado, cliente.cidade, cliente.uf, ...cliente.apelidos]
      .filter(Boolean)
      .some((value) => value!.toLocaleLowerCase("pt-BR").includes(consulta));
  });
  const clienteSelecionado = modoNovo
    ? null
    : clientes.find((cliente) => cliente.id === clienteSelecionadoId) ?? null;
  const propriedadesDoCliente = clienteSelecionado
    ? propriedades.filter((propriedade) => propriedade.clienteId === clienteSelecionado.id)
    : [];
  const vinculosDoCliente = clienteSelecionado
    ? vinculos.filter((vinculo) => vinculo.clienteId === clienteSelecionado.id && vinculo.status === "active")
    : [];
  const pessoasPorId = new Map(pessoas.map((pessoa) => [pessoa.id, pessoa]));

  return (
    <section className="clients-workbench" aria-label="Gestão de clientes e propriedades">
      <div className="clients-list-panel">
        <div className="clients-list-heading">
          <div>
            <span className="section-kicker">Consulta</span>
            <h2>Clientes</h2>
          </div>
          <span className="count-badge">{clientesFiltrados.length}</span>
        </div>

        {clientesFiltrados.length > 0 ? (
          <div className="clients-list" role="list">
            {clientesFiltrados.map((cliente) => {
              const selected = clienteSelecionado?.id === cliente.id;
              const propertyCount = propriedades.filter((property) => property.clienteId === cliente.id).length;
              return (
                <Link
                  aria-current={selected ? "page" : undefined}
                  className={`client-list-item${selected ? " selected" : ""}`}
                  href={`/cadastros?grupo=clientes&cliente=${cliente.id}`}
                  key={cliente.id}
                  role="listitem"
                >
                  <span className="client-list-main">
                    <strong>{cliente.nome}</strong>
                    <small>{formatLocation(cliente.cidade, cliente.uf)}</small>
                  </span>
                  <span className={`status-chip status-${cliente.status}`}>
                    {cadastroStatusLabel(cliente.status)}
                  </span>
                  <span className="client-list-meta">
                    {propertyCount === 1 ? "1 propriedade" : `${propertyCount} propriedades`}
                  </span>
                </Link>
              );
            })}
          </div>
        ) : (
          <div className="shell-state shell-state-empty compact-state">
            <span className="shell-state-label">Sem resultados</span>
            <h3>Nenhum cliente encontrado</h3>
            <p>Revise o nome, código, município ou UF usados na busca.</p>
            <div className="shell-state-actions">
              <Link className="secondary-button" href="/cadastros?grupo=clientes">Limpar busca</Link>
            </div>
          </div>
        )}
      </div>

      <div className="clients-detail-panel">
        {clienteSelecionado ? (
          <ClientDetail
            cliente={clienteSelecionado}
            propriedades={propriedadesDoCliente}
            vinculos={vinculosDoCliente}
            pessoasPorId={pessoasPorId}
            gravacaoDisponivel={gravacaoDisponivel}
          />
        ) : modoNovo ? (
          <ClientForm gravacaoDisponivel={gravacaoDisponivel} />
        ) : (
          <div className="shell-state shell-state-empty client-selection-state">
            <span className="shell-state-label">Visão detalhada</span>
            <h2>Selecione um cliente</h2>
            <p>Abra um cadastro para revisar dados, propriedades e vínculos comerciais.</p>
            <div className="shell-state-actions">
              <Link className="primary-button" href="/cadastros?grupo=clientes&modo=novo#cadastro-cliente">
                Cadastrar cliente
              </Link>
            </div>
          </div>
        )}
      </div>
    </section>
  );
}

function ClientForm({
  gravacaoDisponivel,
  cliente
}: {
  gravacaoDisponivel: boolean;
  cliente?: MasterDataClient;
}) {
  const editing = Boolean(cliente);
  return (
    <section className="panel form-panel client-form-panel" id="cadastro-cliente" aria-labelledby="cadastro-cliente-title">
      <div className="panel-header">
        <div>
          <span className="section-kicker">{editing ? "Edição auditada" : "Novo cadastro"}</span>
          <h2 id="cadastro-cliente-title">{editing ? "Dados do cliente" : "Cadastrar cliente"}</h2>
        </div>
        <span className="pill">{gravacaoDisponivel ? "Gravação disponível" : "Somente consulta"}</span>
      </div>
      <form action={editing ? updateClienteAction : createClienteAction}>
        {cliente ? <input name="cliente_id" type="hidden" value={cliente.id} /> : null}
        {!editing ? <input name="status" type="hidden" value="active" /> : null}
        <div className="form-grid client-form-grid">
          <label className="wide-field">
            Nome principal
            <input name="nome" defaultValue={cliente?.nome} placeholder="Nome ou razão social" required />
          </label>
          <label>
            Código legado
            <input name="codigo_legado" defaultValue={cliente?.codigoLegado ?? ""} placeholder="Opcional" />
          </label>
          <label>
            UF
            <select name="uf" defaultValue={cliente?.uf ?? "SP"} required>
              {UF_OPTIONS.map((uf) => <option key={uf} value={uf}>{uf}</option>)}
            </select>
          </label>
          <label className="wide-field">
            Município
            <input name="cidade" defaultValue={cliente?.cidade} placeholder="Município do cadastro" required />
            <small>Será relacionado ao catálogo municipal quando essa fonte governada estiver disponível.</small>
          </label>
          <label className="wide-field">
            Apelidos e grafias históricas
            <input
              name="apelidos"
              defaultValue={cliente?.apelidos.join("; ")}
              placeholder="Separe diferentes grafias por ponto e vírgula"
            />
          </label>
          {editing ? (
            <label className="wide-field">
              Motivo da alteração
              <textarea name="motivo" placeholder="Explique objetivamente o que está sendo corrigido" required rows={3} />
            </label>
          ) : null}
        </div>
        <div className="form-footer">
          <span>{editing ? "A alteração preserva o histórico e identifica o responsável." : "O cliente será criado como ativo e poderá ser revisado depois."}</span>
          <button className="primary-button" disabled={!gravacaoDisponivel} type="submit">
            {editing ? "Salvar alterações" : "Cadastrar cliente"}
          </button>
        </div>
      </form>
    </section>
  );
}

function ClientDetail({
  cliente,
  propriedades,
  vinculos,
  pessoasPorId,
  gravacaoDisponivel
}: {
  cliente: MasterDataClient;
  propriedades: MasterDataProperty[];
  vinculos: MasterDataClientSeller[];
  pessoasPorId: Map<number, LookupOption>;
  gravacaoDisponivel: boolean;
}) {
  return (
    <div className="client-detail-stack">
      <section className="client-summary-panel" aria-labelledby="cliente-selecionado-title">
        <div className="client-summary-heading">
          <div>
            <span className="section-kicker">Cliente selecionado</span>
            <h2 id="cliente-selecionado-title">{cliente.nome}</h2>
            <p>{formatLocation(cliente.cidade, cliente.uf)}</p>
          </div>
          <span className={`status-chip status-${cliente.status}`}>{cadastroStatusLabel(cliente.status)}</span>
        </div>
        <dl className="client-summary-grid">
          <div><dt>Código legado</dt><dd>{formatLegacyCode(cliente.codigoLegado)}</dd></div>
          <div><dt>Apelidos registrados</dt><dd>{cliente.apelidos.length || "Nenhum"}</dd></div>
          <div><dt>Propriedades</dt><dd>{propriedades.length}</dd></div>
          <div><dt>Vínculos comerciais</dt><dd>{vinculos.length}</dd></div>
        </dl>
      </section>

      <ClientForm cliente={cliente} gravacaoDisponivel={gravacaoDisponivel} />

      <section className="panel related-records-panel" aria-labelledby="propriedades-title">
        <div className="panel-header">
          <div>
            <span className="section-kicker">Relação por cliente</span>
            <h2 id="propriedades-title">Propriedades vinculadas</h2>
          </div>
          <span className="count-badge">{propriedades.length}</span>
        </div>
        {propriedades.length > 0 ? (
          <div className="related-record-list">
            {propriedades.map((propriedade) => (
              <article key={propriedade.id}>
                <div><strong>{propriedade.nome}</strong><span>{formatLocation(propriedade.cidade, propriedade.uf)}</span></div>
                <div><span>{propriedade.cnpj || "CNPJ não informado"}</span><span className={`status-chip status-${propriedade.status}`}>{cadastroStatusLabel(propriedade.status)}</span></div>
              </article>
            ))}
          </div>
        ) : (
          <div className="empty-state"><strong>Nenhuma propriedade vinculada</strong><span>O cliente continua válido sem propriedade. A inclusão depende do contrato auditado de propriedades.</span></div>
        )}
      </section>

      <section className="panel related-records-panel" aria-labelledby="vinculos-title">
        <div className="panel-header">
          <div>
            <span className="section-kicker">Responsabilidade comercial</span>
            <h2 id="vinculos-title">Vendedores e responsáveis</h2>
          </div>
          <span className="count-badge">{vinculos.length}</span>
        </div>
        {vinculos.length > 0 ? (
          <div className="related-record-list">
            {vinculos.map((vinculo) => {
              const pessoa = pessoasPorId.get(vinculo.pessoaId);
              return (
                <article key={vinculo.id}>
                  <div><strong>{pessoa?.label ?? "Pessoa não localizada"}</strong><span>{vinculo.propriedadeId ? "Vínculo específico da propriedade" : "Vínculo geral do cliente"}</span></div>
                  <div><span>{formatValidity(vinculo.vigenciaInicio, vinculo.vigenciaFim)}</span></div>
                </article>
              );
            })}
          </div>
        ) : (
          <div className="empty-state"><strong>Nenhum responsável vigente</strong><span>O vínculo será incluído quando o fluxo auditado de relacionamento estiver disponível.</span></div>
        )}
      </section>

      {cliente.status !== "inactive" ? (
        <details className="danger-zone">
          <summary>Desativar este cliente</summary>
          <form action={deactivateClienteAction}>
            <input name="cliente_id" type="hidden" value={cliente.id} />
            <label>Motivo da desativação<textarea name="motivo" required rows={3} /></label>
            <button className="secondary-button danger-button" disabled={!gravacaoDisponivel} type="submit">Desativar cliente</button>
          </form>
        </details>
      ) : null}
    </div>
  );
}

function formatValidity(start: string | null, end: string | null) {
  if (!start && !end) return "Vigência não informada";
  if (start && !end) return `Desde ${formatDate(start)}`;
  if (!start && end) return `Até ${formatDate(end)}`;
  return `${formatDate(start!)} a ${formatDate(end!)}`;
}

function formatDate(value: string) {
  const [year, month, day] = value.split("-");
  return `${day}/${month}/${year}`;
}
