import { randomUUID } from "node:crypto";

import Link from "next/link";

import {
  createClienteAddressAction,
  createClienteAction,
  createClienteContactAction,
  createClienteDocumentAction,
  createClienteEstablishmentAction,
  createClientePropertyAction,
  deactivateClienteAction,
  updateClienteAction,
  upsertClienteIdentificationAction,
} from "@/app/cadastros/actions";
import { ajustarLimiteCreditoAction } from "@/app/pedidos/actions";
import { internalValueLabel } from "@/lib/labels-ptbr";
import {
  UF_OPTIONS,
  cadastroStatusLabel,
  formatLegacyCode,
  formatLocation,
} from "@/lib/master-data-governance";
import type {
  LookupOption,
  MasterDataClient,
  MasterDataClientAddress,
  MasterDataClientContact,
  MasterDataClientCredit,
  MasterDataClientCreditEvent,
  MasterDataClientDocument,
  MasterDataClientEstablishment,
  MasterDataClientIdentification,
  MasterDataClientSeller,
  MasterDataProperty,
} from "@/lib/master-data";

const SECTIONS = [
  ["resumo", "Resumo"],
  ["identificacao", "Identificação"],
  ["documentos", "Documentos"],
  ["propriedades", "Estabelecimentos e propriedades"],
  ["enderecos", "Endereços"],
  ["contatos", "Contatos"],
  ["comercial", "Comercial"],
  ["credito", "Crédito"],
  ["historico", "Histórico"],
] as const;

type SectionKey = (typeof SECTIONS)[number][0];

type Props = {
  clientes: MasterDataClient[];
  propriedades: MasterDataProperty[];
  vinculos: MasterDataClientSeller[];
  pessoas: LookupOption[];
  documentos: MasterDataClientDocument[];
  contatos: MasterDataClientContact[];
  creditos: MasterDataClientCredit[];
  creditoEventos: MasterDataClientCreditEvent[];
  creditoGravacaoDisponivel: boolean;
  identificacoes: MasterDataClientIdentification[];
  estabelecimentos: MasterDataClientEstablishment[];
  enderecos: MasterDataClientAddress[];
  busca: string;
  clienteSelecionadoId: number | null;
  secao?: string;
  modoNovo: boolean;
  gravacaoDisponivel: boolean;
};

export function ClientesSection(props: Props) {
  const consulta = normalizeSearch(props.busca);
  const clientesFiltrados = props.clientes.filter(
    (cliente) => {
      const relatedValues = [
        cliente.nome,
        cliente.codigoLegado,
        cliente.cidade,
        cliente.uf,
        ...cliente.apelidos,
        ...props.propriedades
          .filter((item) => item.clienteId === cliente.id)
          .flatMap((item) => [item.nome, item.cnpj, item.cidade, item.uf]),
        ...props.documentos
          .filter((item) => item.clienteId === cliente.id)
          .flatMap((item) => [item.tipo, item.numero]),
        ...props.contatos
          .filter((item) => item.clienteId === cliente.id)
          .flatMap((item) => [item.nome, item.papel, item.telefone, item.email]),
        ...props.identificacoes
          .filter((item) => item.clienteId === cliente.id)
          .flatMap((item) => [item.razaoSocial, item.nomeFantasia, item.cnaePrincipal]),
        ...props.estabelecimentos
          .filter((item) => item.clienteId === cliente.id)
          .flatMap((item) => [item.nome, item.tipo]),
        ...props.enderecos
          .filter((item) => item.clienteId === cliente.id)
          .flatMap((item) => [item.cep, item.logradouro, item.numero, item.complemento, item.bairro, item.cidade, item.uf]),
      ];
      return !consulta || relatedValues.some((value) => matchesSearch(consulta, value));
    },
  );
  const cliente = props.modoNovo
    ? null
    : (props.clientes.find((item) => item.id === props.clienteSelecionadoId) ??
      null);
  const secao = SECTIONS.some(([key]) => key === props.secao)
    ? (props.secao as SectionKey)
    : "resumo";

  return (
    <section
      className="clients-workbench"
      aria-label="Gestão de clientes e propriedades"
    >
      <div className="clients-list-panel">
        <div className="clients-list-heading">
          <div>
            <span className="section-kicker">Consulta</span>
            <h2>Clientes</h2>
          </div>
          <span className="count-badge">{clientesFiltrados.length}</span>
        </div>
        {clientesFiltrados.length ? (
          <div className="clients-list" role="list">
            {clientesFiltrados.map((item) => (
              <Link
                aria-current={cliente?.id === item.id ? "page" : undefined}
                className={`client-list-item${cliente?.id === item.id ? " selected" : ""}`}
                href={`/cadastros?grupo=clientes&cliente=${item.id}`}
                key={item.id}
                role="listitem"
              >
                <span className="client-list-main">
                  <strong>{item.nome}</strong>
                  <small>{formatLocation(item.cidade, item.uf)}</small>
                </span>
                <span className={`status-chip status-${item.status}`}>
                  {cadastroStatusLabel(item.status)}
                </span>
                <span className="client-list-meta">
                  {
                    props.propriedades.filter(
                      (property) => property.clienteId === item.id,
                    ).length
                  }{" "}
                  propriedade(s)
                </span>
              </Link>
            ))}
          </div>
        ) : (
          <Empty
            title="Nenhum cliente encontrado"
            text="Revise nome, documento, município, UF, telefone ou e-mail."
          />
        )}
      </div>

      <div className="clients-detail-panel">
        {cliente ? (
          <ClientDetail {...props} cliente={cliente} secao={secao} />
        ) : props.modoNovo ? (
          <ClientForm gravacaoDisponivel={props.gravacaoDisponivel} />
        ) : (
          <Empty
            title="Selecione um cliente"
            text="Abra uma ficha para consultar e manter seus dados relacionados."
            action="Cadastrar cliente"
          />
        )}
      </div>
    </section>
  );
}

function ClientDetail(
  props: Props & { cliente: MasterDataClient; secao: SectionKey },
) {
  const { cliente, secao } = props;
  const byClient = <T extends { clienteId: number }>(rows: T[]) =>
    rows.filter((row) => row.clienteId === cliente.id);
  const propriedades = byClient(props.propriedades);
  const documentos = byClient(props.documentos);
  const contatos = byClient(props.contatos);
  const vinculos = byClient(props.vinculos);
  const estabelecimentos = byClient(props.estabelecimentos);
  const enderecos = byClient(props.enderecos);
  const credito = byClient(props.creditos)[0] ?? null;
  const creditoEventos = byClient(props.creditoEventos);
  const identificacao = byClient(props.identificacoes)[0] ?? null;
  const pessoas = new Map(props.pessoas.map((pessoa) => [pessoa.id, pessoa]));

  return (
    <div className="client-detail-stack">
      <section className="client-summary-panel">
        <div className="client-summary-heading">
          <div>
            <span className="section-kicker">Ficha cadastral</span>
            <h2>{cliente.nome}</h2>
            <p>{formatLocation(cliente.cidade, cliente.uf)}</p>
          </div>
          <span className={`status-chip status-${cliente.status}`}>
            {cadastroStatusLabel(cliente.status)}
          </span>
        </div>
        <dl className="client-summary-grid">
          <div>
            <dt>Documento principal</dt>
            <dd>{documentos[0]?.numero ?? "Não informado"}</dd>
          </div>
          <div>
            <dt>Propriedades</dt>
            <dd>{propriedades.length}</dd>
          </div>
          <div>
            <dt>Contatos ativos</dt>
            <dd>
              {contatos.filter((item) => item.status === "active").length}
            </dd>
          </div>
          <div>
            <dt>Limite disponível</dt>
            <dd>
              {credito ? money(credito.limiteDisponivel) : "Não definido"}
            </dd>
          </div>
        </dl>
      </section>

      <nav className="client-sections" aria-label="Seções da ficha do cliente">
        {SECTIONS.map(([key, label]) => (
          <Link
            key={key}
            href={`/cadastros?grupo=clientes&cliente=${cliente.id}&secao=${key}`}
            aria-current={secao === key ? "page" : undefined}
          >
            {label}
          </Link>
        ))}
      </nav>

      {secao === "resumo" ? (
        <Summary
          cliente={cliente}
          identificacao={identificacao}
          documentos={documentos}
          propriedades={propriedades}
          contatos={contatos}
          vinculos={vinculos}
          credito={credito}
        />
      ) : null}
      {secao === "identificacao" ? (
        <Identification
          cliente={cliente}
          identificacao={identificacao}
          gravacaoDisponivel={props.gravacaoDisponivel}
        />
      ) : null}
      {secao === "documentos" ? (
        <Documents
          cliente={cliente}
          documentos={documentos}
          gravacaoDisponivel={props.gravacaoDisponivel}
        />
      ) : null}
      {secao === "propriedades" ? (
        <Properties
          cliente={cliente}
          propriedades={propriedades}
          estabelecimentos={estabelecimentos}
          gravacaoDisponivel={props.gravacaoDisponivel}
        />
      ) : null}
      {secao === "enderecos" ? (
        <Addresses
          cliente={cliente}
          enderecos={enderecos}
          estabelecimentos={estabelecimentos}
          propriedades={propriedades}
          gravacaoDisponivel={props.gravacaoDisponivel}
        />
      ) : null}
      {secao === "contatos" ? (
        <Contacts
          cliente={cliente}
          contatos={contatos}
          propriedades={propriedades}
          gravacaoDisponivel={props.gravacaoDisponivel}
        />
      ) : null}
      {secao === "comercial" ? (
        <Commercial vinculos={vinculos} pessoas={pessoas} />
      ) : null}
      {secao === "credito" ? (
        <Credit
          cliente={cliente}
          credito={credito}
          eventos={creditoEventos}
          gravacaoDisponivel={props.creditoGravacaoDisponivel}
        />
      ) : null}
      {secao === "historico" ? <History cliente={cliente} /> : null}
    </div>
  );
}

function Summary({
  cliente,
  identificacao,
  documentos,
  propriedades,
  contatos,
  vinculos,
  credito,
}: {
  cliente: MasterDataClient;
  identificacao: MasterDataClientIdentification | null;
  documentos: MasterDataClientDocument[];
  propriedades: MasterDataProperty[];
  contatos: MasterDataClientContact[];
  vinculos: MasterDataClientSeller[];
  credito: MasterDataClientCredit | null;
}) {
  return (
    <section className="panel client-overview-grid">
      <Info
        title="Identificação"
        value={identificacao?.razaoSocial || cliente.nome}
        detail={
          identificacao
            ? `${personType(identificacao.tipoPessoa)} · ${internalValueLabel(identificacao.situacaoCadastral)}`
            : "Identificação empresarial pendente"
        }
      />
      <Info
        title="Documentos"
        value={`${documentos.length} registrado(s)`}
        detail={
          documentos
            .map((item) => `${item.tipo.toUpperCase()} ${item.numero}`)
            .join(" · ") || "Nenhum documento"
        }
      />
      <Info
        title="Operação"
        value={`${propriedades.length} propriedade(s)`}
        detail={`${contatos.length} contato(s) · ${vinculos.length} vínculo(s)`}
      />
      <Info
        title="Crédito"
        value={credito ? money(credito.limiteDisponivel) : "Não definido"}
        detail={
          credito
            ? internalValueLabel(credito.statusCredito)
            : "Administrado pelo Financeiro"
        }
      />
    </section>
  );
}

function Identification({
  cliente,
  identificacao,
  gravacaoDisponivel,
}: {
  cliente: MasterDataClient;
  identificacao: MasterDataClientIdentification | null;
  gravacaoDisponivel: boolean;
}) {
  return (
    <section className="panel">
      <header className="panel-header">
        <div>
          <span className="section-kicker">Dados empresariais</span>
          <h3>Identificação</h3>
        </div>
      </header>
      <form
        action={upsertClienteIdentificationAction}
        className="client-section-form"
      >
        <input type="hidden" name="cliente_id" value={cliente.id} />
        <label>
          Tipo de pessoa
          <select
            name="tipo_pessoa"
            defaultValue={identificacao?.tipoPessoa ?? "juridica"}
          >
            <option value="fisica">Pessoa física</option>
            <option value="juridica">Pessoa jurídica</option>
          </select>
        </label>
        <label>
          Razão social
          <input
            name="razao_social"
            defaultValue={identificacao?.razaoSocial ?? ""}
          />
        </label>
        <label>
          Nome fantasia
          <input
            name="nome_fantasia"
            defaultValue={identificacao?.nomeFantasia ?? ""}
          />
        </label>
        <label>
          Situação cadastral
          <select
            name="situacao_cadastral"
            defaultValue={identificacao?.situacaoCadastral ?? "nao_verificada"}
          >
            <option value="ativa">Ativa</option>
            <option value="inativa">Inativa</option>
            <option value="suspensa">Suspensa</option>
            <option value="baixada">Baixada</option>
            <option value="nao_verificada">Não verificada</option>
          </select>
        </label>
        <label>
          Data de abertura
          <input
            type="date"
            name="data_abertura"
            defaultValue={identificacao?.dataAbertura ?? ""}
          />
        </label>
        <label>
          CNAE principal
          <input
            name="cnae_principal"
            defaultValue={identificacao?.cnaePrincipal ?? ""}
          />
        </label>
        <label>
          Regime tributário
          <input
            name="regime_tributario"
            defaultValue={identificacao?.regimeTributario ?? ""}
          />
        </label>
        <label>
          Condição de contribuinte
          <input
            name="condicao_contribuinte"
            defaultValue={identificacao?.condicaoContribuinte ?? ""}
          />
        </label>
        <label>
          Fonte da informação
          <select
            name="fonte_informacao"
            defaultValue={identificacao?.fonteInformacao ?? "informado_cliente"}
          >
            <option value="informado_cliente">Informado pelo cliente</option>
            <option value="documento">Documento apresentado</option>
            <option value="excel_legado">Excel legado</option>
            <option value="consulta_futura">Consulta externa futura</option>
          </select>
        </label>
        <label>
          Data da consulta
          <input
            type="date"
            name="data_consulta"
            defaultValue={identificacao?.dataConsulta ?? ""}
          />
        </label>
        <label className="wide-field">
          Motivo da alteração
          <textarea name="motivo" required rows={2} />
        </label>
        <button className="primary-button" disabled={!gravacaoDisponivel}>
          Salvar identificação
        </button>
      </form>
    </section>
  );
}

function Documents({
  cliente,
  documentos,
  gravacaoDisponivel,
}: {
  cliente: MasterDataClient;
  documentos: MasterDataClientDocument[];
  gravacaoDisponivel: boolean;
}) {
  return (
    <Section
      title="Documentos"
      rows={documentos.map(
        (item) => `${item.tipo.toUpperCase()} · ${item.numero}`,
      )}
    >
      <form
        action={createClienteDocumentAction}
        className="inline-governed-form"
      >
        <input type="hidden" name="cliente_id" value={cliente.id} />
        <select name="tipo" aria-label="Tipo de documento">
          <option value="cpf">CPF</option>
          <option value="cnpj">CNPJ</option>
          <option value="ie">Inscrição estadual</option>
          <option value="outro">Outro</option>
        </select>
        <input name="numero" placeholder="Número" required />
        <input name="motivo" placeholder="Origem ou motivo" required />
        <button disabled={!gravacaoDisponivel}>Adicionar</button>
      </form>
    </Section>
  );
}

function Contacts({
  cliente,
  contatos,
  propriedades,
  gravacaoDisponivel,
}: {
  cliente: MasterDataClient;
  contatos: MasterDataClientContact[];
  propriedades: MasterDataProperty[];
  gravacaoDisponivel: boolean;
}) {
  return (
    <Section
      title="Contatos"
      rows={contatos.map(
        (item) =>
          `${item.nome} · ${item.papel} · ${item.telefone || item.email || "sem contato"}`,
      )}
    >
      <form action={createClienteContactAction} className="client-section-form">
        <input type="hidden" name="cliente_id" value={cliente.id} />
        <label>
          Nome
          <input name="nome" required />
        </label>
        <label>
          Papel
          <input
            name="papel"
            placeholder="Compras, financeiro, proprietário"
            required
          />
        </label>
        <label>
          Telefone
          <input name="telefone" inputMode="tel" />
        </label>
        <label>
          E-mail
          <input name="email" type="email" />
        </label>
        <label>
          Propriedade
          <select name="propriedade_id">
            <option value="">Geral do cliente</option>
            {propriedades.map((item) => (
              <option key={item.id} value={item.id}>
                {item.nome}
              </option>
            ))}
          </select>
        </label>
        <button className="primary-button" disabled={!gravacaoDisponivel}>
          Adicionar contato
        </button>
      </form>
    </Section>
  );
}

function Properties({
  cliente,
  propriedades,
  estabelecimentos,
  gravacaoDisponivel,
}: {
  cliente: MasterDataClient;
  propriedades: MasterDataProperty[];
  estabelecimentos: MasterDataClientEstablishment[];
  gravacaoDisponivel: boolean;
}) {
  return (
    <>
      <Section
        title="Propriedades rurais"
        rows={propriedades.map(
          (item) => `${item.nome} · ${formatLocation(item.cidade, item.uf)}`,
        )}
      >
        <form
          action={createClientePropertyAction}
          className="inline-governed-form"
        >
          <input type="hidden" name="cliente_id" value={cliente.id} />
          <input name="nome" placeholder="Nome da propriedade" required />
          <input name="cnpj" placeholder="CNPJ, se houver" />
          <input name="cidade" placeholder="Município" />
          <select name="uf" aria-label="UF">
            <option value="">UF</option>
            {UF_OPTIONS.map((uf) => (
              <option key={uf}>{uf}</option>
            ))}
          </select>
          <button disabled={!gravacaoDisponivel}>Adicionar</button>
        </form>
      </Section>
      <Section
        title="Estabelecimentos"
        rows={estabelecimentos.map(
          (item) => `${item.nome} · ${establishmentType(item.tipo)}`,
        )}
      >
        <form
          action={createClienteEstablishmentAction}
          className="inline-governed-form"
        >
          <input type="hidden" name="cliente_id" value={cliente.id} />
          <input name="nome" placeholder="Nome do estabelecimento" required />
          <select name="tipo">
            <option value="matriz">Matriz</option>
            <option value="filial">Filial</option>
            <option value="loja">Loja</option>
            <option value="revenda">Revenda</option>
            <option value="unidade_operacional">Unidade operacional</option>
          </select>
          <button disabled={!gravacaoDisponivel}>Adicionar</button>
        </form>
      </Section>
    </>
  );
}

function Addresses({
  cliente,
  enderecos,
  estabelecimentos,
  propriedades,
  gravacaoDisponivel,
}: {
  cliente: MasterDataClient;
  enderecos: MasterDataClientAddress[];
  estabelecimentos: MasterDataClientEstablishment[];
  propriedades: MasterDataProperty[];
  gravacaoDisponivel: boolean;
}) {
  return (
    <Section
      title="Endereços"
      rows={enderecos.map(
        (item) =>
          `${addressType(item.tipo)} · ${item.logradouro}, ${item.numero || "s/n"} · ${formatLocation(item.cidade, item.uf)}`,
      )}
    >
      <form action={createClienteAddressAction} className="client-section-form">
        <input type="hidden" name="cliente_id" value={cliente.id} />
        <label>
          Tipo
          <select name="tipo">
            <option value="fiscal">Fiscal</option>
            <option value="cobranca">Cobrança</option>
            <option value="entrega">Entrega</option>
            <option value="correspondencia">Correspondência</option>
          </select>
        </label>
        <label>
          CEP
          <input name="cep" inputMode="numeric" />
        </label>
        <label>
          Logradouro
          <input name="logradouro" required />
        </label>
        <label>
          Número
          <input name="numero" />
        </label>
        <label>
          Complemento
          <input name="complemento" />
        </label>
        <label>
          Bairro
          <input name="bairro" />
        </label>
        <label>
          Município
          <input name="cidade" required />
        </label>
        <label>
          UF
          <select name="uf" required>
            {UF_OPTIONS.map((uf) => (
              <option key={uf}>{uf}</option>
            ))}
          </select>
        </label>
        <label>
          Estabelecimento
          <select name="estabelecimento_id">
            <option value="">Não vinculado</option>
            {estabelecimentos.map((item) => (
              <option key={item.id} value={item.id}>
                {item.nome}
              </option>
            ))}
          </select>
        </label>
        <label>
          Propriedade
          <select name="propriedade_id">
            <option value="">Não vinculada</option>
            {propriedades.map((item) => (
              <option key={item.id} value={item.id}>
                {item.nome}
              </option>
            ))}
          </select>
        </label>
        <button className="primary-button" disabled={!gravacaoDisponivel}>
          Adicionar endereço
        </button>
      </form>
    </Section>
  );
}

function Commercial({
  vinculos,
  pessoas,
}: {
  vinculos: MasterDataClientSeller[];
  pessoas: Map<number, LookupOption>;
}) {
  return (
    <Section
      title="Responsáveis comerciais"
      rows={vinculos.map(
        (item) =>
          `${pessoas.get(item.pessoaId)?.label ?? "Pessoa não localizada"} · ${formatValidity(item.vigenciaInicio, item.vigenciaFim)}`,
      )}
    >
      <p className="muted">
        Novos vínculos são realizados pelo fluxo governado de Pessoas e áreas
        comerciais.
      </p>
    </Section>
  );
}
function Credit({
  cliente,
  credito,
  eventos,
  gravacaoDisponivel,
}: {
  cliente: MasterDataClient;
  credito: MasterDataClientCredit | null;
  eventos: MasterDataClientCreditEvent[];
  gravacaoDisponivel: boolean;
}) {
  return (
    <div className="client-credit-stack" id="credito-cliente">
      <Section
        title="Crédito atual"
        rows={
          credito
            ? [
                `Disponível: ${money(credito.limiteDisponivel)}`,
                `Manual: ${credito.limiteManual === null ? "Não definido" : money(credito.limiteManual)}`,
                `Calculado: ${credito.limiteCalculado === null ? "Não definido" : money(credito.limiteCalculado)}`,
                `Situação: ${internalValueLabel(credito.statusCredito)}`,
                `Motivo: ${credito.motivo || "Não informado"}`,
                `Última revisão: ${formatDateTime(credito.updatedAt)}`,
              ]
            : []
        }
      >
        <p className="notice-panel">
          O limite pertence ao Financeiro. Toda alteração exige alçada,
          justificativa e gera um evento auditado; o cadastro do cliente não é
          alterado diretamente.
        </p>
        {gravacaoDisponivel ? (
          <form className="client-section-form credit-adjustment-form" action={ajustarLimiteCreditoAction}>
            <input name="idempotency_key" type="hidden" value={randomUUID()} />
            <input name="cliente_id" type="hidden" value={cliente.id} />
            <input
              name="return_to"
              type="hidden"
              value={`/cadastros?grupo=clientes&cliente=${cliente.id}&secao=credito`}
            />
            <label>
              Novo limite manual
              <input
                defaultValue={credito?.limiteManual ?? credito?.limiteDisponivel ?? ""}
                inputMode="decimal"
                min="0"
                name="limite_novo"
                placeholder="0,00"
                required
              />
            </label>
            <label className="wide-field">
              Justificativa
              <textarea
                minLength={10}
                name="justificativa_limite"
                placeholder="Explique a análise e a razão da alteração"
                required
                rows={3}
              />
            </label>
            <button className="primary-button" type="submit">Registrar novo limite</button>
          </form>
        ) : (
          <div className="shell-state shell-state-permission compact-state">
            <h3>Alteração restrita</h3>
            <p>Você pode consultar o crédito, mas não possui alçada para alterar o limite.</p>
          </div>
        )}
      </Section>
      <Section
        title="Histórico de crédito"
        rows={eventos.map(
          (evento) =>
            `${internalValueLabel(evento.tipoEvento)} em ${formatDateTime(evento.createdAt)} · ${evento.limiteAnterior === null ? "Sem limite anterior" : money(evento.limiteAnterior)} → ${money(evento.limiteNovo)} · ${evento.justificativa}`,
        )}
      >
        <p className="muted">O histórico é imutável e acompanha cada decisão financeira registrada.</p>
      </Section>
    </div>
  );
}
function History({ cliente }: { cliente: MasterDataClient }) {
  return (
    <Section
      title="Histórico"
      rows={[
        `Cadastro ${cadastroStatusLabel(cliente.status)}`,
        `Código legado: ${formatLegacyCode(cliente.codigoLegado)}`,
        `${cliente.apelidos.length} apelido(s) ou grafia(s) histórica(s)`,
      ]}
    >
      <p className="muted">
        Eventos detalhados permanecem preservados na auditoria e serão
        apresentados conforme a permissão do usuário.
      </p>
    </Section>
  );
}

function ClientForm({
  gravacaoDisponivel,
  cliente,
}: {
  gravacaoDisponivel: boolean;
  cliente?: MasterDataClient;
}) {
  const editing = Boolean(cliente);
  return (
    <section
      className="panel form-panel client-form-panel"
      id="cadastro-cliente"
    >
      <header className="panel-header">
        <div>
          <span className="section-kicker">
            {editing ? "Edição auditada" : "Novo cadastro"}
          </span>
          <h2>{editing ? "Dados principais" : "Cadastrar cliente"}</h2>
        </div>
      </header>
      <form action={editing ? updateClienteAction : createClienteAction}>
        {cliente ? (
          <input name="cliente_id" type="hidden" value={cliente.id} />
        ) : null}
        <div className="form-grid client-form-grid">
          <label className="wide-field">
            Nome principal
            <input name="nome" defaultValue={cliente?.nome} required />
          </label>
          <label>
            Código legado
            <input
              name="codigo_legado"
              defaultValue={cliente?.codigoLegado ?? ""}
            />
          </label>
          <label>
            UF
            <select name="uf" defaultValue={cliente?.uf ?? "SP"}>
              {UF_OPTIONS.map((uf) => (
                <option key={uf}>{uf}</option>
              ))}
            </select>
          </label>
          <label className="wide-field">
            Município
            <input name="cidade" defaultValue={cliente?.cidade} required />
          </label>
          <label className="wide-field">
            Apelidos
            <input
              name="apelidos"
              defaultValue={cliente?.apelidos.join("; ")}
            />
          </label>
          <label className="wide-field">
            Motivo
            <textarea name="motivo" required rows={2} />
          </label>
        </div>
        <button className="primary-button" disabled={!gravacaoDisponivel}>
          Salvar alterações
        </button>
      </form>
      {cliente && cliente.status !== "inactive" ? (
        <details className="danger-zone">
          <summary>Desativar cliente</summary>
          <form action={deactivateClienteAction}>
            <input name="cliente_id" type="hidden" value={cliente.id} />
            <textarea name="motivo" required />
            <button disabled={!gravacaoDisponivel}>Desativar</button>
          </form>
        </details>
      ) : null}
    </section>
  );
}

function Section({
  title,
  rows,
  children,
}: {
  title: string;
  rows: string[];
  children?: React.ReactNode;
}) {
  return (
    <section className="panel client-record-section">
      <header className="panel-header">
        <h3>{title}</h3>
        <span className="count-badge">{rows.length}</span>
      </header>
      {rows.length ? (
        <div className="client-record-list">
          {rows.map((row, index) => (
            <div key={`${row}-${index}`}>{row}</div>
          ))}
        </div>
      ) : (
        <div className="empty-state">Nenhum registro.</div>
      )}
      {children}
    </section>
  );
}
function Info({
  title,
  value,
  detail,
}: {
  title: string;
  value: string;
  detail: string;
}) {
  return (
    <article>
      <span>{title}</span>
      <strong>{value}</strong>
      <small>{detail}</small>
    </article>
  );
}
function Empty({
  title,
  text,
  action,
}: {
  title: string;
  text: string;
  action?: string;
}) {
  return (
    <div className="shell-state shell-state-empty compact-state">
      <h3>{title}</h3>
      <p>{text}</p>
      {action ? (
        <Link
          className="primary-button"
          href="/cadastros?grupo=clientes&modo=novo#cadastro-cliente"
        >
          {action}
        </Link>
      ) : null}
    </div>
  );
}
function money(value: number) {
  return new Intl.NumberFormat("pt-BR", {
    style: "currency",
    currency: "BRL",
  }).format(value);
}
function personType(value: string) {
  return value === "fisica" ? "Pessoa física" : "Pessoa jurídica";
}
function establishmentType(value: string) {
  return (
    {
      matriz: "Matriz",
      filial: "Filial",
      loja: "Loja",
      revenda: "Revenda",
      unidade_operacional: "Unidade operacional",
    }[value] ?? "Estabelecimento"
  );
}
function addressType(value: string) {
  return (
    {
      fiscal: "Fiscal",
      cobranca: "Cobrança",
      entrega: "Entrega",
      correspondencia: "Correspondência",
    }[value] ?? "Endereço"
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

function formatDateTime(value: string) {
  const date = new Date(value);
  return Number.isNaN(date.getTime())
    ? "Data não informada"
    : new Intl.DateTimeFormat("pt-BR", { dateStyle: "short", timeStyle: "short" }).format(date);
}

function normalizeSearch(value: string | null | undefined): string {
  return (value ?? "")
    .normalize("NFD")
    .replace(/[\u0300-\u036f]/g, "")
    .toLocaleLowerCase("pt-BR")
    .trim();
}

function matchesSearch(query: string, value: string | null | undefined): boolean {
  const normalizedValue = normalizeSearch(value);
  if (!normalizedValue) return false;
  const compactQuery = query.replace(/[^a-z0-9]/g, "");
  const compactValue = normalizedValue.replace(/[^a-z0-9]/g, "");
  return normalizedValue.includes(query) || Boolean(compactQuery && compactValue.includes(compactQuery));
}
