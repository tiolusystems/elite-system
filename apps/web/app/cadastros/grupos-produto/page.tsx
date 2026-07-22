import Link from "next/link";

import {
  createProdutoGroupAction,
  setProdutoGroupActiveStateAction,
  updateProdutoGroupAction
} from "@/app/cadastros/actions";
import { CatalogFeedback, CatalogShell, StatusChip, singleParam } from "@/app/cadastros/tecnicos/catalog-shell";
import { getTechnicalCatalog, getTechnicalProductGroupHistory } from "@/lib/technical-catalog";

type SearchParams = Record<string, string | string[] | undefined>;

export default async function ProductGroupsPage({ searchParams }: { searchParams?: Promise<SearchParams> }) {
  const params = searchParams ? await searchParams : {};
  const catalog = await getTechnicalCatalog();
  const query = (singleParam(params.q) ?? "").trim().toLocaleLowerCase("pt-BR");
  const status = singleParam(params.status) ?? "all";
  const selectedId = Number(singleParam(params.selected) ?? "");
  const selected = catalog.productGroups.find((item) => item.id === selectedId) ?? null;
  const history = selected ? await getTechnicalProductGroupHistory(selected.id) : [];
  const groups = catalog.productGroups.filter((item) =>
    (status === "all" || item.status === status) &&
    (!query || `${item.code} ${item.name} ${item.description ?? ""}`.toLocaleLowerCase("pt-BR").includes(query))
  );
  const productsByGroup = new Map<number, typeof catalog.products>();
  for (const product of catalog.products) {
    if (!product.groupId) continue;
    productsByGroup.set(product.groupId, [...(productsByGroup.get(product.groupId) ?? []), product]);
  }

  return (
    <CatalogShell
      active="product-groups"
      title="Grupos de produto"
      description="Catálogo relacional usado por Produtos, Pedidos, Produção e Relatórios."
      source={catalog.source}
      error={catalog.error}
      actions={<a className="primary-button" href="#novo-grupo">Novo grupo</a>}
    >
      <CatalogFeedback result={singleParam(params.result)} />
      <form className="catalog-filter" method="get" aria-label="Filtros de grupos de produto">
        <label>Buscar<input name="q" defaultValue={singleParam(params.q) ?? ""} placeholder="Código, nome ou descrição" /></label>
        <label>Situação<select name="status" defaultValue={status}><option value="all">Todas</option><option value="active">Ativos</option><option value="inactive">Inativos</option><option value="pending_review">Em revisão</option></select></label>
        <button className="secondary-button" type="submit">Filtrar</button>
      </form>

      <section className="panel" aria-labelledby="groups-list-title">
        <div className="panel-header"><div><span className="eyebrow">Catálogo</span><h2 id="groups-list-title">Grupos cadastrados</h2></div><span className="pill">{groups.length} registro(s)</span></div>
        <div className="catalog-record-list">
          {groups.map((group) => (
            <article className="catalog-record" key={group.id}>
              <div><span><small>{group.code}</small><strong>{group.name}</strong></span><StatusChip value={group.status} /></div>
              <p>{group.description ?? "Sem descrição complementar."}</p>
              <div className="catalog-record-actions"><span>{productsByGroup.get(group.id)?.length ?? 0} produto(s) vinculado(s)</span><Link href={`/cadastros/grupos-produto?selected=${group.id}#editar-grupo`}>Abrir grupo</Link></div>
            </article>
          ))}
          {groups.length === 0 ? <div className="empty-state"><strong>Nenhum grupo encontrado</strong><span>Revise os filtros ou crie o primeiro grupo.</span></div> : null}
        </div>
      </section>

      {selected ? (
        <section className="panel form-panel" id="editar-grupo">
          <div className="panel-header"><div><span className="eyebrow">Manutenção auditada</span><h2>{selected.name}</h2></div><StatusChip value={selected.status} /></div>
          <form action={updateProdutoGroupAction}>
            <input type="hidden" name="return_to" value="/cadastros/grupos-produto" /><input type="hidden" name="grupo_id" value={selected.id} />
            <div className="form-grid"><label>Código<input name="codigo" defaultValue={selected.code} required /></label><label>Nome<input name="nome" defaultValue={selected.name} required /></label><label>Ordem de exibição<input name="ordem_exibicao" type="number" min="0" defaultValue={selected.displayOrder} required /></label><label className="form-grid-wide">Descrição<textarea name="descricao" defaultValue={selected.description ?? ""} /></label><label className="form-grid-wide">Motivo da alteração<input name="motivo" minLength={10} required /></label></div>
            <div className="form-footer"><span>Alterações não reclassificam produtos automaticamente.</span><button className="primary-button" type="submit">Salvar alterações</button></div>
          </form>
          <form action={setProdutoGroupActiveStateAction}>
            <input type="hidden" name="return_to" value="/cadastros/grupos-produto" /><input type="hidden" name="grupo_id" value={selected.id} /><input type="hidden" name="active" value={selected.status === "inactive" ? "true" : "false"} />
            <div className="form-grid"><label className="form-grid-wide">Justificativa<input name="motivo" minLength={10} required /></label></div>
            <div className="form-footer"><span>Produtos vinculados permanecem legíveis.</span><button className="secondary-button" type="submit">{selected.status === "inactive" ? "Reativar grupo" : "Inativar grupo"}</button></div>
          </form>
          <div className="compact-list"><strong>Produtos vinculados</strong>{(productsByGroup.get(selected.id) ?? []).map((product) => <p key={product.id}><span>{product.code} · {product.name}</span><Link href={`/cadastros/produtos?selected=${product.id}`}>Abrir produto</Link></p>)}</div>
          <div className="compact-list"><strong>Histórico de alterações</strong>{history.length === 0 ? <p><span>Nenhuma alteração auditada encontrada.</span></p> : history.map((event) => <p key={`${event.createdAt}-${event.action}`}><span>{productGroupEventLabel(event.action)} · {event.actorName}</span><small>{new Intl.DateTimeFormat("pt-BR", { dateStyle: "short", timeStyle: "short" }).format(new Date(event.createdAt))}</small></p>)}</div>
        </section>
      ) : null}

      <section className="panel form-panel" id="novo-grupo">
        <div className="panel-header"><div><span className="eyebrow">Novo cadastro</span><h2>Criar grupo</h2></div></div>
        <form action={createProdutoGroupAction}>
          <input type="hidden" name="return_to" value="/cadastros/grupos-produto" />
          <div className="form-grid"><label>Código<input name="codigo" required /></label><label>Nome<input name="nome" required /></label><label>Ordem de exibição<input name="ordem_exibicao" type="number" min="0" defaultValue="0" required /></label><label className="form-grid-wide">Descrição<textarea name="descricao" /></label></div>
          <div className="form-footer"><span>Código e nome são únicos após normalização.</span><button className="primary-button" type="submit">Criar grupo</button></div>
        </form>
      </section>
    </CatalogShell>
  );
}

function productGroupEventLabel(action: string): string {
  const labels: Record<string, string> = {
    "cadastros.grupo_produto_created": "Grupo criado",
    "cadastros.grupo_produto_updated": "Grupo atualizado",
    "cadastros.grupo_produto_deactivated": "Grupo inativado",
    "cadastros.grupo_produto_reactivated": "Grupo reativado"
  };
  return labels[action] ?? "Alteração registrada";
}
