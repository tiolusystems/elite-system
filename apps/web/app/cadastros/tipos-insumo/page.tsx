import Link from "next/link";

import {
  activateInputTypeAction,
  createInputTypeAction,
  deactivateInputTypeAction,
  updateInputTypeAction
} from "@/app/cadastros/tipos-insumo/actions";
import { CatalogFeedback, CatalogShell, StatusChip, singleParam } from "@/app/cadastros/tecnicos/catalog-shell";
import { getTechnicalCatalog } from "@/lib/technical-catalog";

type SearchParams = Record<string, string | string[] | undefined>;

export default async function InputTypesPage({ searchParams }: { searchParams?: Promise<SearchParams> }) {
  const params = searchParams ? await searchParams : {};
  const catalog = await getTechnicalCatalog();
  const query = (singleParam(params.q) ?? "").trim().toLocaleLowerCase("pt-BR");
  const status = singleParam(params.status) ?? "all";
  const requestedId = Number(singleParam(params.selected));
  const filtered = catalog.inputTypes.filter((item) => {
    const matchesText = !query || `${item.code} ${item.name} ${item.description ?? ""}`.toLocaleLowerCase("pt-BR").includes(query);
    return matchesText && (status === "all" || item.status === status);
  });
  const selected = catalog.inputTypes.find((item) => item.id === requestedId) ?? filtered[0] ?? null;
  const summary = catalog.inputTypeSummary;

  return (
    <CatalogShell
      active="input-types"
      title="Tipos de insumo"
      description="Classificação governada das matérias-primas, sem nomes livres ou inferências automáticas."
      source={catalog.source}
      error={catalog.error}
      actions={<a className="primary-button" href="#novo-tipo">Novo tipo</a>}
    >
      <CatalogFeedback result={singleParam(params.result)} />

      <section className="technical-kpis input-type-kpis" aria-label="Resumo da classificação">
        <article><span>Matérias-primas</span><strong>{summary.totalMaterials}</strong><small>Total cadastrado</small></article>
        <article><span>Classificadas</span><strong>{summary.classified}</strong><small>Com fonte auditável</small></article>
        <article className={summary.unclassified > 0 ? "attention" : ""}><span>Não definidas</span><strong>{summary.unclassified}</strong><small>Aguardando revisão</small></article>
        <article><span>Por inferência</span><strong>{summary.inferred}</strong><small>Deve permanecer zero</small></article>
      </section>

      <form className="catalog-filter" method="get" aria-label="Filtros de tipos de insumo">
        <label>Buscar<input name="q" defaultValue={singleParam(params.q) ?? ""} placeholder="Código, nome ou descrição" /></label>
        <label>Situação<select name="status" defaultValue={status}>
          <option value="all">Todas</option><option value="active">Ativas</option>
          <option value="pending_review">Em revisão</option><option value="inactive">Inativas</option>
        </select></label>
        <button className="secondary-button" type="submit">Filtrar</button>
        <Link href="/cadastros/tipos-insumo">Limpar</Link>
      </form>

      <section className="catalog-split input-type-split">
        <article className="panel catalog-list-panel">
          <div className="panel-header"><h2>Catálogo</h2><span className="pill">{filtered.length}</span></div>
          <div className="catalog-record-list">
            {filtered.map((item) => <Link key={item.id} href={{pathname:"/cadastros/tipos-insumo",query:{q:singleParam(params.q)??"",status,selected:item.id}}} aria-current={selected?.id===item.id?"page":undefined}>
              <span><strong>{item.name}</strong><small>{item.code}</small></span>
              <span className="catalog-record-meta"><StatusChip value={item.status}/><small>Ordem {item.displayOrder}</small></span>
            </Link>)}
            {filtered.length === 0 ? <div className="empty-state"><strong>Nenhum tipo encontrado</strong><span>Ajuste os filtros ou cadastre o primeiro tipo de insumo.</span></div> : null}
          </div>
        </article>

        <article className="panel catalog-detail-panel" id="editar-tipo">
          {selected ? <>
            <div className="panel-header catalog-detail-header"><div><span className="eyebrow">{selected.code}</span><h2>{selected.name}</h2><p>{selected.description ?? "Sem descrição complementar."}</p></div><StatusChip value={selected.status}/></div>
            <form action={updateInputTypeAction} className="compact-edit-form governed-form">
              <input type="hidden" name="tipo_insumo_id" value={selected.id}/>
              <label>Código<input name="codigo" defaultValue={selected.code} required/></label>
              <label>Nome<input name="nome" defaultValue={selected.name} required/></label>
              <label>Ordem de exibição<input name="ordem_exibicao" type="number" min="0" defaultValue={selected.displayOrder} required/></label>
              <label className="wide-field">Descrição<textarea name="descricao" rows={3} defaultValue={selected.description ?? ""}/></label>
              <label className="wide-field">Motivo da alteração<input name="motivo" placeholder="Explique por que o cadastro mudou" required/></label>
              <button className="primary-button" type="submit">Salvar alterações</button>
            </form>
            <div className="status-action-band">
              <div><strong>{selected.status === "inactive" ? "Tipo inativo" : "Controle de situação"}</strong><span>Registros vinculados permanecem preservados no histórico.</span></div>
              <form action={selected.status === "inactive" ? activateInputTypeAction : deactivateInputTypeAction}>
                <input type="hidden" name="tipo_insumo_id" value={selected.id}/>
                <label>Motivo<input name="motivo" placeholder="Motivo obrigatório" required/></label>
                <button className={selected.status === "inactive" ? "primary-button" : "danger-button"} type="submit">{selected.status === "inactive" ? "Ativar tipo" : "Inativar tipo"}</button>
              </form>
            </div>
          </> : <div className="empty-state"><strong>Selecione um tipo</strong><span>Os detalhes e ações aparecerão aqui.</span></div>}
        </article>
      </section>

      <section className="panel form-panel" id="novo-tipo" aria-labelledby="new-input-type-title">
        <div className="panel-header"><div><span className="eyebrow">Novo registro</span><h2 id="new-input-type-title">Cadastrar tipo de insumo</h2></div></div>
        <form action={createInputTypeAction}>
          <div className="form-grid">
            <label>Código<input name="codigo" placeholder="Ex.: LIQUIDO" required/></label>
            <label>Nome<input name="nome" placeholder="Nome em PT-BR" required/></label>
            <label>Situação<select name="status" defaultValue="pending_review"><option value="pending_review">Em revisão</option><option value="active">Ativa</option></select></label>
            <label>Ordem de exibição<input name="ordem_exibicao" type="number" min="0" defaultValue="100" required/></label>
            <label className="wide-field">Descrição<textarea name="descricao" rows={3} placeholder="Quando este tipo deve ser utilizado"/></label>
            <label className="wide-field">Motivo do cadastro<input name="motivo" placeholder="Justificativa obrigatória" required/></label>
          </div>
          <div className="form-footer"><span>Nenhuma matéria-prima será classificada automaticamente.</span><button className="primary-button" type="submit">Salvar tipo</button></div>
        </form>
      </section>
    </CatalogShell>
  );
}
