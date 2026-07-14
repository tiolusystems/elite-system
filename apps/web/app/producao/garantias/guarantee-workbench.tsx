import { registerMpLotGuaranteeAction, registerProductGuaranteeAction } from "@/app/pcp/actions";
import type { PcpDashboard } from "@/lib/pcp";

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
              <input name="nutriente" placeholder="N, P2O5, K2O" required />
            </label>
            <label>
              Limite
              <select name="tipo_limite" defaultValue="minimo">
                <option value="minimo">Minimo</option>
                <option value="maximo">Maximo</option>
                <option value="faixa">Faixa</option>
                <option value="declarado">Declarado</option>
              </select>
            </label>
            <label>
              Valor
              <input name="valor" inputMode="decimal" required />
            </label>
            <label>
              Maximo da faixa
              <input name="valor_maximo" inputMode="decimal" />
            </label>
            <label>
              Unidade
              <input name="unidade" placeholder="%, g/L" required />
            </label>
            <label>
              Fonte
              <select name="fonte" defaultValue="mapa">
                <option value="mapa">MAPA</option>
                <option value="laboratorio">Laboratorio</option>
                <option value="manual">Manual</option>
                <option value="fornecedor">Fornecedor</option>
                <option value="calculado">Calculado</option>
              </select>
            </label>
            <label>
              Vigencia inicial
              <input name="vigencia_inicio" type="date" defaultValue={today} />
            </label>
            <label>
              Vigencia final
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
          <button className="primary-button" type="submit">Registrar versao</button>
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
              <input name="nutriente" placeholder="N, P2O5, K2O" required />
            </label>
            <label>
              Valor
              <input name="valor" inputMode="decimal" required />
            </label>
            <label>
              Unidade
              <input name="unidade" placeholder="%, g/L" required />
            </label>
            <label>
              Fonte
              <select name="fonte" defaultValue="laboratorio">
                <option value="laboratorio">Laboratorio</option>
                <option value="fornecedor">Fornecedor</option>
                <option value="manual">Manual</option>
                <option value="mapa">MAPA</option>
                <option value="calculado">Calculado</option>
              </select>
            </label>
            <label>
              Data de referencia
              <input name="data_referencia" type="date" defaultValue={today} required />
            </label>
            <label className="wide-field">
              Documento
              <input name="documento_referencia" placeholder="Laudo ou certificado" />
            </label>
            <label className="full-field">
              Justificativa
              <input name="justificativa" placeholder="Origem e motivo desta versao" required />
            </label>
          </div>
          <button className="primary-button" type="submit">Registrar analise</button>
        </form>
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
                  <td>{formatNumber(guarantee.valor)}{guarantee.valorMaximo === null ? "" : ` a ${formatNumber(guarantee.valorMaximo)}`} {guarantee.unidade}</td>
                  <td>{guarantee.tipoLimite} / {guarantee.fonte}</td>
                  <td>{guarantee.documentoReferencia ?? "-"}</td>
                </tr>
              ))}
              {dashboard.mpLotGuarantees.map((guarantee) => (
                <tr key={`lote-${guarantee.id}`}>
                  <td>Lote MP</td>
                  <td>{guarantee.loteLabel}</td>
                  <td>{guarantee.nutriente}</td>
                  <td>{formatNumber(guarantee.valor)} {guarantee.unidade}</td>
                  <td>{guarantee.fonte}</td>
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
    </>
  );
}

function formatNumber(value: number): string {
  return new Intl.NumberFormat("pt-BR", { maximumFractionDigits: 6 }).format(value);
}
