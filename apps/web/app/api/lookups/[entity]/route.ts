import { NextResponse } from "next/server";

import { isCorporateLookupEntity, searchCorporateLookup } from "@/lib/corporate-lookups";
import { createSupabaseServerClient } from "@/lib/supabase/server";

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
