"use client";

import { CatalogRouteError } from "@/app/cadastros/tecnicos/catalog-route-states";

export default function ProductsError({ reset }: { error: Error; reset: () => void }) {
  return <CatalogRouteError title="Produtos indisponiveis" reset={reset} />;
}
