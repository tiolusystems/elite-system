import { mkdir, writeFile } from "node:fs/promises";
import path from "node:path";
import { createClient } from "@supabase/supabase-js";

const url = process.env.NEXT_PUBLIC_SUPABASE_URL;
const serviceKey = process.env.SUPABASE_SERVICE_ROLE_KEY;
const password = process.env.E2E_SYNTHETIC_PASSWORD;
const output = process.env.E2E_ACCOUNTS_PATH;
const bootstrapSqlOutput = process.env.E2E_BOOTSTRAP_SQL_PATH;
const runId = process.env.E2E_RUN_ID;
if (!url || !serviceKey || !password || !output || !bootstrapSqlOutput || !runId) throw new Error("Synthetic E2E bootstrap environment is incomplete");

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
const accounts = [];
for (const [name, role, prefixes] of definitions) {
  const email = `hom-e2e-${runId}-${name}@test.invalid`;
  const { data, error } = await supabase.auth.admin.createUser({ email, password, email_confirm: true, user_metadata: { display_name: `HOM E2E ${name}` } });
  if (error || !data.user) throw error ?? new Error(`Could not create ${name}`);
  const userId = data.user.id;
  accounts.push({ id: userId, name, email, password, role, prefixes });
}

const securityAdministrator = accounts.find((account) => account.name === "security-admin");
const profileValues = accounts.map((account) =>
  `(${sqlLiteral(account.id)}::uuid, ${sqlLiteral(`HOM E2E ${account.name}`)}, ${sqlLiteral(account.role)}, 'active')`
).join(",\n  ");
const overrideStatements = accounts.map((account) => {
  const predicate = account.name === "security-admin"
    ? "true"
    : account.prefixes.map((prefix) => `action_key like ${sqlLiteral(`${prefix}%`)}`).join(" or ");
  return `insert into public.user_permission_overrides(user_id, action_key, allowed, updated_by)\n` +
    `select ${sqlLiteral(account.id)}::uuid, action_key, true, ${sqlLiteral(account.id)}::uuid\n` +
    `from public.permission_actions where ${predicate}\n` +
    `on conflict (user_id, action_key) do update set allowed = true, updated_by = excluded.updated_by;`;
}).join("\n\n");
const bootstrapSql = `\\set ON_ERROR_STOP on
begin;

insert into public.user_profiles(id, display_name, role, status)
values
  ${profileValues}
on conflict (id) do update set
  display_name = excluded.display_name,
  role = excluded.role,
  status = excluded.status;

${overrideStatements}

select set_config('request.jwt.claim.sub', ${sqlLiteral(securityAdministrator.id)}, true);
do $runtime$
begin
  if public.current_system_environment() = 'unconfigured' then
    perform public.set_system_runtime_environment(
      'test', 'initial_configuration', ${sqlLiteral(`Bootstrap do ensaio operacional ${runId}`)}
    );
  elsif public.current_system_environment() <> 'test' then
    raise exception 'synthetic bootstrap requires test environment';
  end if;
end;
$runtime$;

commit;
`;

await mkdir(path.dirname(output), { recursive: true });
await mkdir(path.dirname(bootstrapSqlOutput), { recursive: true });
await writeFile(output, JSON.stringify({
  runId,
  accounts: accounts.map((account) => ({
    id: account.id,
    name: account.name,
    email: account.email,
    password: account.password,
    role: account.role
  }))
}, null, 2), "utf8");
await writeFile(bootstrapSqlOutput, bootstrapSql, "utf8");
console.log(`E2E_SYNTHETIC_USERS_READY=${accounts.length}`);
console.log("E2E_BOOTSTRAP_SQL_READY=1");

function sqlLiteral(value) {
  return `'${String(value).replaceAll("'", "''")}'`;
}
