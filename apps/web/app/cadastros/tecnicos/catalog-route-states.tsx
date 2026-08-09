"use client";

type ErrorProps = {
  title: string;
  reset: () => void;
};

export function CatalogRouteLoading({ title }: { title: string }) {
  return (
    <main className="workspace technical-workspace catalog-route-state" aria-busy="true" aria-live="polite">
      <div className="catalog-state-heading">
        <span className="eyebrow">Cadastros tecnicos</span>
        <h1>{title}</h1>
        <p>Carregando catalogo, relacionamentos e permissoes...</p>
      </div>
      <div className="catalog-state-skeleton" aria-hidden="true">
        <span />
        <span />
        <span />
      </div>
    </main>
  );
}

export function CatalogRouteError({ title, reset }: ErrorProps) {
  return (
    <main className="workspace technical-workspace catalog-route-state" role="alert">
      <div className="notice-panel warning catalog-route-error">
        <span className="eyebrow">Operacao interrompida</span>
        <h1>{title}</h1>
        <p>Nao foi possivel carregar este cadastro. Seus dados nao foram alterados.</p>
        <button className="primary-button" type="button" onClick={reset}>Tentar carregar novamente</button>
      </div>
    </main>
  );
}
