import Link from "next/link";

import {
  createConversaoUnidadeMpAction,
  createEmbalagemAction,
  createMateriaPrimaAction,
  createPessoaComercialAction,
  createProdutoBaseAction,
  createProdutoEmbalagemAction
} from "@/app/cadastros/actions";
import { ClientesSection } from "@/app/cadastros/clientes-section";
import { getMasterDataDashboard } from "@/lib/master-data";
import { getRuntimeStatus } from "@/lib/runtime";

type SearchParams = Record<string, string | string[] | undefined>;

type CadastroGroupKey =
  | "clientes"
  | "pessoas"
  | "materias-primas"
  | "produtos"
  | "embalagens"
  | "logistica"
  | "tecnicos"
  | "validacao";

const CADASTRO_GROUPS: Array<{
  key: CadastroGroupKey;
  title: string;
  description: string;
  action: string;
}> = [
  { key: "clientes", title: "Clientes e propriedades", description: "Identidade, fazendas, enderecos, contatos e credito.", action: "Novo cliente" },
  { key: "pessoas", title: "Pessoas e vinculos comerciais", description: "Vendedores, agentes, gerentes, tecnicos e papeis.", action: "Nova pessoa" },
  { key: "materias-primas", title: "Materias-primas e insumos", description: "SKU, unidade, densidade, estoque e dados regulatorios.", action: "Nova materia-prima" },
  { key: "produtos", title: "Produtos e apresentacoes", description: "Produto-base, validade e combinacao produto + embalagem.", action: "Novo produto" },
  { key: "embalagens", title: "Embalagens e conversoes", description: "Volumes, insumos de embalagem e conversoes de unidade.", action: "Nova embalagem" },
  { key: "logistica", title: "Veiculos e logistica", description: "Cadastros de apoio para entrega, carga e expedicao.", action: "Ver estrutura" },
  { key: "tecnicos", title: "Cadastros tecnicos", description: "Unidades, nutrientes, garantias e catalogos industriais.", action: "Abrir catalogos" },
  { key: "validacao", title: "Validacao e pendencias", description: "Duplicidades, revisoes e cadastros incompletos.", action: "Abrir fila" }
];

export default async function CadastrosPage({ searchParams }: { searchParams?: Promise<SearchParams> }) {
  const params = searchParams ? await searchParams : {};
  const runtime = getRuntimeStatus();
  const dashboard = await getMasterDataDashboard();
  const lookups = dashboard.lookups;
  const pendingCount = dashboard.validationIssues.length;
  const result = singleValue(params.result);
  const formMessage = messageForResult(result);
  const requestedGroup = singleValue(params.grupo);
  const activeGroup = CADASTRO_GROUPS.find((group) => group.key === requestedGroup) ?? null;
  const query = (singleValue(params.busca) ?? "").trim().toLocaleLowerCase("pt-BR");
  const selectedClientId = positiveInteger(singleValue(params.cliente));
  const newClientMode = singleValue(params.modo) === "novo";
  const visibleGroups = query
    ? CADASTRO_GROUPS.filter((group) => `${group.title} ${group.description}`.toLocaleLowerCase("pt-BR").includes(query))
    : CADASTRO_GROUPS;

  return (
    <main className="app-shell">
      <header className="topbar">
        <div className="brand">
          <strong>Elite System</strong>
          <span>Cadastros mestres</span>
        </div>
        <nav className="topnav" aria-label="Modulos principais">
          <Link href="/">Inicio</Link>
          <a href="/modulos">Modulos</a>
          <a href="/cadastros" aria-current="page">
            Cadastros
          </a>
          <a href="/pedidos">Pedidos</a>
          <a href="/kanban">Kanban</a>
          <a href="/importacao-xml">XML MP</a>
          <a href="/producao">Producao</a>
          <a href="/romaneios">Romaneio</a>
          <a href="/relatorios">Relatorios</a>
          <a href="/seguranca">Seguranca</a>
          <a href="/login">Login</a>
          <a href="#validacao">Validacao</a>
        </nav>
      </header>

      <aside className={`db-banner ${runtime.isOperationalDatabase ? "operational" : ""}`}>
        <strong>{runtime.databaseLabel}</strong>
        <span>{runtime.databaseWarning}</span>
        <span className="pill">{runtime.databaseMode}</span>
      </aside>

      <section className="workspace">
        <div className="cadastros-heading">
          <div>
            <span className="eyebrow">Dados mestres</span>
            <h1>{activeGroup?.title ?? "Cadastros"}</h1>
            <p className="muted">
              {activeGroup?.description ?? "Encontre, revise e mantenha os dados que sustentam toda a operacao Elite."}
            </p>
          </div>
          <div className="cadastros-heading-actions">
            {activeGroup ? <Link className="secondary-button" href="/cadastros">Visao geral</Link> : null}
            {activeGroup ? (
              <a className="primary-button" href={actionHref(activeGroup.key)}>{activeGroup.action}</a>
            ) : (
              <Link className="primary-button" href="/cadastros?grupo=clientes&modo=novo#cadastro-cliente">Novo cliente</Link>
            )}
          </div>
        </div>

        <form className="cadastros-search" action="/cadastros" method="get" role="search">
          {activeGroup ? <input type="hidden" name="grupo" value={activeGroup.key} /> : null}
          <label htmlFor="cadastros-search-input">Buscar nos cadastros</label>
          <div>
            <input id="cadastros-search-input" name="busca" defaultValue={singleValue(params.busca)} placeholder="Cliente, produto, materia-prima ou area" />
            <button className="secondary-button" type="submit">Buscar</button>
            {query ? <Link className="text-button" href={activeGroup ? `/cadastros?grupo=${activeGroup.key}` : "/cadastros"}>Limpar</Link> : null}
          </div>
        </form>

        <section className="cadastros-context" aria-label="Situacao dos cadastros">
          <div><strong>{dashboard.modules.length}</strong><span>cadastros monitorados</span></div>
          <div className={pendingCount > 0 ? "attention" : ""}><strong>{pendingCount}</strong><span>pendencias relevantes</span></div>
          <div><strong>{dashboard.source === "supabase" ? "Conectado" : "Indisponivel"}</strong><span>estado da consulta</span></div>
        </section>

        {dashboard.error ? (
          <section className="notice-panel" role="status">
            <strong>Cadastros temporariamente indisponíveis</strong>
            <span>Não foi possível carregar todos os dados. Tente novamente ou solicite análise ao administrador.</span>
          </section>
        ) : null}

        {formMessage ? (
          <section className={`notice-panel ${formMessage.kind}`} role="status">
            <strong>{formMessage.title}</strong>
            <span>{formMessage.detail}</span>
          </section>
        ) : null}

        {!activeGroup ? (
          <section className="cadastros-group-grid" aria-label="Areas de cadastro">
            {visibleGroups.map((group) => {
              const groupCount = countForGroup(group.key, dashboard.metrics);
              return (
                <Link className="cadastros-group-card" href={`/cadastros?grupo=${group.key}`} key={group.key}>
                  <span className="cadastros-group-icon" aria-hidden="true">{groupInitials(group.key)}</span>
                  <span className="cadastros-group-copy"><strong>{group.title}</strong><small>{group.description}</small></span>
                  <span className="cadastros-group-meta">{group.key === "validacao" ? `${pendingCount} pendente(s)` : groupCount}</span>
                </Link>
              );
            })}
            {visibleGroups.length === 0 ? (
              <div className="shell-state shell-state-empty cadastros-no-results">
                <span className="shell-state-label">Sem resultados</span>
                <h2>Nenhuma area encontrada</h2>
                <p>Revise a busca ou limpe o filtro para ver todos os grupos.</p>
                <div className="shell-state-actions"><Link className="secondary-button" href="/cadastros">Limpar busca</Link></div>
              </div>
            ) : null}
          </section>
        ) : null}

        {activeGroup?.key === "validacao" ? (
          <section className="panel cadastros-focused-panel" id="validacao" aria-labelledby="validacao-title">
            <div className="panel-header">
              <h2 id="validacao-title">Fila de validacao</h2>
              <span className="pill">{pendingCount} pendente(s)</span>
            </div>
            {dashboard.validationIssues.length > 0 ? (
              <div className="issue-list">
                {dashboard.validationIssues.map((issue) => (
                  <article className={`issue-row ${issue.severity}`} key={issue.id}>
                    <div>
                      <strong>{issue.entity}</strong>
                      <span>{issue.entity_key ?? "sem chave"}</span>
                    </div>
                    <p>{issue.message}</p>
                    <span className="tag">{issue.code}</span>
                  </article>
                ))}
              </div>
            ) : (
              <div className="empty-state">
                <strong>Nenhum alerta carregado</strong>
                <span>
                  Nao ha duplicidades, revisoes de SKU ou cadastros incompletos aguardando tratamento.
                </span>
              </div>
            )}
          </section>
        ) : null}

        {activeGroup?.key === "clientes" ? (
          <ClientesSection
            busca={singleValue(params.busca) ?? ""}
            clienteSelecionadoId={selectedClientId}
            clientes={dashboard.clientes}
            gravacaoDisponivel={runtime.supabaseConfigured}
            modoNovo={newClientMode}
            pessoas={lookups.pessoasComerciais}
            propriedades={dashboard.propriedades}
            vinculos={dashboard.clienteVendedores}
          />
        ) : null}

        {activeGroup?.key === "pessoas" ? <section className="panel form-panel cadastros-focused-panel" aria-labelledby="nova-pessoa-title">
          <div className="panel-header">
            <h2 id="nova-pessoa-title">Nova pessoa comercial</h2>
            <span className="pill">{runtime.supabaseConfigured ? "gravacao ativa" : "aguardando Supabase"}</span>
          </div>
          <form action={createPessoaComercialAction} id="nova-pessoa">
            <div className="form-grid">
              <label>
                Nome
                <input name="nome" placeholder="Nome da pessoa" required />
              </label>
              <label>
                Codigo legado
                <input name="codigo_legado" placeholder="Codigo, se houver" />
              </label>
              <label>
                Tipo comercial
                <select name="tipo_comercial" defaultValue="vendedor_direto_elite">
                  <option value="funcionario_elite">funcionario_elite</option>
                  <option value="agente_vinculado">agente_vinculado</option>
                  <option value="agente_direto_elite">agente_direto_elite</option>
                  <option value="vendedor_direto_elite">vendedor_direto_elite</option>
                  <option value="tecnico_campo">tecnico_campo</option>
                  <option value="entregador">entregador</option>
                  <option value="gerente">gerente</option>
                  <option value="vendedor_gerente">vendedor_gerente</option>
                </select>
              </label>
              <label>
                Status
                <select name="status" defaultValue="active">
                  <option value="active">active</option>
                  <option value="pending_review">pending_review</option>
                  <option value="inactive">inactive</option>
                </select>
              </label>
              <label>
                Vendedor responsavel
                <select name="vendedor_responsavel_id" defaultValue="">
                  <option value="">Nenhum</option>
                  {lookups.pessoasComerciais.map((option) => (
                    <option key={option.id} value={option.id}>{option.label} - {option.detail}</option>
                  ))}
                </select>
              </label>
              <label className="wide-field">
                Apelidos
                <input name="apelidos" placeholder="Separar por virgula, ponto e virgula ou linha" />
              </label>
              <label className="wide-field">
                Grafias incorretas
                <input name="grafias_incorretas" placeholder="Grafias usadas historicamente" />
              </label>
            </div>
            <fieldset className="check-grid">
              <legend>Papeis</legend>
              <label>
                <input name="papeis" type="checkbox" value="vendedor" defaultChecked />
                Vendedor
              </label>
              <label>
                <input name="papeis" type="checkbox" value="agente" />
                Agente
              </label>
              <label>
                <input name="papeis" type="checkbox" value="gerente" />
                Gerente
              </label>
              <label>
                <input name="papeis" type="checkbox" value="tecnico_campo" />
                Tecnico campo
              </label>
              <label>
                <input name="papeis" type="checkbox" value="entregador" />
                Entregador
              </label>
              <label>
                <input name="papeis" type="checkbox" value="comissionado" defaultChecked />
                Comissionado
              </label>
            </fieldset>
            <div className="form-footer">
              <span>Entregador nao vira vendedor automaticamente; papeis ficam separados para auditoria.</span>
              <button className="primary-button" type="submit">
                Salvar pessoa
              </button>
            </div>
          </form>
        </section> : null}

        {activeGroup?.key === "materias-primas" ? <section className="panel form-panel cadastros-focused-panel" id="nova-mp" aria-labelledby="nova-mp-title">
          <div className="panel-header">
            <h2 id="nova-mp-title">Nova materia-prima</h2>
            <span className="pill">{runtime.supabaseConfigured ? "gravacao ativa" : "aguardando Supabase"}</span>
          </div>
          <form action={createMateriaPrimaAction}>
            <div className="form-grid">
              <label>
                Nome
                <input name="nome" placeholder="Nome da MP" required />
              </label>
              <label>
                SKU corrigido
                <input name="sku_corrigido" placeholder="Codigo unico" required />
              </label>
              <label>
                Codigo legado
                <input name="codigo_legado" placeholder="Codigo antigo, se houver" />
              </label>
              <label>
                Unidade base
                <input name="unidade_base_estoque" placeholder="KG" required />
              </label>
              <label>
                Status
                <select name="status" defaultValue="active">
                  <option value="active">active</option>
                  <option value="pending_review">pending_review</option>
                  <option value="inactive">inactive</option>
                </select>
              </label>
              <label>
                Tipo
                <input name="tipo" placeholder="Liquido, solido, embalagem..." />
              </label>
              <label>
                Densidade
                <input name="densidade" placeholder="1,20" inputMode="decimal" />
              </label>
              <label>
                Estoque minimo
                <input name="estoque_minimo" placeholder="0" inputMode="decimal" />
              </label>
              <label>
                NCM
                <input name="ncm" />
              </label>
              <label>
                IBAMA
                <input name="ibama" />
              </label>
              <label>
                Codigo ADS
                <input name="codigo_ads" />
              </label>
            </div>
            <div className="form-footer">
              <span>SKU corrigido passa a ser a chave unica operacional da materia-prima.</span>
              <button className="primary-button" type="submit">
                Salvar MP
              </button>
            </div>
          </form>
        </section> : null}

        {activeGroup?.key === "produtos" ? <section className="panel form-panel cadastros-focused-panel" id="novo-produto" aria-labelledby="novo-produto-title">
          <div className="panel-header">
            <h2 id="novo-produto-title">Novo produto-base</h2>
            <span className="pill">{runtime.supabaseConfigured ? "gravacao ativa" : "aguardando Supabase"}</span>
          </div>
          <form action={createProdutoBaseAction}>
            <div className="form-grid">
              <label>
                Codigo produto
                <input name="codigo_produto" placeholder="0001" required />
              </label>
              <label>
                Nome
                <input name="nome" placeholder="Nome do produto" required />
              </label>
              <label>
                Status
                <select name="status" defaultValue="active">
                  <option value="active">active</option>
                  <option value="pending_review">pending_review</option>
                  <option value="inactive">inactive</option>
                </select>
              </label>
              <label>
                Grupo
                <input name="grupo" placeholder="Linha ou familia" />
              </label>
              <label>
                Densidade kg/L
                <input name="densidade_kg_l" placeholder="1,20" inputMode="decimal" />
              </label>
              <label>
                Validade PA/PI em meses
                <input name="prazo_validade_meses" placeholder="12" inputMode="numeric" />
              </label>
              <label>
                Registro MAPA
                <input name="reg_mapa" />
              </label>
              <label>
                NCM
                <input name="ncm" />
              </label>
              <label>
                IBAMA
                <input name="ibama" />
              </label>
              <label>
                ADS
                <input name="ads" />
              </label>
            </div>
            <div className="form-footer">
              <span>Produto-base fica separado das embalagens; o item vendavel sera produto + embalagem.</span>
              <button className="primary-button" type="submit">
                Salvar produto
              </button>
            </div>
          </form>
        </section> : null}

        {activeGroup?.key === "embalagens" ? <section className="panel form-panel cadastros-focused-panel" id="nova-embalagem" aria-labelledby="nova-embalagem-title">
          <div className="panel-header">
            <h2 id="nova-embalagem-title">Nova embalagem</h2>
            <span className="pill">{runtime.supabaseConfigured ? "gravacao ativa" : "aguardando Supabase"}</span>
          </div>
          <form action={createEmbalagemAction}>
            <div className="form-grid">
              <label>
                Descricao
                <input name="descricao" placeholder="Balde 20L" required />
              </label>
              <label>
                Unidade
                <input name="unidade" placeholder="UN" required />
              </label>
              <label>
                Volume litros
                <input name="volume_litros" placeholder="20" inputMode="decimal" />
              </label>
              <label>
                Codigo legado
                <input name="codigo_legado" />
              </label>
              <label>
                Status
                <select name="status" defaultValue="active">
                  <option value="active">active</option>
                  <option value="pending_review">pending_review</option>
                  <option value="inactive">inactive</option>
                </select>
              </label>
              <label>
                MP vinculada
                <select name="materia_prima_id" defaultValue="">
                  <option value="">Nenhuma</option>
                  {lookups.materiasPrimas.map((option) => (
                    <option key={option.id} value={option.id}>{option.label} - {option.detail}</option>
                  ))}
                </select>
              </label>
              <label className="checkbox-line">
                <input name="controla_estoque" type="checkbox" value="1" />
                Controla estoque como insumo
              </label>
            </div>
            <div className="form-footer">
              <span>Embalagem pode ser insumo de MP e depois compor PA/PI.</span>
              <button className="primary-button" type="submit">
                Salvar embalagem
              </button>
            </div>
          </form>
        </section> : null}

        {activeGroup?.key === "produtos" ? <section className="panel form-panel cadastros-focused-panel" id="novo-item-vendavel" aria-labelledby="novo-item-vendavel-title">
          <div className="panel-header">
            <h2 id="novo-item-vendavel-title">Novo item vendavel</h2>
            <span className="pill">{runtime.supabaseConfigured ? "gravacao ativa" : "aguardando Supabase"}</span>
          </div>
          <form action={createProdutoEmbalagemAction}>
            <div className="form-grid">
              <label>
                Produto
                <select name="produto_id" defaultValue="" required>
                  <option value="">Selecione</option>
                  {lookups.produtos.map((option) => (
                    <option key={option.id} value={option.id}>{option.label} - {option.detail}</option>
                  ))}
                </select>
              </label>
              <label>
                Embalagem
                <select name="embalagem_id" defaultValue="" required>
                  <option value="">Selecione</option>
                  {lookups.embalagens.map((option) => (
                    <option key={option.id} value={option.id}>{option.label} - {option.detail}</option>
                  ))}
                </select>
              </label>
              <label>
                Codigo do item
                <input name="codigo_item" placeholder="0001-20L" required />
              </label>
              <label>
                Status
                <select name="status" defaultValue="active">
                  <option value="active">active</option>
                  <option value="pending_review">pending_review</option>
                  <option value="inactive">inactive</option>
                </select>
              </label>
            </div>
            <div className="form-footer">
              <span>Produto + embalagem passa a ser o item usado em pedido, faturamento e estoque PA.</span>
              <button className="primary-button" type="submit">
                Salvar item
              </button>
            </div>
          </form>
        </section> : null}

        {activeGroup?.key === "embalagens" ? <section className="panel form-panel cadastros-focused-panel" id="nova-conversao-mp" aria-labelledby="nova-conversao-mp-title">
          <div className="panel-header">
            <h2 id="nova-conversao-mp-title">Nova conversao de MP</h2>
            <span className="pill">{runtime.supabaseConfigured ? "gravacao ativa" : "aguardando Supabase"}</span>
          </div>
          <form action={createConversaoUnidadeMpAction}>
            <div className="form-grid">
              <label>
                Materia-prima
                <select name="materia_prima_id" defaultValue="" required>
                  <option value="">Selecione</option>
                  {lookups.materiasPrimas.map((option) => (
                    <option key={option.id} value={option.id}>{option.label} - {option.detail}</option>
                  ))}
                </select>
              </label>
              <label>
                Unidade origem
                <input name="unidade_origem" placeholder="SC" required />
              </label>
              <label>
                Unidade destino
                <input name="unidade_destino" placeholder="KG" required />
              </label>
              <label>
                Fator
                <input name="fator" placeholder="50" required inputMode="decimal" />
              </label>
              <label>
                Vigencia inicio
                <input name="vigencia_inicio" type="date" />
              </label>
              <label>
                Vigencia fim
                <input name="vigencia_fim" type="date" />
              </label>
            </div>
            <div className="form-footer">
              <span>Conversao define como XML/NF em outra unidade entra no estoque base da MP.</span>
              <button className="primary-button" type="submit">
                Salvar conversao
              </button>
            </div>
          </form>
        </section> : null}

        {activeGroup?.key === "tecnicos" ? (
          <section className="cadastros-destination-grid" aria-label="Catalogos tecnicos disponiveis">
            <Link href="/cadastros/unidades"><strong>Unidades e conversoes</strong><span>Padroes de medida usados em XML, estoque e formulas.</span></Link>
            <Link href="/cadastros/materias-primas"><strong>Materias-primas</strong><span>Edicao completa por identidade, SKU, tecnica e regulatorio.</span></Link>
            <Link href="/cadastros/embalagens"><strong>Embalagens</strong><span>Volumes e controle como insumo de estoque.</span></Link>
            <Link href="/cadastros/produtos"><strong>Produtos PA/PI</strong><span>Produto-base, validade e apresentacoes vendaveis.</span></Link>
            <Link href="/producao/garantias"><strong>Garantias</strong><span>Referencias MAPA e garantias dos lotes de MP.</span></Link>
            <Link href="/producao/formulas"><strong>Formulas</strong><span>Receitas de producao e documentacao tecnica.</span></Link>
          </section>
        ) : null}

        {activeGroup?.key === "logistica" ? (
          <section className="shell-state shell-state-empty cadastros-focused-state">
            <span className="shell-state-label">Estrutura em preparacao</span>
            <h2>Veiculos e logistica</h2>
            <p>Os vinculos de entregadores ja pertencem ao cadastro de pessoas. Veiculos e demais recursos logisticos ainda nao possuem tela operacional nesta central.</p>
            <div className="shell-state-actions">
              <Link className="primary-button" href="/cadastros?grupo=pessoas#nova-pessoa">Ver entregadores</Link>
              <Link className="secondary-button" href="/romaneios">Abrir romaneio</Link>
            </div>
          </section>
        ) : null}
      </section>
    </main>
  );
}

function actionHref(group: CadastroGroupKey): string {
  const hrefs: Record<CadastroGroupKey, string> = {
    clientes: "/cadastros?grupo=clientes&modo=novo#cadastro-cliente",
    pessoas: "#nova-pessoa",
    "materias-primas": "#nova-mp",
    produtos: "#novo-produto",
    embalagens: "#nova-embalagem",
    logistica: "#",
    tecnicos: "/cadastros/tecnicos",
    validacao: "#validacao"
  };
  return hrefs[group];
}

function groupInitials(group: CadastroGroupKey): string {
  const initials: Record<CadastroGroupKey, string> = {
    clientes: "CL",
    pessoas: "PV",
    "materias-primas": "MP",
    produtos: "PA",
    embalagens: "EM",
    logistica: "LG",
    tecnicos: "CT",
    validacao: "VP"
  };
  return initials[group];
}

function countForGroup(group: CadastroGroupKey, metrics: Array<{ moduleKey: string; count: number | null }>): string {
  const moduleKeys: Partial<Record<CadastroGroupKey, string[]>> = {
    clientes: ["clientes", "credito"],
    pessoas: ["pessoas"],
    "materias-primas": ["materias-primas"],
    produtos: ["produtos", "produto-embalagens"],
    embalagens: ["embalagens", "conversoes-mp"]
  };
  const counts = (moduleKeys[group] ?? []).map((key) => metrics.find((metric) => metric.moduleKey === key)?.count);
  if (counts.length === 0) return "Abrir";
  if (counts.some((count) => count === null || count === undefined)) return "Sem leitura";
  return `${counts.reduce<number>((total, count) => total + (count ?? 0), 0)} registro(s)`;
}

function singleValue(value: string | string[] | undefined): string | undefined {
  return Array.isArray(value) ? value[0] : value;
}

function positiveInteger(value: string | undefined): number | null {
  if (!value) return null;
  const parsed = Number(value);
  return Number.isInteger(parsed) && parsed > 0 ? parsed : null;
}

function messageForResult(result: string | undefined): { kind: "ok" | "warning"; title: string; detail: string } | null {
  if (!result) {
    return null;
  }
  const messages: Record<string, { kind: "ok" | "warning"; title: string; detail: string }> = {
    cliente_created: {
      kind: "ok",
      title: "Cliente cadastrado",
      detail: "O cadastro foi criado e já está disponível para consulta."
    },
    cliente_updated: {
      kind: "ok",
      title: "Cliente atualizado",
      detail: "As alterações foram salvas e o histórico da operação foi preservado."
    },
    cliente_deactivated: {
      kind: "ok",
      title: "Cliente desativado",
      detail: "O cadastro foi preservado para consulta e não poderá ser usado em novas operações."
    },
    pessoa_created: {
      kind: "ok",
      title: "Pessoa comercial salva",
      detail: "Cadastro criado via funcao auditavel com papeis separados para venda, entrega, gerencia e comissao."
    },
    pessoa_identity_updated: {
      kind: "ok",
      title: "Identidade atualizada",
      detail: "Nome, apelidos ou grafias foram editados com before/after em action_logs."
    },
    pessoa_role_updated: {
      kind: "ok",
      title: "Papel comercial atualizado",
      detail: "Papeis comerciais foram alterados com motivo padronizado e diff de adicionados/removidos."
    },
    pessoa_deactivated: {
      kind: "ok",
      title: "Pessoa desativada",
      detail: "Cadastro preservado como historico e marcado como inactive por funcao auditavel."
    },
    mp_created: {
      kind: "ok",
      title: "Materia-prima salva",
      detail: "Cadastro criado com SKU corrigido e validacao de unidade base."
    },
    mp_identity_updated: {
      kind: "ok",
      title: "Identidade de MP atualizada",
      detail: "Nome ou tipo da materia-prima foi alterado por eixo auditavel."
    },
    mp_sku_updated: {
      kind: "ok",
      title: "SKU de MP atualizado",
      detail: "Codigo operacional da materia-prima foi alterado com before/after."
    },
    mp_technical_updated: {
      kind: "ok",
      title: "Dados tecnicos atualizados",
      detail: "Unidade base ou densidade da MP foi alterada por RPC tecnica."
    },
    mp_stock_policy_updated: {
      kind: "ok",
      title: "Politica de estoque atualizada",
      detail: "Estoque minimo da materia-prima foi alterado por eixo proprio."
    },
    mp_regulatory_updated: {
      kind: "ok",
      title: "Dados regulatorios atualizados",
      detail: "NCM, IBAMA ou ADS foram alterados por RPC regulatoria."
    },
    mp_deactivated: {
      kind: "ok",
      title: "Materia-prima desativada",
      detail: "Cadastro preservado como historico e marcado como inactive por funcao auditavel."
    },
    produto_created: {
      kind: "ok",
      title: "Produto salvo",
      detail: "Produto-base criado para depois ser combinado com embalagens e receitas."
    },
    embalagem_created: {
      kind: "ok",
      title: "Embalagem salva",
      detail: "Embalagem criada com controle opcional de estoque como insumo."
    },
    item_vendavel_created: {
      kind: "ok",
      title: "Item vendavel salvo",
      detail: "Produto + embalagem criado como item operacional para pedido e estoque PA."
    },
    conversion_created: {
      kind: "ok",
      title: "Conversao salva",
      detail: "Conversao de unidade criada para entrada de MP em XML/NF e estoque base."
    },
    duplicated: {
      kind: "warning",
      title: "Cadastro duplicado",
      detail: "O codigo legado ou chave unica ja existe. Revise antes de tentar novamente."
    },
    invalid_status: {
      kind: "warning",
      title: "Situação inválida",
      detail: "Escolha uma das situações disponíveis no cadastro."
    },
    invalid_uf: {
      kind: "warning",
      title: "UF invalida",
      detail: "UF deve ter exatamente duas letras."
    },
    missing_required: {
      kind: "warning",
      title: "Campos obrigatorios",
      detail: "Nome, cidade e UF sao obrigatorios para cliente."
    },
    missing_person_required: {
      kind: "warning",
      title: "Campos obrigatorios",
      detail: "Nome e ao menos um papel sao obrigatorios para pessoa comercial."
    },
    missing_mp_required: {
      kind: "warning",
      title: "Campos obrigatorios",
      detail: "Nome, SKU corrigido e unidade base sao obrigatorios para materia-prima."
    },
    missing_product_required: {
      kind: "warning",
      title: "Campos obrigatorios",
      detail: "Codigo do produto e nome sao obrigatorios para produto-base."
    },
    missing_package_required: {
      kind: "warning",
      title: "Campos obrigatorios",
      detail: "Descricao e unidade sao obrigatorias para embalagem."
    },
    missing_sale_item_required: {
      kind: "warning",
      title: "Campos obrigatorios",
      detail: "Produto, embalagem e codigo do item sao obrigatorios."
    },
    missing_conversion_required: {
      kind: "warning",
      title: "Campos obrigatorios",
      detail: "Materia-prima, unidades de origem/destino e fator sao obrigatorios."
    },
    invalid_positive_number: {
      kind: "warning",
      title: "Numero invalido",
      detail: "Informe um numero maior que zero."
    },
    invalid_non_negative_number: {
      kind: "warning",
      title: "Numero invalido",
      detail: "Informe zero ou um numero positivo."
    },
    missing_package_stock_item: {
      kind: "warning",
      title: "MP vinculada obrigatoria",
      detail: "Embalagem com controle de estoque precisa apontar para uma materia-prima cadastrada."
    },
    invalid_unit_conversion: {
      kind: "warning",
      title: "Conversao invalida",
      detail: "Unidade de origem e unidade de destino precisam ser diferentes."
    },
    invalid_sku: {
      kind: "warning",
      title: "SKU invalido",
      detail: "SKU corrigido nao pode conter espacos."
    },
    invalid_ncm: {
      kind: "warning",
      title: "NCM invalido",
      detail: "NCM deve conter exatamente 8 digitos."
    },
    invalid_date_range: {
      kind: "warning",
      title: "Vigencia invalida",
      detail: "A data final nao pode ser anterior a data inicial."
    },
    invalid_commercial_type: {
      kind: "warning",
      title: "Tipo comercial invalido",
      detail: "Use um dos tipos comerciais aprovados no dicionario de cadastros."
    },
    missing_responsible_seller: {
      kind: "warning",
      title: "Vendedor responsavel obrigatorio",
      detail: "Agente vinculado precisa apontar para um vendedor responsavel Elite."
    },
    invalid_responsible_seller: {
      kind: "warning",
      title: "Vendedor responsavel invalido",
      detail: "Informe o ID numerico do vendedor responsavel."
    },
    invalid_role_reason: {
      kind: "warning",
      title: "Motivo invalido",
      detail: "Use um dos motivos padronizados para alterar papel comercial."
    },
    missing_role_reason_detail: {
      kind: "warning",
      title: "Detalhe obrigatorio",
      detail: "Quando o motivo for outro, descreva o motivo da alteracao."
    },
    not_configured: {
      kind: "warning",
      title: "Supabase nao configurado",
      detail: "Configure as variaveis de ambiente antes de gravar cadastros reais ou de teste."
    },
    permission_denied: {
      kind: "warning",
      title: "Permissao negada",
      detail: "Usuario precisa estar autenticado e autorizado para gravar cadastros."
    },
    save_failed: {
      kind: "warning",
      title: "Falha ao salvar",
      detail: "O cadastro não foi gravado. Tente novamente ou solicite análise ao administrador."
    }
  };
  return messages[result] ?? messages.save_failed;
}
