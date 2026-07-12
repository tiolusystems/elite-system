"use server";

import { revalidatePath } from "next/cache";
import { redirect } from "next/navigation";

import { applicationUrl } from "@/lib/application-url";
import { getRuntimeStatus } from "@/lib/runtime";
import { auditedRpc } from "@/lib/supabase/rpc";
import { createSupabaseServerClient } from "@/lib/supabase/server";

const EMAIL_PATTERN = /^[^@\s]+@[^@\s]+\.[^@\s]+$/;
const MINIMUM_PASSWORD_LENGTH = 12;

type PasswordChangeMode = "authenticated" | "recovery" | "temporary";

export async function loginAction(formData: FormData) {
  if (!getRuntimeStatus().supabaseConfigured) {
    redirect("/login?result=not_configured");
  }

  const email = field(formData, "email");
  const password = field(formData, "password");
  const nextPath = safeNextPath(field(formData, "next"));

  if (!email || !password) {
    redirect("/login?result=missing_credentials");
  }

  const supabase = await createSupabaseServerClient();
  const { data, error } = await supabase.auth.signInWithPassword({
    email,
    password
  });

  if (error) {
    redirect(`/login?result=${encodeURIComponent(mapLoginError(error.message))}`);
  }

  if (data.user?.user_metadata?.temporary_password_bootstrap === true) {
    redirect(`/login/trocar-senha?mode=temporary&next=${encodeURIComponent(nextPath)}`);
  }

  revalidatePath("/", "layout");
  redirect(nextPath);
}

export async function requestPasswordRecoveryAction(formData: FormData) {
  if (!getRuntimeStatus().supabaseConfigured) {
    redirect("/login/recuperar-senha?result=not_configured");
  }

  const email = field(formData, "email").toLowerCase();
  if (!EMAIL_PATTERN.test(email)) {
    redirect("/login/recuperar-senha?result=invalid_email");
  }

  const supabase = await createSupabaseServerClient();
  const { error } = await supabase.auth.resetPasswordForEmail(email, {
    redirectTo: applicationUrl("/auth/confirm").toString()
  });

  if (error) {
    const result = mapPasswordRecoveryError(error.message);
    redirect(`/login/recuperar-senha?result=${encodeURIComponent(result)}`);
  }

  // The same response is used whether or not the account exists.
  redirect("/login/recuperar-senha?result=recovery_sent");
}

export async function changeOwnPasswordAction(formData: FormData) {
  if (!getRuntimeStatus().supabaseConfigured) {
    redirect("/login?result=not_configured");
  }

  const nextPath = safeNextPath(field(formData, "next"));
  const mode = passwordChangeMode(field(formData, "mode"));
  const password = field(formData, "new_password");
  const confirmation = field(formData, "new_password_confirmation");

  if (!password || !confirmation) {
    redirect(changePasswordUrl("missing_credentials", nextPath, mode));
  }
  if (password !== confirmation) {
    redirect(changePasswordUrl("password_mismatch", nextPath, mode));
  }
  if (password.length < MINIMUM_PASSWORD_LENGTH) {
    redirect(changePasswordUrl("weak_password", nextPath, mode));
  }

  const supabase = await createSupabaseServerClient();
  const {
    data: { user },
    error: userError
  } = await supabase.auth.getUser();

  if (userError || !user) {
    redirect("/login/recuperar-senha?result=recovery_expired");
  }

  const { error: updateError } = await supabase.auth.updateUser({
    password,
    data: {
      ...user.user_metadata,
      temporary_password_bootstrap: false,
      temporary_password_changed_at: new Date().toISOString()
    }
  });

  if (updateError) {
    redirect(changePasswordUrl(mapLoginError(updateError.message), nextPath, mode));
  }

  const { error: auditError } = await auditedRpc(supabase, "record_security_own_password_changed", {}, {
    metadata: {
      action_key: "security.change_own_password",
      axis: "change_type",
      domain: "seguranca",
      entity: "auth.users",
      entity_id: user.id,
      failure_action: "seguranca.own_password_change_log_failed"
    }
  });

  if (auditError) {
    redirect(changePasswordUrl("password_changed_audit_failed", nextPath, mode));
  }

  revalidatePath("/", "layout");

  if (mode === "recovery") {
    await supabase.auth.signOut({ scope: "local" });
    redirect("/login?result=password_recovered");
  }
  if (mode === "authenticated") {
    redirect("/login?result=password_changed");
  }
  redirect(nextPath);
}

export async function logoutAction() {
  if (!getRuntimeStatus().supabaseConfigured) {
    redirect("/login?result=not_configured");
  }

  const supabase = await createSupabaseServerClient();
  await supabase.auth.signOut();
  revalidatePath("/", "layout");
  redirect("/login?result=logged_out");
}

function field(formData: FormData, name: string): string {
  return String(formData.get(name) ?? "").trim();
}

function safeNextPath(value: string): string {
  if (!value || !value.startsWith("/") || value.startsWith("//")) {
    return "/";
  }
  if (value.includes("://")) {
    return "/";
  }
  return value;
}

function passwordChangeMode(value: string): PasswordChangeMode {
  if (value === "recovery" || value === "temporary") {
    return value;
  }
  return "authenticated";
}

function changePasswordUrl(result: string, nextPath: string, mode: PasswordChangeMode): string {
  const params = new URLSearchParams({ result, next: nextPath, mode });
  return `/login/trocar-senha?${params.toString()}`;
}

function mapPasswordRecoveryError(message: string): string {
  const normalized = message.toLowerCase();
  if (normalized.includes("rate") || normalized.includes("frequency")) {
    return "rate_limited";
  }
  return "recovery_failed";
}

function mapLoginError(message: string): string {
  const normalized = message.toLowerCase();
  if (normalized.includes("invalid login") || normalized.includes("invalid credentials")) {
    return "invalid_credentials";
  }
  if (normalized.includes("email not confirmed")) {
    return "email_not_confirmed";
  }
  if (normalized.includes("rate")) {
    return "rate_limited";
  }
  if (normalized.includes("not allowed")) {
    return "permission_denied";
  }
  if (normalized.includes("weak") || normalized.includes("password")) {
    return "weak_password";
  }
  return "login_failed";
}
