import { type NextRequest, NextResponse } from "next/server";

import { applicationUrl } from "@/lib/application-url";
import { createSupabaseServerClient } from "@/lib/supabase/server";

const CHANGE_PASSWORD_PATH = "/login/trocar-senha";

export async function GET(request: NextRequest) {
  const code = request.nextUrl.searchParams.get("code");
  const tokenHash = request.nextUrl.searchParams.get("token_hash");
  const type = request.nextUrl.searchParams.get("type");
  const supabase = await createSupabaseServerClient();

  let error: { message: string } | null = null;

  if (tokenHash && type === "recovery") {
    const result = await supabase.auth.verifyOtp({
      token_hash: tokenHash,
      type: "recovery"
    });
    error = result.error;
  } else if (code) {
    const result = await supabase.auth.exchangeCodeForSession(code);
    error = result.error;
  } else {
    error = { message: "missing recovery credential" };
  }

  const redirectUrl = applicationUrl("/");

  if (error) {
    redirectUrl.pathname = "/login/recuperar-senha";
    redirectUrl.searchParams.set("result", "recovery_expired");
    return NextResponse.redirect(redirectUrl);
  }

  redirectUrl.pathname = CHANGE_PASSWORD_PATH;
  redirectUrl.searchParams.set("mode", "recovery");
  return NextResponse.redirect(redirectUrl);
}
