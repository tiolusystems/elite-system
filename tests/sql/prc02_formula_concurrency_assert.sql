\set ON_ERROR_STOP on
do $$
declare v_rows integer; v_codes integer;
begin
  select count(*),count(distinct f.codigo) into v_rows,v_codes
  from public.prc02_formula_concurrency_probe p
  join public.prc_formula_versoes v on v.id=p.version_id
  join public.prc_formula_perfis f on f.id=v.formula_id
  where f.codigo ~ '^FML-[0-9]{8}$' and v.versao=1;
  if v_rows<>2 or v_codes<>2 then raise exception 'concurrent FML issuance failed: rows %, codes %',v_rows,v_codes; end if;
  if (select count(*) from public.prc_requisicoes where idempotency_key in (
    '15120000-0000-4000-8000-000000000021'::uuid,
    '15120000-0000-4000-8000-000000000022'::uuid))<>2 then
    raise exception 'concurrent formula requests not recorded';
  end if;
end $$;
\echo PG_PRC02_FML_CONCURRENCY_OK
