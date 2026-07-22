import Link from "next/link";

import { ClientesSection } from "@/app/cadastros/clientes-section";
import { PessoasSection } from "@/app/cadastros/pessoas-section";
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
  const selectedPersonId = positiveInteger(singleValue(params.pessoa));
  const newClientMode = activeGroup?.key === "clientes" && singleValue(params.modo) === "novo";
  const newPersonMode = activeGroup?.key === "pessoas" && singleValue(params.modo) === "novo";
  const visibleGroups = query
    ? CADASTRO_GROUPS.filter((group) => `${group.title} ${group.description}`.toLocaleLowerCase("pt-BR").includes(query))
    : CADASTRO_GROUPS;

  return (
    <main className="app-shell">
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
                <Link className="cadastros-group-card" href={groupHref(group.key)} key={group.key}>
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
            contatos={dashboard.clienteContatos}
            creditos={dashboard.clienteCreditos}
            documentos={dashboard.clienteDocumentos}
            enderecos={dashboard.clienteEnderecos}
            estabelecimentos={dashboard.clienteEstabelecimentos}
            gravacaoDisponivel={runtime.supabaseConfigured}
            identificacoes={dashboard.clienteIdentificacoes}
            modoNovo={newClientMode}
            pessoas={lookups.pessoasComerciais}
            propriedades={dashboard.propriedades}
            secao={singleValue(params.secao) ?? undefined}
            vinculos={dashboard.clienteVendedores}
          />
        ) : null}

        {activeGroup?.key === "pessoas" ? (
          <PessoasSection
            areas={dashboard.areasComerciais}
            busca={singleValue(params.busca) ?? ""}
            filtroPapel={singleValue(params.papel) ?? ""}
            filtroSituacao={singleValue(params.situacao) ?? ""}
            gravacaoDisponivel={runtime.supabaseConfigured}
            modoNovo={newPersonMode}
            papeis={dashboard.pessoaPapeis}
            pessoaSelecionadaId={selectedPersonId}
            pessoas={dashboard.pessoas}
            vinculosAreas={dashboard.pessoaAreas}
          />
        ) : null}

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
              <Link className="primary-button" href="/cadastros?grupo=pessoas">Ver entregadores</Link>
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
    pessoas: "/cadastros?grupo=pessoas&modo=novo#cadastro-pessoa",
    "materias-primas": "/cadastros/materias-primas#nova-materia-prima",
    produtos: "/cadastros/produtos#novo-produto",
    embalagens: "/cadastros/embalagens#nova-embalagem",
    logistica: "#",
    tecnicos: "/cadastros/tecnicos",
    validacao: "#validacao"
  };
  return hrefs[group];
}

function groupHref(group: CadastroGroupKey): string {
  const canonicalRoutes: Partial<Record<CadastroGroupKey, string>> = {
    "materias-primas": "/cadastros/materias-primas",
    produtos: "/cadastros/produtos",
    embalagens: "/cadastros/embalagens",
    tecnicos: "/cadastros/tecnicos"
  };
  return canonicalRoutes[group] ?? `/cadastros?grupo=${group}`;
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
      detail: "O cadastro foi preservado para consulta e deixou de participar de novas operações."
    },
    pessoa_reactivated: {
      kind: "ok",
      title: "Pessoa reativada",
      detail: "O mesmo cadastro voltou a ficar ativo; vínculos encerrados permaneceram históricos."
    },
    pessoa_area_linked: {
      kind: "ok",
      title: "Área comercial vinculada",
      detail: "O vínculo temporal foi registrado com autoria e justificativa."
    },
    pessoa_area_closed: {
      kind: "ok",
      title: "Vínculo encerrado",
      detail: "A vigência foi encerrada sem excluir o histórico comercial."
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
