import {
  activateEmbalagemVersaoAction,
  addEmbalagemComponenteAction,
  createEmbalagemVersaoAction,
  removeEmbalagemComponenteAction,
  reviewEmbalagemVersaoAction,
  setEmbalagemActiveStateAction,
  updateEmbalagemIdentityAction,
  updateEmbalagemPhysicalAction
} from "@/app/cadastros/actions";
import { StatusChip } from "@/app/cadastros/tecnicos/catalog-shell";
import type {
  TechnicalMaterial,
  TechnicalPackage,
  TechnicalPackageComponent,
  TechnicalPackageVersion,
  TechnicalUnit
} from "@/lib/technical-catalog";

type Props = {
  packageRecord: TechnicalPackage | null;
  versions: TechnicalPackageVersion[];
  components: TechnicalPackageComponent[];
  materials: TechnicalMaterial[];
  units: TechnicalUnit[];
};

export function PackageMaintenancePanel({ packageRecord, versions, components, materials, units }: Props) {
  if (!packageRecord) {
    return (
      <section className="panel catalog-selection-empty" aria-label="Manutencao de embalagem">
        <strong>Selecione uma embalagem</strong>
        <p>Abra um registro para revisar capacidade, estoque e composicao normalizada por litro.</p>
      </section>
    );
  }

  const unit = units.find((item) => item.code.toUpperCase() === packageRecord.unit.toUpperCase());
  const pendingVersion = versions.find((item) => item.reviewStatus === "pending_review") ?? null;

  return (
    <section className="panel catalog-maintenance" id="editar-embalagem" aria-labelledby="package-maintenance-title">
      <div className="panel-header catalog-maintenance-heading">
        <div>
          <span className="eyebrow">Embalagem selecionada</span>
          <h2 id="package-maintenance-title">{packageRecord.description}</h2>
          <p>{packageRecord.volumeLiters ? packageRequirementText(packageRecord.volumeLiters) : "Capacidade pendente para calcular UN/L."}</p>
        </div>
        <StatusChip value={packageRecord.status} />
      </div>

      <div className="catalog-maintenance-summary">
        <span><small>Capacidade</small><strong>{packageRecord.volumeLiters ? `${formatNumber(packageRecord.volumeLiters)} L` : "Nao definida"}</strong></span>
        <span><small>Necessidade</small><strong>{packageRecord.volumeLiters ? `${formatNumber(1 / packageRecord.volumeLiters)} UN/L` : "Incompleta"}</strong></span>
        <span><small>Estoque</small><strong>{packageRecord.controlsStock ? "Controlado" : "Nao controlado"}</strong></span>
        <span><small>Versoes</small><strong>{versions.length}</strong></span>
      </div>

      <div className="catalog-maintenance-sections">
        <details open>
          <summary>Identidade</summary>
          <form action={updateEmbalagemIdentityAction}>
            <PackageContext packageId={packageRecord.id} />
            <div className="form-grid">
              <label>Descricao<input name="descricao" defaultValue={packageRecord.description} required /></label>
              <label>Codigo legado<input name="codigo_legado" defaultValue={packageRecord.legacyCode ?? ""} /></label>
              <label className="form-grid-wide">Motivo da alteracao<input name="motivo" minLength={5} required /></label>
            </div>
            <div className="form-footer"><span>Identidade alterada sem perder o historico.</span><button className="primary-button" type="submit">Salvar identidade</button></div>
          </form>
        </details>

        <details>
          <summary>Capacidade e estoque</summary>
          <form action={updateEmbalagemPhysicalAction}>
            <PackageContext packageId={packageRecord.id} />
            <div className="form-grid">
              <label>Unidade<select name="unidade_id" defaultValue={unit?.id ?? ""} required>{units.filter((item) => item.status === "active" && item.code.toUpperCase() === "UN").map((item) => <option key={item.id} value={item.id}>UN · {item.name}</option>)}</select></label>
              <label>Capacidade em litros<input name="volume_litros" defaultValue={packageRecord.volumeLiters ?? ""} inputMode="decimal" required /></label>
              <label>MP de estoque<select name="materia_prima_id" defaultValue={packageRecord.materialId ?? ""}><option value="">Nenhuma</option>{materials.filter((item) => item.status === "active").map((item) => <option key={item.id} value={item.id}>{item.sku} · {item.name}</option>)}</select></label>
              <label className="checkbox-line"><input type="checkbox" name="controla_estoque" value="1" defaultChecked={packageRecord.controlsStock} />Controlar como insumo</label>
              <label className="form-grid-wide">Motivo da alteracao<input name="motivo" minLength={5} required /></label>
            </div>
            <div className="form-footer"><span>A necessidade UN/L sera derivada da capacidade.</span><button className="primary-button" type="submit">Salvar capacidade</button></div>
          </form>
        </details>
      </div>

      <div className="package-composition" id="composicao">
        <div className="panel-header">
          <div><span className="eyebrow">Composicao versionada</span><h3>Componentes em UN/L</h3></div>
          <span className="pill">{versions.length} versao(oes)</span>
        </div>

        {versions.map((version) => {
          const versionComponents = components.filter((item) => item.packageVersionId === version.id && item.status === "active");
          return (
            <article className="package-version" key={version.id}>
              <div className="package-version-heading">
                <span><strong>Versao {version.version}</strong><small>{version.active ? "Versao ativa" : validityLabel(version)}</small></span>
                <StatusChip value={version.active ? "active" : version.reviewStatus} />
              </div>
              <p className="package-ratio">{version.unitsPerLiter ? `${formatNumber(version.unitsPerLiter)} UN/L de embalagem` : "Base por litro nao comprovada"}</p>
              <div className="component-list">
                {versionComponents.map((component) => (
                  <div key={component.id}>
                    <span><strong>{component.materialLabel}</strong><small>{component.quantityUnL ? `${formatNumber(component.quantityUnL)} UN/L` : "Quantidade pendente"}</small></span>
                    {version.reviewStatus === "pending_review" ? <form action={removeEmbalagemComponenteAction}><PackageContext packageId={packageRecord.id} /><input type="hidden" name="componente_id" value={component.id} /><input name="motivo" placeholder="Motivo para remover" minLength={5} required /><button className="icon-text-button" type="submit">Remover</button></form> : null}
                  </div>
                ))}
                {versionComponents.length === 0 ? <p className="empty-state">Nenhum componente ativo nesta versao.</p> : null}
              </div>
              {version.reviewStatus === "pending_review" ? (
                <div className="package-version-actions">
                  <form action={reviewEmbalagemVersaoAction}><PackageContext packageId={packageRecord.id} /><input type="hidden" name="embalagem_versao_id" value={version.id} /><input type="hidden" name="decisao" value="approved" /><input name="motivo" placeholder="Motivo da aprovacao" minLength={5} required /><button className="primary-button compact-button" type="submit">Aprovar versao</button></form>
                  <form action={reviewEmbalagemVersaoAction}><PackageContext packageId={packageRecord.id} /><input type="hidden" name="embalagem_versao_id" value={version.id} /><input type="hidden" name="decisao" value="rejected" /><input name="motivo" placeholder="Motivo da rejeicao" minLength={5} required /><button className="secondary-button compact-button" type="submit">Rejeitar</button></form>
                </div>
              ) : null}
              {version.reviewStatus === "approved" ? <form className="package-activation-form" action={activateEmbalagemVersaoAction}><PackageContext packageId={packageRecord.id} /><input type="hidden" name="embalagem_versao_id" value={version.id} /><input type="hidden" name="ativar" value={version.active ? "0" : "1"} /><input name="motivo" placeholder="Motivo obrigatorio" minLength={5} required /><button className={version.active ? "secondary-button" : "primary-button"} type="submit">{version.active ? "Desativar versao" : "Ativar versao"}</button></form> : null}
            </article>
          );
        })}
        {versions.length === 0 ? <p className="empty-state">Nenhuma composicao versionada. Crie a primeira versao sem alterar registros anteriores.</p> : null}

        <div className="two-column package-composition-forms">
          <form className="subform" action={createEmbalagemVersaoAction}>
            <PackageContext packageId={packageRecord.id} />
            <h4>Nova versao</h4>
            <div className="form-grid">
              <label>Vigencia inicial<input type="date" name="vigencia_inicio" /></label>
              <label>Vigencia final<input type="date" name="vigencia_fim" /></label>
              <label>Tara em kg<input name="peso_tara_kg" inputMode="decimal" /></label>
              <label>Cubagem em m³<input name="cubagem_m3" inputMode="decimal" /></label>
              <label className="form-grid-wide">Justificativa<input name="justificativa" minLength={5} required /></label>
            </div>
            <button className="primary-button" type="submit">Criar nova versao</button>
          </form>

          <form className="subform" action={addEmbalagemComponenteAction}>
            <PackageContext packageId={packageRecord.id} />
            <h4>Adicionar componente</h4>
            <label>Versao em revisao<select name="embalagem_versao_id" defaultValue={pendingVersion?.id ?? ""} required><option value="" disabled>Selecione</option>{versions.filter((item) => item.reviewStatus === "pending_review").map((item) => <option key={item.id} value={item.id}>Versao {item.version}</option>)}</select></label>
            <label>Componente<select name="materia_prima_id" defaultValue="" required><option value="" disabled>Selecione</option>{materials.filter((item) => item.status === "active").map((item) => <option key={item.id} value={item.id}>{item.sku} · {item.name}</option>)}</select></label>
            <label>Quantidade UN/L<input name="quantidade_un_l" inputMode="decimal" placeholder={packageRecord.volumeLiters ? formatNumber(1 / packageRecord.volumeLiters) : "0,000"} required /></label>
            <label>Motivo<input name="motivo" minLength={5} required /></label>
            <button className="primary-button" type="submit" disabled={!pendingVersion}>Adicionar componente</button>
          </form>
        </div>
      </div>

      <form className="catalog-status-action" action={setEmbalagemActiveStateAction} id="situacao-embalagem">
        <PackageContext packageId={packageRecord.id} />
        <input type="hidden" name="active" value={packageRecord.status === "active" ? "0" : "1"} />
        <label>Motivo para {packageRecord.status === "active" ? "desativar" : "reativar"}<input name="motivo" minLength={5} required /></label>
        <button className={packageRecord.status === "active" ? "danger-button" : "primary-button"} type="submit">{packageRecord.status === "active" ? "Desativar embalagem" : "Reativar embalagem"}</button>
      </form>
    </section>
  );
}

function PackageContext({ packageId }: { packageId: number }) {
  return <><input type="hidden" name="return_to" value="/cadastros/embalagens" /><input type="hidden" name="embalagem_id" value={packageId} /></>;
}

function packageRequirementText(volume: number): string {
  return `1 unidade para cada ${formatNumber(volume)} litros · ${formatNumber(1 / volume)} UN/L`;
}

function validityLabel(version: TechnicalPackageVersion): string {
  if (!version.validFrom && !version.validTo) return "Vigencia permanente";
  return `${version.validFrom ?? "Inicio aberto"} ate ${version.validTo ?? "sem termino"}`;
}

function formatNumber(value: number): string {
  return new Intl.NumberFormat("pt-BR", { minimumFractionDigits: 0, maximumFractionDigits: 6 }).format(value);
}
