import {
  confirmNfeItemMatchAction,
  generateMpLotFromNfeItemAction,
  ignoreNfeItemAction,
  importNfeXmlTextAction,
  stageNfeHeaderAction,
  stageNfeItemAction
} from "@/app/importacao-xml/actions";
import { LocalEntityLookup } from "@/app/corporate-search/local-entity-lookup";
import {
  getImportacaoXmlDashboard,
  type PendingXmlItem,
  type XmlLookupOption
} from "@/lib/importacao-xml";
import { getRuntimeStatus } from "@/lib/runtime";
import { internalValueLabel } from "@/lib/labels-ptbr";

type SearchParams = Record<string, string | string[] | undefined>;

export default async function ImportacaoXmlPage({ searchParams }: { searchParams?: Promise<SearchParams> }) {
  const params = searchParams ? await searchParams : {};
  const runtime = getRuntimeStatus();
  const dashboard = await getImportacaoXmlDashboard();
  const result = singleValue(params.result);
  const formMessage = messageForResult(result);

  return (
    <main className="app-shell">
      <section className="workspace dashboard-workspace">
        <div className="dashboard-header">
          <div>
            <span className="eyebrow">estoque MP auditavel</span>
            <h1>Importacao semiautomatica de NF XML</h1>
            <p className="muted">
              XML entra em conferencia, sugere MP candidata e so gera lote de MP depois de match e conversao auditados.
            </p>
          </div>
          <div className="toolbar-actions" aria-label="Acoes de importacao XML">
            <a className="secondary-button" href="#fila-xml">
              Fila
            </a>
            <a className="primary-button" href="#importar-xml">
              Importar XML
            </a>
          </div>
        </div>



        <section className="kpi-grid" aria-label="Resumo da importacao XML">
          <article className="kpi-card accent-blue">
            <span>NF XML</span>
            <strong>{valueOrDash(dashboard.metrics.notasXml)}</strong>
            <p>Cabecalhos importados para conferencia.</p>
          </article>
          <article className="kpi-card accent-amber">
            <span>Itens pendentes</span>
            <strong>{valueOrDash(dashboard.metrics.itensPendentes)}</strong>
            <p>Aguardam escolha de MP e conversao.</p>
          </article>
          <article className="kpi-card accent-green">
            <span>Lotes MP gerados</span>
            <strong>{valueOrDash(dashboard.metrics.lotesMpGerados)}</strong>
            <p>Entradas reais criadas apos conferencia.</p>
          </article>
          <article className="kpi-card accent-red">
            <span>Valor XML</span>
            <strong>{moneyOrDash(dashboard.metrics.valorXml)}</strong>
            <p>Soma das notas carregadas nesta visao.</p>
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
          <section className="panel form-panel" id="importar-xml" aria-labelledby="importar-xml-title">
            <div className="panel-header">
              <h2 id="importar-xml-title">Importar XML colado</h2>
              <span className="pill">{runtime.supabaseConfigured ? "staging ativo" : "aguardando Supabase"}</span>
            </div>
            <form action={importNfeXmlTextAction}>
              <div className="form-grid single-field-grid">
                <label className="wide-field full-field">
                  XML da NF-e
                  <textarea
                    className="text-area"
                    name="xml_text"
                    placeholder="Cole aqui o XML completo da NF-e de compra de insumos"
                    rows={14}
                    required
                  />
                </label>
              </div>
              <div className="form-footer">
                <span>Esta acao apenas estrutura a NF e sugere candidatos; nao movimenta estoque.</span>
                <button className="primary-button" type="submit">
                  Importar para conferencia
                </button>
              </div>
            </form>
          </section>

          <section className="panel" aria-labelledby="resumo-nfe-title">
            <div className="panel-header">
              <h2 id="resumo-nfe-title">NF XML recentes</h2>
              <span className="pill">{dashboard.summaries.length} registro(s)</span>
            </div>
            {dashboard.summaries.length > 0 ? (
              <div className="module-list">
                {dashboard.summaries.slice(0, 8).map((summary) => (
                  <article className="module-card" key={summary.nfeId}>
                    <div className="module-card-main">
                      <h3>{summary.numero ?? "sem numero"}</h3>
                      <span>{summary.emitenteNome ?? summary.emitenteCnpj ?? summary.chaveAcesso}</span>
                    </div>
                    <div className="module-card-meta">
                      <span>{internalValueLabel(summary.status)}</span>
                      <strong>{moneyOrDash(summary.valorTotalXml)}</strong>
                    </div>
                    <div className="tag-row">
                      <span className="tag">itens: {summary.totalItens}</span>
                      <span className="tag">pendentes: {summary.itensPendentesMatch}</span>
                      <span className="tag">lotes MP: {summary.itensComLoteMp}</span>
                    </div>
                  </article>
                ))}
              </div>
            ) : (
              <div className="empty-state">
                <strong>Nenhuma NF XML carregada</strong>
                <span>Quando Supabase estiver configurado, as notas importadas aparecerao aqui.</span>
              </div>
            )}
          </section>
        </section>

        <section className="two-column">
          <section className="panel form-panel" id="cabecalho-nfe" aria-labelledby="cabecalho-nfe-title">
            <div className="panel-header">
              <h2 id="cabecalho-nfe-title">Cabecalho manual</h2>
              <span className="pill">contingencia</span>
            </div>
            <form action={stageNfeHeaderAction}>
              <div className="form-grid">
                <label className="wide-field">
                  Chave de acesso
                  <input name="chave_acesso" placeholder="44 digitos" required />
                </label>
                <label>
                  Numero
                  <input name="numero" placeholder="nNF" />
                </label>
                <label>
                  Serie
                  <input name="serie" placeholder="serie" />
                </label>
                <label>
                  Emissao
                  <input name="data_emissao" type="date" />
                </label>
                <label>
                  CNPJ emitente
                  <input name="emitente_cnpj" placeholder="00.000.000/0000-00" />
                </label>
                <label className="wide-field">
                  Emitente
                  <input name="emitente_nome" placeholder="Fornecedor" />
                </label>
              </div>
              <div className="form-footer">
                <span>Use quando o XML nao puder ser colado inteiro.</span>
                <button className="primary-button" type="submit">
                  Salvar cabecalho
                </button>
              </div>
            </form>
          </section>

          <section className="panel form-panel" id="item-nfe" aria-labelledby="item-nfe-title">
            <div className="panel-header">
              <h2 id="item-nfe-title">Item manual</h2>
              <span className="pill">sem estoque</span>
            </div>
            <form action={stageNfeItemAction}>
              <div className="form-grid">
                <LocalEntityLookup
                  className="wide-field"
                  name="nfe_id"
                  label="NF XML"
                  placeholder="Abra a lista ou pesquise a NF"
                  options={dashboard.nfeOptions}
                  defaultValue={null}
                  required
                />
                <label>
                  Item
                  <input name="numero_item" inputMode="numeric" placeholder="1" required />
                </label>
                <label>
                  Codigo fornecedor
                  <input name="codigo_fornecedor" placeholder="cProd" />
                </label>
                <label className="wide-field">
                  Descricao
                  <input name="descricao_fornecedor" placeholder="xProd" required />
                </label>
                <label>
                  NCM
                  <input name="ncm" placeholder="NCM" />
                </label>
                <label>
                  CFOP
                  <input name="cfop" placeholder="CFOP" />
                </label>
                <label>
                  Unidade XML
                  <input name="unidade_xml" placeholder="KG, TON, T" required />
                </label>
                <label>
                  Quantidade XML
                  <input name="quantidade_xml" inputMode="decimal" required />
                </label>
                <label>
                  Valor total
                  <input name="valor_total" inputMode="decimal" placeholder="0,00" />
                </label>
                <label>
                  Lote fornecedor
                  <input name="lote_fornecedor" placeholder="se houver" />
                </label>
                <label>
                  Fabricacao
                  <input name="data_fabricacao" type="date" />
                </label>
                <label>
                  Validade
                  <input name="data_validade" type="date" />
                </label>
              </div>
              <div className="form-footer">
                <span>Item manual tambem entra como pendente de conferencia.</span>
                <button className="primary-button" type="submit">
                  Salvar item
                </button>
              </div>
            </form>
          </section>
        </section>

        <section className="panel lookup-surface" id="fila-xml" aria-labelledby="fila-xml-title">
          <div className="panel-header">
            <h2 id="fila-xml-title">Fila de conferencia</h2>
            <span className="pill">{dashboard.pendingItems.length} pendente(s)</span>
          </div>
          {dashboard.pendingItems.length > 0 ? (
            <div className="xml-review-list">
              {dashboard.pendingItems.map((item) => (
                <XmlReviewCard key={item.itemId} item={item} materiasPrimas={dashboard.materiasPrimas} />
              ))}
            </div>
          ) : (
            <div className="empty-state">
              <strong>Sem itens pendentes</strong>
              <span>Itens importados aparecem aqui quando precisam de escolha de MP ou conversao.</span>
            </div>
          )}
        </section>
      </section>
    </main>
  );
}

function XmlReviewCard({ item, materiasPrimas }: { item: PendingXmlItem; materiasPrimas: XmlLookupOption[] }) {
  const suggestedMpId = item.materiaPrimaSugeridaId !== null
    && materiasPrimas.some((option) => option.id === item.materiaPrimaSugeridaId)
    ? item.materiaPrimaSugeridaId
    : null;

  return (
    <article className="xml-review-card">
      <div className="xml-review-main">
        <div>
          <h3>
            Item {item.numeroItem} - {item.descricaoFornecedor}
          </h3>
          <p>
            NF {item.nfeNumero ?? item.nfeId} / {item.emitenteNome ?? item.chaveAcesso}
          </p>
          <div className="tag-row">
            <span className="tag">codigo: {item.codigoFornecedor ?? "sem codigo"}</span>
            <span className="tag">NCM: {item.ncm ?? "sem NCM"}</span>
            <span className="tag">CFOP: {item.cfop ?? "sem CFOP"}</span>
            <span className="tag">
              {numberOrDash(item.quantidadeXml)} {item.unidadeXml}
            </span>
            <span className="tag">{moneyOrDash(item.valorTotal)}</span>
          </div>
        </div>
        <div className="xml-score">
          <strong>{item.melhorScore === null ? "-" : `${item.melhorScore}`}</strong>
          <span>{internalValueLabel(item.status)}</span>
        </div>
      </div>

      <p className="muted">{item.melhorMotivo ?? "Sem candidato sugerido. Escolha a MP manualmente."}</p>

      <form className="inline-form-grid" action={confirmNfeItemMatchAction}>
        <input type="hidden" name="item_id" value={item.itemId} />
        <LocalEntityLookup
          className="wide-field"
          name="materia_prima_id"
          label="MP confirmada"
          placeholder="Abra a lista ou pesquise por SKU ou nome"
          options={materiasPrimas}
          defaultValue={suggestedMpId}
          required
        />
        <label>
          Unidade destino
          <input name="unidade_destino" placeholder="KG" />
        </label>
        <label>
          Fator
          <input name="fator_conversao" inputMode="decimal" placeholder="auto ou manual" />
        </label>
        <label>
          Lote fornecedor
          <input name="lote_fornecedor" placeholder="opcional" />
        </label>
        <label>
          Fabricacao
          <input name="data_fabricacao" type="date" />
        </label>
        <label>
          Validade
          <input name="data_validade" type="date" />
        </label>
        <label className="wide-field">
          Motivo
          <input name="motivo" placeholder="Confirmacao da MP correta e conversao aplicada" required />
        </label>
        <button className="primary-button" type="submit">
          Confirmar match
        </button>
      </form>

      <div className="xml-action-row">
        <form action={generateMpLotFromNfeItemAction}>
          <input type="hidden" name="item_id" value={item.itemId} />
          <select name="status" defaultValue="disponivel" aria-label="Status inicial do lote MP">
            <option value="disponivel">Disponível</option>
            <option value="bloqueado">Bloqueado</option>
          </select>
          <input name="observacao" placeholder="observacao do lote MP" />
          <button className="secondary-button" type="submit">
            Gerar lote MP
          </button>
        </form>
        <form action={ignoreNfeItemAction}>
          <input type="hidden" name="item_id" value={item.itemId} />
          <input name="motivo" placeholder="motivo para ignorar" required />
          <button className="secondary-button" type="submit">
            Ignorar item
          </button>
        </form>
      </div>
    </article>
  );
}



function singleValue(value: string | string[] | undefined): string | undefined {
  return Array.isArray(value) ? value[0] : value;
}

function valueOrDash(value: number | null): string {
  return value === null ? "sem conexao" : String(value);
}

function numberOrDash(value: number | null): string {
  if (value === null) {
    return "sem conexao";
  }
  return new Intl.NumberFormat("pt-BR", { maximumFractionDigits: 4 }).format(value);
}

function moneyOrDash(value: number | null): string {
  if (value === null) {
    return "sem conexao";
  }
  return new Intl.NumberFormat("pt-BR", {
    style: "currency",
    currency: "BRL"
  }).format(value);
}

function messageForResult(result: string | undefined): { kind: "ok" | "warning"; title: string; detail: string } | null {
  if (!result) {
    return null;
  }
  const messages: Record<string, { kind: "ok" | "warning"; title: string; detail: string }> = {
    xml_imported: {
      kind: "ok",
      title: "XML importado",
      detail: "Cabecalho e itens entraram na fila de conferencia sem movimentar estoque."
    },
    header_staged: {
      kind: "ok",
      title: "Cabecalho salvo",
      detail: "A NF XML foi criada ou atualizada para conferencia."
    },
    item_staged: {
      kind: "ok",
      title: "Item salvo",
      detail: "O item entrou como pendente de match."
    },
    item_matched: {
      kind: "ok",
      title: "Match confirmado",
      detail: "MP, unidade e conversao foram registrados com auditoria."
    },
    mp_lot_generated: {
      kind: "ok",
      title: "Lote MP gerado",
      detail: "A entrada de MP foi criada a partir do item XML conferido."
    },
    item_ignored: {
      kind: "ok",
      title: "Item ignorado",
      detail: "O item XML foi encerrado sem gerar estoque."
    },
    not_configured: {
      kind: "warning",
      title: "Supabase nao configurado",
      detail: "Configure Supabase antes de importar XML."
    },
    missing_xml_text: {
      kind: "warning",
      title: "XML obrigatorio",
      detail: "Cole o XML completo ou use os formularios manuais."
    },
    invalid_xml: {
      kind: "warning",
      title: "XML invalido",
      detail: "Nao encontrei chave de acesso valida no XML."
    },
    no_xml_items: {
      kind: "warning",
      title: "Sem itens",
      detail: "Nao encontrei itens de produto no XML informado."
    },
    invalid_chave_acesso: {
      kind: "warning",
      title: "Chave invalida",
      detail: "A chave de acesso deve ter 44 digitos."
    },
    missing_item_required: {
      kind: "warning",
      title: "Item incompleto",
      detail: "NF, item, descricao, unidade e quantidade sao obrigatorios."
    },
    missing_match_required: {
      kind: "warning",
      title: "Match incompleto",
      detail: "Informe item, MP confirmada e motivo."
    },
    missing_conversion_factor: {
      kind: "warning",
      title: "Conversao obrigatoria",
      detail: "Cadastre a conversao da MP ou informe um fator manual."
    },
    missing_motivo: {
      kind: "warning",
      title: "Motivo obrigatorio",
      detail: "Confirmacao, ignore ou ajuste precisa de motivo auditavel."
    },
    already_generated: {
      kind: "warning",
      title: "Lote ja gerado",
      detail: "Este item XML ja possui lote de MP vinculado."
    },
    save_failed: {
      kind: "warning",
      title: "Falha ao salvar",
      detail: "A acao nao foi concluida. Verifique o banco e os logs."
    }
  };
  return messages[result] ?? messages.save_failed;
}
