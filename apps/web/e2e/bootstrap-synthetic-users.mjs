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
  ["seller", "comercial", [
    "pedidos.create", "pedidos.view", "pedidos.price_reference.resolve",
    "pedidos.payment_terms.manage", "pedidos.commercial_context.manage",
    "pedidos.practiced_price.record", "pedidos.commercial_review.",
    "pedidos.commercial_comparison.view"
  ]],
  ["price-list-admin", "comercial", ["pedidos.price_lists."]],
  ["order-reviewer", "comercial", ["pedidos.credit.review"]],
  ["credit-authority", "auditoria", ["financeiro.credit_limits.adjust"]],
  ["stock-operator", "estoque", ["estoque."]],
  ["production-operator", "producao", ["pcp."]],
  ["quality-operator", "producao", ["qualidade.", "pcp.op.finish"]],
  ["shipping-operator", "expedicao", ["romaneios.", "estoque.pa.issue.romaneio"]],
  ["fiscal-reference", "expedicao", ["faturamento.external_references."]],
  ["commission-assign", "auditoria", ["pedidos.commissions.assign"]],
  ["finance-receipts", "auditoria", ["financeiro.receipts."]],
  ["finance-commissions", "auditoria", ["financeiro.commissions."]],
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
const seller = accounts.find((account) => account.name === "seller");
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
const orderReadOnlyUser = accounts.find((account) => account.name === "order-reviewer");
const orderReadOnlyDenials = `insert into public.user_permission_overrides(user_id, action_key, allowed, updated_by)\n` +
  `select ${sqlLiteral(orderReadOnlyUser.id)}::uuid, action_key, false, ${sqlLiteral(orderReadOnlyUser.id)}::uuid\n` +
  `from public.permission_actions\n` +
  `where action_key in ('pcp.op.create', 'pcp.op.reserve_components', 'pcp.op.reserve_override_fifo', 'pcp.op.start', 'pcp.op.cancel')\n` +
  `on conflict (user_id, action_key) do update set allowed = false, updated_by = excluded.updated_by;`;
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

${orderReadOnlyDenials}

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

do $price_list_fixture$
declare
  v_actor uuid := ${sqlLiteral(securityAdministrator.id)}::uuid;
  v_product_a_id bigint;
  v_product_b_id bigint;
  v_packaging_a_id bigint;
  v_packaging_b_id bigint;
begin
  insert into public.cad_produtos_base(codigo_produto, nome, nome_norm, status, created_by, updated_by)
  values ('9137', 'Produto Lista Preco E2E', 'produto lista preco e2e', 'active', v_actor, v_actor)
  returning id into v_product_a_id;
  insert into public.cad_produtos_base(codigo_produto, nome, nome_norm, status, created_by, updated_by)
  values ('9138', 'Produto Alternativo Lista Preco E2E', 'produto alternativo lista preco e2e', 'active', v_actor, v_actor)
  returning id into v_product_b_id;

  insert into public.cad_embalagens(
    descricao, descricao_norm, unidade, volume_litros, status, unidade_id, origem_dados, created_by, updated_by
  ) values (
    'Embalagem Lista Preco E2E 20 L', 'embalagem lista preco e2e 20 l', 'UN', 20, 'active',
    (select id from public.cad_unidades_medida where lower(codigo) = 'un'), 'sistema', v_actor, v_actor
  ) returning id into v_packaging_a_id;
  insert into public.cad_embalagens(
    descricao, descricao_norm, unidade, volume_litros, status, unidade_id, origem_dados, created_by, updated_by
  ) values (
    'Embalagem Alternativa Lista Preco E2E 10 L', 'embalagem alternativa lista preco e2e 10 l', 'UN', 10, 'active',
    (select id from public.cad_unidades_medida where lower(codigo) = 'un'), 'sistema', v_actor, v_actor
  ) returning id into v_packaging_b_id;

  insert into public.cad_produto_embalagens(
    produto_id, embalagem_id, codigo_item, status, origem_dados, created_by, updated_by
  ) values (v_product_a_id, v_packaging_a_id, 'PLX137-20L', 'active', 'sistema', v_actor, v_actor);
  insert into public.cad_produto_embalagens(
    produto_id, embalagem_id, codigo_item, status, origem_dados, created_by, updated_by
  ) values (v_product_b_id, v_packaging_b_id, 'PLX138-10L', 'active', 'sistema', v_actor, v_actor);
end;
$price_list_fixture$;

do $f2b_fixture$
declare
  v_actor uuid := ${sqlLiteral(securityAdministrator.id)}::uuid;
  v_seller_user uuid := ${sqlLiteral(seller.id)}::uuid;
  v_seller_id bigint;
  v_client_id bigint;
  v_property_id bigint;
  v_product_a_id bigint;
  v_product_b_id bigint;
  v_packaging_a_id bigint;
  v_packaging_b_id bigint;
  v_presentation_a_id bigint;
  v_presentation_b_id bigint;
  v_list_id bigint;
  v_version_id bigint;
  v_version_item_id bigint;
  v_unit_l_id bigint;
  v_today date := (clock_timestamp() at time zone 'America/Sao_Paulo')::date;
begin
  insert into public.cad_pessoas_comerciais(
    nome, nome_norm, tipo_comercial, papeis_json, status, user_profile_id, created_by, updated_by
  ) values (
    'Vendedor Revisao Comercial E2E', 'vendedor revisao comercial e2e',
    'vendedor_direto_elite', '["vendedor"]', 'active', v_seller_user, v_actor, v_actor
  ) returning id into v_seller_id;

  insert into public.cad_clientes(nome, nome_norm, cidade, uf, status, created_by, updated_by)
  values ('Cliente Revisao Comercial E2E', 'cliente revisao comercial e2e', 'Campinas', 'SP', 'active', v_actor, v_actor)
  returning id into v_client_id;

  insert into public.cad_cliente_propriedades(cliente_id, nome, cidade, uf, status, created_by, updated_by)
  values (v_client_id, 'Propriedade Revisao Comercial E2E', 'Campinas', 'SP', 'active', v_actor, v_actor)
  returning id into v_property_id;

  insert into public.cad_cliente_vendedores(
    cliente_id, pessoa_id, papel_vinculo_id, status, vigencia_inicio, origem_dados, created_by, updated_by
  ) values (
    v_client_id, v_seller_id,
    (select id from public.cad_cliente_vinculo_papeis where codigo_norm = 'atende'),
    'active', v_today, 'sistema', v_actor, v_actor
  );

  insert into public.cad_produtos_base(codigo_produto, nome, nome_norm, status, created_by, updated_by)
  values ('9211', 'Produto Desconto E2E', 'produto desconto e2e', 'active', v_actor, v_actor)
  returning id into v_product_a_id;
  insert into public.cad_produtos_base(codigo_produto, nome, nome_norm, status, created_by, updated_by)
  values ('9212', 'Produto Acima E2E', 'produto acima e2e', 'active', v_actor, v_actor)
  returning id into v_product_b_id;

  insert into public.cad_embalagens(
    descricao, descricao_norm, unidade, volume_litros, status, unidade_id, origem_dados, created_by, updated_by
  ) values (
    'Embalagem Desconto E2E', 'embalagem desconto e2e', 'UN', 20, 'active',
    (select id from public.cad_unidades_medida where lower(codigo) = 'un'), 'sistema', v_actor, v_actor
  ) returning id into v_packaging_a_id;
  insert into public.cad_embalagens(
    descricao, descricao_norm, unidade, volume_litros, status, unidade_id, origem_dados, created_by, updated_by
  ) values (
    'Embalagem Acima E2E', 'embalagem acima e2e', 'UN', 20, 'active',
    (select id from public.cad_unidades_medida where lower(codigo) = 'un'), 'sistema', v_actor, v_actor
  ) returning id into v_packaging_b_id;

  insert into public.cad_produto_embalagens(
    produto_id, embalagem_id, codigo_item, status, origem_dados, created_by, updated_by
  ) values (v_product_a_id, v_packaging_a_id, 'E2B-A-20L', 'active', 'sistema', v_actor, v_actor)
  returning id into v_presentation_a_id;
  insert into public.cad_produto_embalagens(
    produto_id, embalagem_id, codigo_item, status, origem_dados, created_by, updated_by
  ) values (v_product_b_id, v_packaging_b_id, 'E2B-B-20L', 'active', 'sistema', v_actor, v_actor)
  returning id into v_presentation_b_id;

  select id into v_unit_l_id from public.cad_unidades_medida where lower(codigo) = 'l';
  insert into public.com_listas_preco(codigo, nome, created_by)
  values ('E2BF2B', 'Lista Revisao Comercial E2E', v_actor) returning id into v_list_id;
  insert into public.com_lista_preco_versoes(
    lista_id, numero, vigencia_inicio, motivo, created_by, updated_by
  ) values (v_list_id, 1, v_today, 'Fixture descartavel da revisao comercial', v_actor, v_actor)
  returning id into v_version_id;

  insert into public.com_lista_preco_versao_itens(
    versao_id, produto_embalagem_id, unidade_precificacao_id,
    quantidade_unidade_precificacao_por_apresentacao, created_by
  ) values (v_version_id, v_presentation_a_id, v_unit_l_id, 20, v_actor)
  returning id into v_version_item_id;
  insert into public.com_lista_preco_versao_precos(
    versao_item_id, prazo_dias, valor_centavos_por_litro,
    valor_centavos_por_unidade_precificacao, created_by
  ) values (v_version_item_id, 0, 100, 100, v_actor);

  insert into public.com_lista_preco_versao_itens(
    versao_id, produto_embalagem_id, unidade_precificacao_id,
    quantidade_unidade_precificacao_por_apresentacao, created_by
  ) values (v_version_id, v_presentation_b_id, v_unit_l_id, 20, v_actor)
  returning id into v_version_item_id;
  insert into public.com_lista_preco_versao_precos(
    versao_item_id, prazo_dias, valor_centavos_por_litro,
    valor_centavos_por_unidade_precificacao, created_by
  ) values (v_version_item_id, 0, 100, 100, v_actor);

  insert into public.com_lista_preco_regras(versao_id, codigo, descricao, prioridade, created_by)
  values (v_version_id, 'GERAL', 'Regra geral da fixture F2B', 0, v_actor);
  insert into public.com_lista_preco_publicacoes(
    versao_id, conteudo_hash, motivo, published_by, published_at
  ) values (v_version_id, md5('E2BF2B'), 'Publicacao da fixture descartavel F2B', v_actor, clock_timestamp());
end;
$f2b_fixture$;

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
