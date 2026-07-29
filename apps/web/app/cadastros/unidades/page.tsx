import Link from "next/link";

import { createConversaoUnidadeMpAction } from "@/app/cadastros/actions";
import { CatalogFeedback, CatalogShell, StatusChip, singleParam } from "@/app/cadastros/tecnicos/catalog-shell";
import { getTechnicalCatalog } from "@/lib/technical-catalog";

type SearchParams = Record<string, string | string[] | undefined>;

export default async function UnitsPage({ searchParams }: { searchParams?: Promise<SearchParams> }) {
  const params = searchParams ? await searchParams : {};
  const catalog = await getTechnicalCatalog();
  const activeUnits = catalog.units.filter((unit) => unit.status === "active");
  const isCreating = singleParam(params.modo) === "novo";

  return (
    <CatalogShell
      active="units"
      title="Unidades e conversões"
      description="Unidades usadas nas matérias-primas, embalagens, fórmulas e movimentações de estoque."
      source={catalog.source}
      error={catalog.error}
      actions={
        isCreating ? (
          <Link className="secondary-button" href="/cadastros/unidades">Voltar à consulta</Link>
        ) : (
          <Link className="primary-button" href="/cadastros/unidades?modo=novo#nova-conversao-mp">Nova conversão</Link>
        )
      }
    >
      <CatalogFeedback result={singleParam(params.result)} />

      <div className="catalog-workbench">
      {!isCreating ? (
      <section className="catalog-list-view" aria-label="Consulta de unidades e conversões">
      <section className="technical-kpis" aria-label="Resumo de unidades">
        <article><span>Unidades</span><strong>{catalog.units.length}</strong><small>{activeUnits.length} ativas</small></article>
        <article><span>Grandezas</span><strong>{new Set(catalog.units.map((item) => item.dimension)).size}</strong><small>Massa, volume e outras</small></article>
        <article><span>Conversões de MP</span><strong>{catalog.conversions.length}</strong><small>Com vigência controlada</small></article>
        <article><span>Nutrientes</span><strong>{catalog.nutrients.length}</strong><small>referencias de garantia</small></article>
      </section>

      <section className="two-column technical-lists">
        <article className="panel">
          <div className="panel-header"><h2>Unidades de medida</h2><span className="pill">{catalog.units.length}</span></div>
          <div className="canonical-grid">
            {catalog.units.map((unit) => (
              <div key={unit.id}>
                <span className="unit-symbol">{unit.symbol}</span>
                <span><strong>{unit.code}</strong><small>{unit.name} · {unit.dimension}</small></span>
                <StatusChip value={unit.status} />
              </div>
            ))}
          </div>
        </article>

        <article className="panel">
          <div className="panel-header"><h2>Nutrientes</h2><span className="pill">{catalog.nutrients.length}</span></div>
          <div className="canonical-grid">
            {catalog.nutrients.map((nutrient) => (
              <div key={nutrient.id}>
                <span className="unit-symbol">{nutrient.symbol ?? "-"}</span>
                <span><strong>{nutrient.name}</strong><small>Garantias e especificacoes</small></span>
                <StatusChip value={nutrient.status} />
              </div>
            ))}
          </div>
        </article>
      </section>

      <section className="panel" aria-labelledby="conversion-list-title">
        <div className="panel-header"><h2 id="conversion-list-title">Conversoes cadastradas</h2><span className="pill">{catalog.conversions.length}</span></div>
        <div className="responsive-record-grid">
          {catalog.conversions.map((conversion) => (
            <article key={conversion.id}>
              <div><strong>{conversion.materialLabel}</strong><StatusChip value={conversion.reviewStatus} /></div>
              <p className="conversion-expression">1 {conversion.sourceUnit} = {formatFactor(conversion.factor)} {conversion.targetUnit}</p>
              <small>{formatValidity(conversion.validFrom, conversion.validTo)}</small>
            </article>
          ))}
          {catalog.conversions.length === 0 ? <p className="empty-state">Nenhuma conversao cadastrada.</p> : null}
        </div>
      </section>
      </section>
      ) : null}

      {isCreating ? (
      <section className="panel form-panel catalog-create-view" id="nova-conversao-mp" aria-labelledby="new-conversion-title">
        <div className="panel-header">
          <div><span className="eyebrow">Regra de entrada</span><h2 id="new-conversion-title">Nova conversao de MP</h2></div>
        </div>
        <form action={createConversaoUnidadeMpAction}>
          <input type="hidden" name="return_to" value="/cadastros/unidades" />
          <div className="form-grid">
            <label>
              Materia-prima
              <select name="materia_prima_id" defaultValue="" required>
                <option value="" disabled>Selecione</option>
                {catalog.materials.filter((item) => item.status === "active").map((item) => (
                  <option key={item.id} value={item.id}>{item.sku} · {item.name}</option>
                ))}
              </select>
            </label>
            <label>
              Unidade de origem
              <select name="unidade_origem" defaultValue="" required>
                <option value="" disabled>Selecione</option>
                {activeUnits.map((unit) => <option key={unit.id} value={unit.code}>{unit.code} · {unit.name}</option>)}
              </select>
            </label>
            <label>
              Unidade de destino
              <select name="unidade_destino" defaultValue="KG" required>
                {activeUnits.map((unit) => <option key={unit.id} value={unit.code}>{unit.code} · {unit.name}</option>)}
              </select>
            </label>
            <label>Fator<input name="fator" inputMode="decimal" required placeholder="50" /></label>
            <label>Vigencia inicial<input name="vigencia_inicio" type="date" /></label>
            <label>Vigencia final<input name="vigencia_fim" type="date" /></label>
          </div>
          <div className="form-footer">
            <span>A unidade de destino deve ser a unidade base da materia-prima.</span>
            <button className="primary-button" type="submit">Salvar conversao</button>
          </div>
        </form>
      </section>
      ) : null}
      </div>
    </CatalogShell>
  );
}

function formatFactor(value: number): string {
  return new Intl.NumberFormat("pt-BR", { maximumFractionDigits: 6 }).format(value);
}

function formatValidity(from: string | null, to: string | null): string {
  if (!from && !to) return "Vigencia permanente";
  return `${from ? formatDate(from) : "inicio aberto"} ate ${to ? formatDate(to) : "sem termino"}`;
}

function formatDate(value: string): string {
  return new Intl.DateTimeFormat("pt-BR").format(new Date(`${value}T12:00:00`));
}
