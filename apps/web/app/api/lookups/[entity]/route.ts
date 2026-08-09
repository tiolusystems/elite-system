import { NextResponse } from "next/server";

import {
  CORPORATE_LOOKUP_CONTRACTS,
  isCorporateLookupEntity,
  searchCorporateLookup
} from "@/lib/corporate-lookups";
import { createSupabaseServerClient } from "@/lib/supabase/server";

type RouteModuleAccess = {
  module_key: string | null;
  available: boolean;
  reason: string;
};

export async function GET(request: Request, context: { params: Promise<{ entity: string }> }) {
  const { entity } = await context.params;
  if (!isCorporateLookupEntity(entity)) {
    return NextResponse.json({ message: "Consulta não reconhecida." }, { status: 404 });
  }

  const supabase = await createSupabaseServerClient();
  const { data: authData, error: authError } = await supabase.auth.getUser();
  if (authError || !authData.user) {
    return NextResponse.json({ message: "Sua sessão expirou. Entre novamente para consultar." }, { status: 401 });
  }

  const contract = CORPORATE_LOOKUP_CONTRACTS[entity];
  const guardedModule = contract.scope === "production"
    ? { pathname: "/producao", label: "Produção" }
    : contract.scope === "commercial"
      ? { pathname: "/pedidos", label: "Comercial" }
      : null;

  if (guardedModule) {
    const moduleAccessResult = await supabase.rpc("get_current_route_module_access", {
      p_pathname: guardedModule.pathname
    });
    const moduleAccess = Array.isArray(moduleAccessResult.data)
      ? (moduleAccessResult.data[0] as RouteModuleAccess | undefined)
      : undefined;

    if (moduleAccessResult.error || !moduleAccess) {
      return NextResponse.json(
        { message: `A autorização do módulo ${guardedModule.label} não está disponível agora.` },
        { status: 503 }
      );
    }
    if (!moduleAccess.available) {
      return NextResponse.json(
        { message: `Você não possui acesso ao módulo ${guardedModule.label}.` },
        { status: 403 }
      );
    }
  }

  const url = new URL(request.url);
  const page = positive(url.searchParams.get("pagina")) ?? 1;
  const contextId = positive(url.searchParams.get("contexto"));

  try {
    const result = await searchCorporateLookup({
      entity,
      query: url.searchParams.get("q") ?? "",
      page,
      contextId
    });
    return NextResponse.json(result, { headers: { "Cache-Control": "private, no-store" } });
  } catch {
    return NextResponse.json({ message: "Não foi possível consultar agora." }, { status: 500 });
  }
}

function positive(value: string | null): number | null {
  const parsed = Number(value);
  return Number.isInteger(parsed) && parsed > 0 ? parsed : null;
}
