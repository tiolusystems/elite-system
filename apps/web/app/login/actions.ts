"use server";

import { revalidatePath } from "next/cache";
import { redirect } from "next/navigation";

import { getRuntimeStatus } from "@/lib/runtime";
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
  const { error } = await supabase.auth.signInWithPassword({
    email,
    password
  });

  if (error) {
    redirect(`/login?result=${encodeURIComponent(mapLoginError(error.message))}`);
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
  return "login_failed";
}
