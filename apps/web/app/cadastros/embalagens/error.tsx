"use client";

import { CatalogRouteError } from "@/app/cadastros/tecnicos/catalog-route-states";

export default function PackagesError({ reset }: { error: Error; reset: () => void }) {
  return <CatalogRouteError title="Embalagens indisponiveis" reset={reset} />;
}
