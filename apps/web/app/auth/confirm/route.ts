import { type NextRequest, NextResponse } from "next/server";

import { applicationUrl } from "@/lib/application-url";
import { auditedRpc } from "@/lib/supabase/rpc";
import { createSupabaseServerClient } from "@/lib/supabase/server";

const CHANGE_PASSWORD_PATH = "/login/trocar-senha";
type ConfirmationFlow = "email_change" | "invite" | "recovery";

export async function GET(request: NextRequest) {
  const code = request.nextUrl.searchParams.get("code");
  const tokenHash = request.nextUrl.searchParams.get("token_hash");
  const type = request.nextUrl.searchParams.get("type");
  let flow = confirmationFlow(request.nextUrl.searchParams.get("flow"));
  const supabase = await createSupabaseServerClient();

  let error: { message: string } | null = null;

  if (tokenHash && (type === "recovery" || type === "invite" || type === "email_change")) {
    flow = type;
    const result = await supabase.auth.verifyOtp({
      token_hash: tokenHash,
      type
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
    if (flow === "recovery") {
      redirectUrl.pathname = "/login/recuperar-senha";
      redirectUrl.searchParams.set("result", "recovery_expired");
    } else {
      redirectUrl.pathname = "/login";
      redirectUrl.searchParams.set("result", flow === "invite" ? "invitation_expired" : "email_change_expired");
    }
    return NextResponse.redirect(redirectUrl);
  }

  if (flow === "email_change") {
    const { error: auditError } = await auditedRpc(supabase, "complete_security_email_change_request", {}, {
      metadata: {
        action_key: "security.email_change.dispatch_approved",
        axis: "status_transition",
        domain: "seguranca",
        entity: "security_email_change_requests",
        failure_action: "seguranca.own_email_change_confirmation_log_failed"
      }
    });
    redirectUrl.pathname = "/login";
    redirectUrl.searchParams.set("result", auditError ? "email_change_audit_failed" : "email_confirmed");
    return NextResponse.redirect(redirectUrl);
  }

  redirectUrl.pathname = CHANGE_PASSWORD_PATH;
  redirectUrl.searchParams.set("mode", flow === "invite" ? "invitation" : "recovery");
  return NextResponse.redirect(redirectUrl);
}

function confirmationFlow(value: string | null): ConfirmationFlow {
  if (value === "email_change" || value === "invite") {
    return value;
  }
  return "recovery";
}
