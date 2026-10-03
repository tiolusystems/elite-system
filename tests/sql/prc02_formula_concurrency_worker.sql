\set ON_ERROR_STOP on
begin;
set local application_name = 'prc02_fml_concurrency';
select set_config('request.jwt.claim.sub','15120000-0000-4000-8000-000000000001',true);
select pg_sleep(3);
insert into public.prc02_formula_concurrency_probe(worker,version_id)
select :'worker',public.salvar_prc_formula_versao_idempotente(
  :'request_key'::uuid,null,:'formula_name',
  jsonb_build_object('schema','prc-formula-ast-v1','result_unit','BRL_L','root',jsonb_build_object('kind','parameter','code','materia_prima')),
  jsonb_build_object('schema','prc-formula-ast-v1','result_unit','BRL_L','root',jsonb_build_object('kind','variable','name','cash_price')),
  array['materia_prima'],
  (select id from public.prc_grade_prazo_versoes order by id desc limit 1),2,
  'Criacao concorrente de formula para teste');
commit;
