\set ON_ERROR_STOP on
\pset tuples_only on
\pset format unaligned

select jsonb_object_agg(domain_name, fingerprint order by domain_name)
from (
  select 'cadastros' domain_name, md5(coalesce(string_agg(row_to_json(t)::text, '|' order by row_to_json(t)::text), '')) fingerprint from public.cad_clientes t
  union all select 'pedidos', md5(coalesce(string_agg(row_to_json(t)::text, '|' order by row_to_json(t)::text), '')) from public.com_pedidos t
  union all select 'estoque', md5(coalesce(string_agg(row_to_json(t)::text, '|' order by row_to_json(t)::text), '')) from public.est_lotes_pa t
  union all select 'pcp', md5(coalesce(string_agg(row_to_json(t)::text, '|' order by row_to_json(t)::text), '')) from public.pcp_formula_versoes t
  union all select 'producao', md5(coalesce(string_agg(row_to_json(t)::text, '|' order by row_to_json(t)::text), '')) from public.pcp_ordens_producao t
  union all select 'romaneio', md5(coalesce(string_agg(row_to_json(t)::text, '|' order by row_to_json(t)::text), '')) from public.exp_romaneios t
  union all select 'faturamento', md5(coalesce(string_agg(row_to_json(t)::text, '|' order by row_to_json(t)::text), '')) from public.fat_notas_fiscais t
  union all select 'financeiro', md5(coalesce(string_agg(row_to_json(t)::text, '|' order by row_to_json(t)::text), '')) from public.fin_pedido_planos_pagamento t
  union all select 'metas', md5(coalesce(string_agg(row_to_json(t)::text, '|' order by row_to_json(t)::text), '')) from public.com_meta_periodos t
  union all select 'importacao', md5(coalesce(string_agg(row_to_json(t)::text, '|' order by row_to_json(t)::text), '')) from public.migration_batches t
  union all select 'seguranca', md5(coalesce(string_agg(row_to_json(t)::text, '|' order by row_to_json(t)::text), '')) from public.user_profiles t
) fingerprints;
