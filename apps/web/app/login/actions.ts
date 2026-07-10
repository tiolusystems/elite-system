"use server";

import { revalidatePath } from "next/cache";
import { redirect } from "next/navigation";

import { getRuntimeStatus } from "@/lib/runtime";
import { auditedRpc } from "@/lib/supabase/rpc";
import { createSupabaseServerClient } from "@/lib/supabase/server";

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
    redirect(`/login/trocar-senha?next=${encodeURIComponent(nextPath)}`);
  }

  revalidatePath("/", "layout");
  redirect(nextPath);
}

export async function changeTemporaryPasswordAction(formData: FormData) {
  if (!getRuntimeStatus().supabaseConfigured) {
    redirect("/login?result=not_configured");
  }

  const nextPath = safeNextPath(field(formData, "next"));
  const password = field(formData, "new_password");
  const confirmation = field(formData, "new_password_confirmation");

  if (!password || !confirmation) {
    redirect(`/login/trocar-senha?result=missing_credentials&next=${encodeURIComponent(nextPath)}`);
  }
  if (password !== confirmation) {
    redirect(`/login/trocar-senha?result=password_mismatch&next=${encodeURIComponent(nextPath)}`);
  }
  if (password.length < 12) {
    redirect(`/login/trocar-senha?result=weak_password&next=${encodeURIComponent(nextPath)}`);
  }

  const supabase = await createSupabaseServerClient();
  const {
    data: { user },
    error: userError
  } = await supabase.auth.getUser();

  if (userError || !user) {
    redirect(`/login?result=auth_required&next=${encodeURIComponent("/login/trocar-senha")}`);
  }

  if (user.user_metadata?.temporary_password_bootstrap !== true) {
    redirect(nextPath);
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
    redirect(`/login/trocar-senha?result=${encodeURIComponent(mapLoginError(updateError.message))}&next=${encodeURIComponent(nextPath)}`);
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
    redirect(`/login/trocar-senha?result=${encodeURIComponent(mapLoginError(auditError.message))}&next=${encodeURIComponent(nextPath)}`);
  }

  revalidatePath("/", "layout");
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
