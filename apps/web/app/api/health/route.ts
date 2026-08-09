import { NextResponse } from "next/server";

import { getRuntimeStatus } from "@/lib/runtime";

export const dynamic = "force-dynamic";

export function GET() {
  const runtime = getRuntimeStatus();
  return NextResponse.json({
    service: "elite-system-web",
    status: "ok",
    backendConfigured: runtime.supabaseConfigured
  });
}
