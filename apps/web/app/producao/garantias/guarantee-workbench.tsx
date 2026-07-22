import {
  registerMpLotGuaranteeAction,
  registerMpLotParametersAction,
  registerProductGuaranteeAction,
  reviewHistoricalGuaranteeAction
} from "@/app/pcp/actions";
import type { PcpDashboard } from "@/lib/pcp";
import { unitLabel, unitOptionLabel } from "@/lib/production-labels";

export function GuaranteeWorkbench({ dashboard, today }: { dashboard: PcpDashboard; today: string }) {
  return (
    <>
      <section className="two-column production-forms">
        <form className="panel production-form" action={registerProductGuaranteeAction}>
          <div className="panel-header">
            <h2>Garantia declarada do produto</h2>
            <span className="pill">MAPA / documento</span>
          </div>
          <div className="form-grid">
            <label className="wide-field">
              Produto
              <select name="produto_id" defaultValue="" required>
                <option value="">Selecione</option>
                {dashboard.lookups.produtos.map((option) => (
                  <option key={option.id} value={option.id}>{option.label}</option>
                ))}
              </select>
            </label>
            <label>
              Nutriente
              <select name="nutriente" defaultValue="" required>
                <option value="">Selecione</option>
                {dashboard.lookups.nutrientes.map((option) => (
                  <option key={option.id} value={option.label}>{unitOptionLabel(option)}</option>
                ))}
              </select>
            </label>
            <label>
              Limite
              <select name="tipo_limite" defaultValue="minimo">
                <option value="minimo">Mínimo</option>
                <option value="maximo">Máximo</option>
                <option value="faixa">Faixa</option>
                <option value="declarado">Declarado</option>
              </select>
            </label>
            <label>
              Valor
              <input name="valor" inputMode="decimal" required />
            </label>
            <label>
              Máximo da faixa
              <input name="valor_maximo" inputMode="decimal" />
            </label>
            <label>
              Unidade
              <select name="unidade" defaultValue="" required>
                <option value="">Selecione</option>
                {dashboard.lookups.unidades.map((option) => (
                  <option key={option.id} value={option.label}>{unitOptionLabel(option)}</option>
                ))}
              </select>
            </label>
            <label>
              Fonte
              <select name="fonte" defaultValue="mapa">
                <option value="mapa">MAPA</option>
                <option value="laboratorio">Laboratório</option>
                <option value="manual">Manual</option>
                <option value="fornecedor">Fornecedor</option>
                <option value="calculado">Calculado</option>
              </select>
            </label>
            <label>
              Vigência inicial
              <input name="vigencia_inicio" type="date" defaultValue={today} />
            </label>
            <label>
              Vigência final
              <input name="vigencia_fim" type="date" />
            </label>
            <label className="wide-field">
              Documento
              <input name="documento_referencia" placeholder="Registro MAPA ou laudo" />
            </label>
            <label className="full-field">
              Justificativa
              <input name="justificativa" placeholder="Motivo desta versao" required />
            </label>
          </div>
          <button className="primary-button" type="submit">Registrar versão</button>
        </form>

        <form className="panel production-form" action={registerMpLotGuaranteeAction}>
          <div className="panel-header">
            <h2>Garantia analisada do lote de MP</h2>
            <span className="pill">por lote</span>
          </div>
          <div className="form-grid">
            <label className="wide-field">
              Lote de MP
              <select name="lote_mp_id" defaultValue="" required>
                <option value="">Selecione</option>
                {dashboard.availableLots.filter((lot) => lot.tipo === "MP").map((lot) => (
                  <option key={lot.id} value={lot.id}>{lot.codigoLote} - {lot.targetLabel}</option>
                ))}
              </select>
            </label>
            <label>
              Nutriente
              <select name="nutriente" defaultValue="" required>
                <option value="">Selecione</option>
                {dashboard.lookups.nutrientes.map((option) => (
                  <option key={option.id} value={option.label}>{option.label} - {option.detail}</option>
                ))}
              </select>
            </label>
            <label>
              Valor
              <input name="valor" inputMode="decimal" required />
            </label>
            <label>
              Unidade
              <select name="unidade" defaultValue="" required>
                <option value="">Selecione</option>
                {dashboard.lookups.unidades.map((option) => (
                  <option key={option.id} value={option.label}>{unitOptionLabel(option)}</option>
                ))}
              </select>
            </label>
            <label>
              Fonte
              <select name="fonte" defaultValue="laboratorio">
                <option value="laboratorio">Laboratório</option>
                <option value="fornecedor">Fornecedor</option>
                <option value="manual">Manual</option>
                <option value="mapa">MAPA</option>
                <option value="calculado">Calculado</option>
              </select>
            </label>
            <label>
              Data de referência
              <input name="data_referencia" type="date" defaultValue={today} required />
            </label>
            <label className="wide-field">
              Documento
              <input name="documento_referencia" placeholder="Laudo ou certificado" />
            </label>
            <label className="full-field">
              Justificativa
              <input name="justificativa" placeholder="Origem e motivo desta versão" required />
            </label>
          </div>
          <button className="primary-button" type="submit">Registrar analise</button>
        </form>
      </section>

      <section className="panel production-form" aria-labelledby="lot-physical-basis-title">
        <div className="panel-header">
          <div>
            <h2 id="lot-physical-basis-title">Base física do lote de matéria-prima</h2>
            <p className="muted">A densidade do lote converte litros e quilogramas sem estimativas do cadastro geral.</p>
          </div>
          <span className="pill">versionado por lote</span>
        </div>
        <form action={registerMpLotParametersAction} className="form-grid">
          <label className="wide-field">
            Lote de matéria-prima
            <select name="lote_mp_id" defaultValue="" required>
              <option value="">Selecione</option>
              {dashboard.availableLots.filter((lot) => lot.tipo === "MP").map((lot) => (
                <option key={lot.id} value={lot.id}>{lot.codigoLote} - {lot.targetLabel}</option>
              ))}
            </select>
          </label>
          <label>
            Densidade (kg/L)
            <input name="densidade_kg_l" inputMode="decimal" placeholder="Ex.: 1,20" required />
          </label>
          <label>
            Data de referência
            <input name="data_referencia" type="date" defaultValue={today} required />
          </label>
          <label>
            Fonte
            <select name="fonte" defaultValue="laboratorio">
              <option value="laboratorio">Laboratório</option>
              <option value="fornecedor">Fornecedor</option>
              <option value="manual">Informação manual</option>
            </select>
          </label>
          <label className="wide-field">
            Documento
            <input name="documento_referencia" placeholder="Laudo ou certificado" />
          </label>
          <label className="full-field">
            Justificativa
            <input name="justificativa" placeholder="Origem e motivo deste valor" required />
          </label>
          <button className="primary-button" type="submit">Registrar densidade do lote</button>
        </form>
      </section>

      <section className="panel" id="conciliacao-historica" aria-labelledby="historical-guarantee-title">
        <div className="panel-header">
          <div>
            <h2 id="historical-guarantee-title">Conciliação do histórico</h2>
            <p className="muted">Classifique os cálculos encontrados no Excel. Esta revisão não cria garantia MAPA, garantia de lote ou movimento de estoque.</p>
          </div>
          <span className="pill">{dashboard.historicalGuarantees.length} fonte(s)</span>
        </div>
        <div className="production-history-grid">
          {dashboard.historicalGuarantees.map((source) => (
            <form className="panel production-form" action={reviewHistoricalGuaranteeAction} key={source.id}>
              <input type="hidden" name="fonte_historica_id" value={source.id} />
              <div className="panel-header">
                <div>
                  <h3>{source.produtoLabel}</h3>
                  <p className="muted">Termo original: {source.descricaoOrigem}</p>
                </div>
                <span className="pill">{historicalDecisionLabel(source.decisao)}</span>
              </div>
              <dl className="operational-summary">
                <div><dt>PP do Excel</dt><dd>{formatOptionalNumber(source.valorPpPercentualL)}</dd></div>
                <div><dt>PV do Excel</dt><dd>{formatOptionalNumber(source.valorPvKgL)}</dd></div>
                <div><dt>Linha de origem</dt><dd>Lote {source.sourceBatchId}, Excel {source.linhaExcel ?? "não informada"}</dd></div>
                <div><dt>Classificação atual</dt><dd>{source.nutrienteLabel ?? "Ainda não classificada"}</dd></div>
              </dl>
              <div className="form-grid">
                <label>
                  Decisão
                  <select name="decisao" defaultValue="manter_pendente">
                    <option value="classificada">Classificar</option>
                    <option value="manter_pendente">Manter pendente</option>
                    <option value="descartada">Descartar como referência</option>
                  </select>
                </label>
                <label>
                  Nutriente governado
                  <select name="nutriente_id" defaultValue="">
                    <option value="">Selecione para classificar</option>
                    {dashboard.lookups.nutrientes.map((option) => (
                      <option key={option.id} value={option.id}>{unitOptionLabel(option)}</option>
                    ))}
                  </select>
                </label>
                <label>
                  Unidade do PP
                  <select name="unidade_pp_id" defaultValue="">
                    <option value="">Selecione para classificar</option>
                    {dashboard.lookups.unidades.map((option) => (
                      <option key={option.id} value={option.id}>{unitOptionLabel(option)}</option>
                    ))}
                  </select>
                </label>
                <label>
                  Unidade do PV
                  <select name="unidade_pv_id" defaultValue="">
                    <option value="">Selecione para classificar</option>
                    {dashboard.lookups.unidades.map((option) => (
                      <option key={option.id} value={option.id}>{unitOptionLabel(option)}</option>
                    ))}
                  </select>
                </label>
                <label className="full-field">
                  Justificativa da revisão
                  <input name="justificativa" minLength={10} placeholder="Explique a classificação ou por que deve continuar pendente" required />
                </label>
              </div>
              <button className="primary-button" type="submit">Registrar revisão</button>
            </form>
          ))}
          {dashboard.historicalGuarantees.length === 0 ? (
            <div className="empty-state">
              <strong>Nenhuma fonte histórica carregada</strong>
              <span>Os cálculos do Excel aparecerão aqui somente após a importação rastreável das linhas aprovadas.</span>
            </div>
          ) : null}
        </div>
      </section>

      <section className="panel" aria-labelledby="guarantee-history-title">
        <div className="panel-header">
          <h2 id="guarantee-history-title">Garantias vigentes</h2>
          <span className="pill">{dashboard.productGuarantees.length + dashboard.mpLotGuarantees.length} registro(s)</span>
        </div>
        <div className="table-scroll production-guarantee-table">
          <table className="data-table">
            <thead>
              <tr><th>Origem</th><th>Item</th><th>Nutriente</th><th>Valor</th><th>Regra/Fonte</th><th>Referencia</th></tr>
            </thead>
            <tbody>
              {dashboard.productGuarantees.map((guarantee) => (
                <tr key={`produto-${guarantee.id}`}>
                  <td>Produto</td>
                  <td>{guarantee.produtoLabel}</td>
                  <td>{guarantee.nutriente}</td>
                  <td>{formatNumber(guarantee.valor)}{guarantee.valorMaximo === null ? "" : ` a ${formatNumber(guarantee.valorMaximo)}`} {unitLabel(guarantee.unidade)}</td>
                  <td>{limitLabel(guarantee.tipoLimite)} / {sourceLabel(guarantee.fonte)}</td>
                  <td>{guarantee.documentoReferencia ?? "-"}</td>
                </tr>
              ))}
              {dashboard.mpLotGuarantees.map((guarantee) => (
                <tr key={`lote-${guarantee.id}`}>
                  <td>Lote MP</td>
                  <td>{guarantee.loteLabel}</td>
                  <td>{guarantee.nutriente}</td>
                  <td>{formatNumber(guarantee.valor)} {unitLabel(guarantee.unidade)}</td>
                  <td>{sourceLabel(guarantee.fonte)}</td>
                  <td>{guarantee.documentoReferencia ?? guarantee.dataReferencia ?? "-"}</td>
                </tr>
              ))}
              {dashboard.productGuarantees.length + dashboard.mpLotGuarantees.length === 0 ? (
                <tr><td colSpan={6}>Nenhuma garantia vigente cadastrada.</td></tr>
              ) : null}
            </tbody>
          </table>
        </div>
      </section>

      <section className="panel" aria-labelledby="lot-density-history-title">
        <div className="panel-header">
          <h2 id="lot-density-history-title">Densidades vigentes por lote</h2>
          <span className="pill">{dashboard.mpLotParameters.length} registro(s)</span>
        </div>
        <div className="table-scroll">
          <table className="data-table">
            <thead>
              <tr><th>Lote</th><th>Densidade</th><th>Referência</th><th>Fonte</th><th>Documento</th></tr>
            </thead>
            <tbody>
              {dashboard.mpLotParameters.map((parameter) => (
                <tr key={parameter.id}>
                  <td>{parameter.loteLabel}</td>
                  <td>{formatNumber(parameter.densidadeKgL)} kg/L</td>
                  <td>{parameter.dataReferencia}</td>
                  <td>{sourceLabel(parameter.fonte)}</td>
                  <td>{parameter.documentoReferencia ?? "-"}</td>
                </tr>
              ))}
              {dashboard.mpLotParameters.length === 0 ? (
                <tr><td colSpan={5}>Nenhuma densidade por lote registrada.</td></tr>
              ) : null}
            </tbody>
          </table>
        </div>
      </section>

      <section className="panel" aria-labelledby="op-guarantee-results-title">
        <div className="panel-header">
          <div>
            <h2 id="op-guarantee-results-title">Resultados calculados por OP</h2>
            <p className="muted">Memória calculada com os lotes efetivamente consumidos, sem substituir laudo ou garantia documental.</p>
          </div>
          <span className="pill">{dashboard.opGuaranteeResults.length} resultado(s)</span>
        </div>
        <div className="table-scroll production-guarantee-table">
          <table className="data-table">
            <thead>
              <tr><th>OP</th><th>Produto gerado</th><th>Nutriente</th><th>Calculado</th><th>Referência MAPA</th><th>Situação</th></tr>
            </thead>
            <tbody>
              {dashboard.opGuaranteeResults.map((result) => (
                <tr key={result.id}>
                  <td>OP {result.opId} / cálculo v{result.calculoVersao}</td>
                  <td>{result.produtoLabel}</td>
                  <td>{result.nutriente}</td>
                  <td>{result.valorCalculado === null ? "Não calculado" : `${formatNumber(result.valorCalculado)} ${unitLabel(result.unidade)}`}</td>
                  <td>{guaranteeReference(result)}</td>
                  <td><span className={`status-badge ${guaranteeStatusTone(result.statusResultado)}`}>{guaranteeResultLabel(result.statusResultado)}</span></td>
                </tr>
              ))}
              {dashboard.opGuaranteeResults.length === 0 ? (
                <tr><td colSpan={6}>Nenhuma OP finalizada possui resultado de garantia calculado.</td></tr>
              ) : null}
            </tbody>
          </table>
        </div>
      </section>
    </>
  );
}

function guaranteeReference(result: PcpDashboard["opGuaranteeResults"][number]): string {
  if (result.valorReferencia === null || !result.tipoLimite) return "Sem referência cadastrada";
  const upper = result.valorMaximoReferencia === null ? "" : ` a ${formatNumber(result.valorMaximoReferencia)}`;
  return `${limitLabel(result.tipoLimite)}: ${formatNumber(result.valorReferencia)}${upper} ${unitLabel(result.unidade)}`;
}

function guaranteeResultLabel(value: string): string {
  const labels: Record<string, string> = {
    atende: "Atende",
    nao_atende: "Não atende",
    informativo: "Informativo",
    sem_dados_lote: "Faltam dados do lote",
    base_incompleta: "Base física incompleta",
    unidade_incompativel: "Unidade incompatível",
    sem_referencia_mapa: "Sem referência MAPA"
  };
  return labels[value] ?? "Situação não reconhecida";
}

function guaranteeStatusTone(value: string): string {
  if (value === "atende") return "is-success";
  if (value === "nao_atende" || value === "unidade_incompativel") return "is-danger";
  return "is-warning";
}

function formatNumber(value: number): string {
  return new Intl.NumberFormat("pt-BR", { maximumFractionDigits: 6 }).format(value);
}

function formatOptionalNumber(value: number | null): string {
  return value === null ? "Não informado" : formatNumber(value);
}

function historicalDecisionLabel(value: string): string {
  const labels: Record<string, string> = {
    nao_revisada: "Não revisada",
    classificada: "Classificada",
    manter_pendente: "Pendente",
    descartada: "Descartada"
  };
  return labels[value] ?? "Situação não reconhecida";
}

function limitLabel(value: string): string {
  const labels: Record<string, string> = { minimo: "Mínimo", maximo: "Máximo", faixa: "Faixa", declarado: "Declarado" };
  return labels[value] ?? "Regra não reconhecida";
}

function sourceLabel(value: string): string {
  const labels: Record<string, string> = {
    mapa: "MAPA",
    manual: "Manual",
    laboratorio: "Laboratório",
    fornecedor: "Fornecedor",
    calculado: "Calculado"
  };
  return labels[value] ?? "Fonte não reconhecida";
}
