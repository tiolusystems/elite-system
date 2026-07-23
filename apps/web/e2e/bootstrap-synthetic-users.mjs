import { mkdir, writeFile } from "node:fs/promises";
import path from "node:path";
import { createClient } from "@supabase/supabase-js";

const url = process.env.NEXT_PUBLIC_SUPABASE_URL;
const publishableKey = process.env.NEXT_PUBLIC_SUPABASE_PUBLISHABLE_KEY;
const serviceKey = process.env.SUPABASE_SERVICE_ROLE_KEY;
const password = process.env.E2E_SYNTHETIC_PASSWORD;
const output = process.env.E2E_ACCOUNTS_PATH;
const runId = process.env.E2E_RUN_ID;
if (!url || !publishableKey || !serviceKey || !password || !output || !runId) throw new Error("Synthetic E2E bootstrap environment is incomplete");

const supabase = createClient(url, serviceKey, { auth: { persistSession: false, autoRefreshToken: false } });
const definitions = [
  ["security-admin", "admin", ["seguranca."]],
  ["master-data", "admin", ["cadastros."]],
  ["seller", "comercial", ["pedidos.create", "pedidos.view"]],
  ["order-reviewer", "comercial", ["pedidos.credit.review"]],
  ["credit-authority", "auditoria", ["financeiro.credit_limits.adjust"]],
  ["stock-operator", "estoque", ["estoque."]],
  ["production-operator", "producao", ["pcp."]],
  ["quality-operator", "producao", ["qualidade.", "pcp.op.finish"]],
  ["shipping-operator", "expedicao", ["romaneios.", "estoque.pa.issue.romaneio"]],
  ["fiscal-reference", "expedicao", ["faturamento.external_references."]],
  ["finance-commission", "auditoria", ["financeiro.", "comissoes."]]
];
const { data: actionRows, error: actionError } = await supabase.from("permission_actions").select("action_key");
if (actionError) throw actionError;
const actionKeys = (actionRows ?? []).map((row) => row.action_key);
const accounts = [];
for (const [name, role, prefixes] of definitions) {
  const email = `hom-e2e-${runId}-${name}@test.invalid`;
  const { data, error } = await supabase.auth.admin.createUser({ email, password, email_confirm: true, user_metadata: { display_name: `HOM E2E ${name}` } });
  if (error || !data.user) throw error ?? new Error(`Could not create ${name}`);
  const userId = data.user.id;
  const { error: profileError } = await supabase.from("user_profiles").upsert({ id: userId, display_name: `HOM E2E ${name}`, role, status: "active" });
  if (profileError) throw profileError;
  const allowed = actionKeys.filter((key) => name === "security-admin" || prefixes.some((prefix) => key.startsWith(prefix)));
  if (allowed.length) {
    const { error: overrideError } = await supabase.from("user_permission_overrides").upsert(
      allowed.map((actionKey) => ({ user_id: userId, action_key: actionKey, allowed: true, updated_by: userId })),
      { onConflict: "user_id,action_key" }
    );
    if (overrideError) throw overrideError;
  }
  accounts.push({ name, email, password, role });
}

const securityAdministrator = accounts.find((account) => account.name === "security-admin");
const runtimeClient = createClient(url, publishableKey, { auth: { persistSession: false, autoRefreshToken: false } });
const { error: signInError } = await runtimeClient.auth.signInWithPassword({
  email: securityAdministrator.email,
  password: securityAdministrator.password
});
if (signInError) throw signInError;
const { error: runtimeError } = await runtimeClient.rpc("set_system_runtime_environment", {
  p_environment: "test",
  p_reason_code: "initial_configuration",
  p_reason_detail: `Bootstrap do ensaio operacional ${runId}`
});
if (runtimeError) throw runtimeError;
await runtimeClient.auth.signOut();

await mkdir(path.dirname(output), { recursive: true });
await writeFile(output, JSON.stringify({ runId, accounts }, null, 2), "utf8");
console.log(`E2E_SYNTHETIC_USERS_READY=${accounts.length}`);
