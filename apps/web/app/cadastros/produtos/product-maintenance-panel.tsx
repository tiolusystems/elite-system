import {
  setApresentacaoActiveStateAction,
  setProdutoActiveStateAction,
  updateProdutoIdentityAction,
  updateProdutoRegulatoryAction,
  updateProdutoTechnicalAction,
  updateApresentacaoLogisticsAction
} from "@/app/cadastros/actions";
import { StatusChip } from "@/app/cadastros/tecnicos/catalog-shell";
import type { TechnicalProduct, TechnicalProductGroup, TechnicalSaleItem } from "@/lib/technical-catalog";

type Props = {
  product: TechnicalProduct | null;
  groups: TechnicalProductGroup[];
  variants: TechnicalSaleItem[];
};

export function ProductMaintenancePanel({ product, groups, variants }: Props) {
  if (!product) {
    return (
      <section className="panel catalog-selection-empty" aria-label="Manutencao de produto">
        <strong>Selecione um produto</strong>
        <p>Abra um registro do catalogo para consultar apresentacoes, revisar dados e alterar sua situacao.</p>
      </section>
    );
  }

  return (
    <section className="panel catalog-maintenance" id="editar-produto" aria-labelledby="product-maintenance-title">
      <div className="panel-header catalog-maintenance-heading">
        <div>
          <span className="eyebrow">Produto selecionado</span>
          <h2 id="product-maintenance-title">{product.code} · {product.name}</h2>
          <p>Formula operacional futura: quantidades para produzir 1 litro.</p>
        </div>
        <StatusChip value={product.status} />
      </div>

      <div className="catalog-maintenance-summary">
        <span><small>Grupo</small><strong>{product.group ?? "Sem grupo"}</strong></span>
        <span><small>Validade</small><strong>{product.shelfLifeMonths ? `${product.shelfLifeMonths} meses` : "Nao definida"}</strong></span>
        <span><small>Densidade</small><strong>{product.density ? `${formatNumber(product.density)} kg/L` : "Nao definida"}</strong></span>
        <span><small>Apresentacoes</small><strong>{variants.length}</strong></span>
      </div>

      <div className="catalog-maintenance-sections">
        <details open>
          <summary>Identidade e grupo</summary>
          <form action={updateProdutoIdentityAction}>
            <ProductContext productId={product.id} />
            <div className="form-grid">
              <label>Codigo<input name="codigo_produto" defaultValue={product.code} pattern="[0-9]{4}" required /></label>
              <label>Nome<input name="nome" defaultValue={product.name} required /></label>
              <label>Grupo<select name="grupo_id" defaultValue={product.groupId ?? ""}><option value="">Sem grupo</option>{groups.filter((item) => item.status === "active" || item.id === product.groupId).map((item) => <option key={item.id} value={item.id}>{item.code} · {item.name}{item.status === "inactive" ? " (inativo)" : ""}</option>)}</select></label>
              <label className="form-grid-wide">Motivo da alteracao<input name="motivo" minLength={5} required /></label>
            </div>
            <div className="form-footer"><span>Codigo e grupo afetam pedidos, formulas e rastreabilidade.</span><button className="primary-button" type="submit">Salvar identidade</button></div>
          </form>
        </details>

        <details>
          <summary>Dados tecnicos</summary>
          <form action={updateProdutoTechnicalAction}>
            <ProductContext productId={product.id} />
            <div className="form-grid">
              <label>Densidade kg/L<input name="densidade_kg_l" defaultValue={product.density ?? ""} inputMode="decimal" /></label>
              <label>Validade em meses<input name="prazo_validade_meses" defaultValue={product.shelfLifeMonths ?? ""} inputMode="numeric" /></label>
              <label className="form-grid-wide">Motivo da alteracao<input name="motivo" minLength={5} required /></label>
            </div>
            <div className="form-footer"><span>Dados tecnicos alterados ficam registrados na auditoria.</span><button className="primary-button" type="submit">Salvar dados tecnicos</button></div>
          </form>
        </details>

        <details>
          <summary>Regulatorio</summary>
          <form action={updateProdutoRegulatoryAction}>
            <ProductContext productId={product.id} />
            <div className="form-grid">
              <label>Registro MAPA<input name="reg_mapa" defaultValue={product.mapaRegistration ?? ""} /></label>
              <label>NCM<input name="ncm" defaultValue={product.ncm ?? ""} inputMode="numeric" /></label>
              <label>IBAMA<input name="ibama" defaultValue={product.ibama ?? ""} /></label>
              <label>ADS<input name="ads" defaultValue={product.ads ?? ""} /></label>
              <label className="form-grid-wide">Motivo da alteracao<input name="motivo" minLength={5} required /></label>
            </div>
            <div className="form-footer"><span>Alteracoes regulatorias exigem rastreabilidade.</span><button className="primary-button" type="submit">Salvar dados regulatorios</button></div>
          </form>
        </details>
      </div>

      <div className="catalog-linked-records" id="apresentacoes">
        <div className="panel-header"><h3>Apresentacoes comerciais</h3><span className="pill">{variants.length}</span></div>
        {variants.map((variant) => (
          <div className="catalog-linked-row" key={variant.id}>
            <span><strong>{variant.code}</strong><small>{variant.packageLabel}</small><small>{variant.unitsPerLogisticVolume ? `${formatNumber(variant.unitsPerLogisticVolume)} un. por volume` : "Volumes pendentes"}</small></span>
            <StatusChip value={variant.status} />
            <form action={updateApresentacaoLogisticsAction}>
              <ProductContext productId={product.id} />
              <input type="hidden" name="apresentacao_id" value={variant.id} />
              <input name="unidades_por_volume" defaultValue={variant.unitsPerLogisticVolume ?? ""} inputMode="decimal" aria-label={`Unidades por volume de ${variant.code}`} placeholder="Unidades por volume" required />
              <input name="motivo" aria-label={`Motivo da configuração logística de ${variant.code}`} placeholder="Motivo obrigatório" minLength={5} required />
              <button className="secondary-button compact-button" type="submit">Salvar volumes</button>
            </form>
            <form action={setApresentacaoActiveStateAction}>
              <ProductContext productId={product.id} />
              <input type="hidden" name="apresentacao_id" value={variant.id} />
              <input type="hidden" name="active" value={variant.status === "active" ? "0" : "1"} />
              <input name="motivo" aria-label={`Motivo para ${variant.code}`} placeholder="Motivo obrigatorio" minLength={5} required />
              <button className="secondary-button compact-button" type="submit">{variant.status === "active" ? "Desativar" : "Reativar"}</button>
            </form>
          </div>
        ))}
        {variants.length === 0 ? <p className="empty-state">Nenhuma apresentacao vinculada.</p> : null}
      </div>

      <form className="catalog-status-action" action={setProdutoActiveStateAction} id="situacao-produto">
        <ProductContext productId={product.id} />
        <input type="hidden" name="active" value={product.status === "active" ? "0" : "1"} />
        <label>Motivo para {product.status === "active" ? "desativar" : "reativar"}<input name="motivo" minLength={5} required /></label>
        <button className={product.status === "active" ? "danger-button" : "primary-button"} type="submit">{product.status === "active" ? "Desativar produto" : "Reativar produto"}</button>
      </form>
    </section>
  );
}

function ProductContext({ productId }: { productId: number }) {
  return <><input type="hidden" name="return_to" value="/cadastros/produtos" /><input type="hidden" name="produto_id" value={productId} /></>;
}

function formatNumber(value: number): string {
  return new Intl.NumberFormat("pt-BR", { maximumFractionDigits: 6 }).format(value);
}
