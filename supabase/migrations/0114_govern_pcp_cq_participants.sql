-- Govern PCP/CQ participants by person ID while preserving legacy snapshots.

alter table public.pcp_op_cq_participantes
  drop constraint if exists pcp_cq_participantes_papel_check;

alter table public.pcp_op_cq_participantes
  add constraint pcp_cq_participantes_papel_check check (
    papel in (
      'separador_mp',
      'conferente_mp',
      'formulador',
      'responsavel_cq',
      'responsavel_liberacao'
    )
  );

create or replace function public.finalizar_pcp_op_relacional(
  p_op_id bigint,
  p_outputs_jsonb jsonb,
  p_cq_status text,
  p_ph numeric,
  p_densidade_kg_l numeric,
  p_volume_l numeric,
  p_massa_kg numeric,
  p_temperatura_c numeric,
  p_separador_pessoa_id bigint,
  p_conferente_pessoa_id bigint,
  p_formulador_pessoa_ids bigint[],
  p_responsavel_cq_pessoa_id bigint,
  p_responsavel_liberacao_pessoa_id bigint,
  p_observacao text default null
)
returns bigint
language plpgsql
security definer
set search_path = public
as $$
declare
  v_actor uuid;
  v_result bigint;
  v_cq_resultado_id bigint;
  v_separador_nome text;
  v_conferente_nome text;
  v_responsavel_cq_nome text;
  v_responsavel_liberacao_nome text;
  v_formuladores_nomes jsonb;
  v_formulador record;
  v_expected_people integer;
  v_active_people integer;
  v_participants_after jsonb;
  v_audit_context jsonb;
begin
  v_audit_context := public.begin_audited_rpc(
    'pcp.op.finish',
    'pcp',
    'pcp_op_cq_participantes',
    'status_transition',
    jsonb_build_object(
      'event', 'register_relational_participants',
      'op_id', p_op_id,
      'source', 'finalizar_pcp_op_relacional'
    )
  );

  if p_separador_pessoa_id is null
     or p_conferente_pessoa_id is null
     or p_responsavel_cq_pessoa_id is null
     or p_responsavel_liberacao_pessoa_id is null then
    raise exception 'all required CQ participant IDs must be informed';
  end if;

  if p_formulador_pessoa_ids is null
     or cardinality(p_formulador_pessoa_ids) < 1
     or cardinality(p_formulador_pessoa_ids) > 3 then
    raise exception 'one to three formulator person IDs must be informed';
  end if;

  if cardinality(p_formulador_pessoa_ids) <> (
    select count(distinct person_id)
      from unnest(p_formulador_pessoa_ids) as person_id
  ) then
    raise exception 'formulator person IDs must not be repeated';
  end if;

  select count(distinct person_id)
    into v_expected_people
    from unnest(array[
      p_separador_pessoa_id,
      p_conferente_pessoa_id,
      p_responsavel_cq_pessoa_id,
      p_responsavel_liberacao_pessoa_id
    ] || p_formulador_pessoa_ids) as person_id;

  select count(*)
    into v_active_people
    from public.cad_pessoas_comerciais person
   where person.id = any (
     array[
       p_separador_pessoa_id,
       p_conferente_pessoa_id,
       p_responsavel_cq_pessoa_id,
       p_responsavel_liberacao_pessoa_id
     ] || p_formulador_pessoa_ids
   )
     and person.status = 'active';

  if v_active_people <> v_expected_people then
    raise exception 'all CQ participants must reference active registered people';
  end if;

  select nome into strict v_separador_nome
    from public.cad_pessoas_comerciais
   where id = p_separador_pessoa_id and status = 'active';
  select nome into strict v_conferente_nome
    from public.cad_pessoas_comerciais
   where id = p_conferente_pessoa_id and status = 'active';
  select nome into strict v_responsavel_cq_nome
    from public.cad_pessoas_comerciais
   where id = p_responsavel_cq_pessoa_id and status = 'active';
  select nome into strict v_responsavel_liberacao_nome
    from public.cad_pessoas_comerciais
   where id = p_responsavel_liberacao_pessoa_id and status = 'active';

  select jsonb_agg(to_jsonb(person.nome) order by input.ordem)
    into v_formuladores_nomes
    from unnest(p_formulador_pessoa_ids) with ordinality as input(pessoa_id, ordem)
    join public.cad_pessoas_comerciais person
      on person.id = input.pessoa_id
     and person.status = 'active';

  v_result := public.finalizar_pcp_op(
    p_op_id,
    p_outputs_jsonb,
    p_cq_status,
    p_ph,
    p_densidade_kg_l,
    p_volume_l,
    p_massa_kg,
    p_temperatura_c,
    v_separador_nome,
    v_conferente_nome,
    v_formuladores_nomes,
    p_observacao
  );

  select id
    into strict v_cq_resultado_id
    from public.pcp_op_cq_resultados
   where op_id = p_op_id;

  v_actor := public.current_actor_id();

  update public.pcp_op_cq_participantes
     set pessoa_comercial_id = p_separador_pessoa_id,
         nome_snapshot = v_separador_nome
   where cq_resultado_id = v_cq_resultado_id
     and papel = 'separador_mp'
     and ordem = 1;

  update public.pcp_op_cq_participantes
     set pessoa_comercial_id = p_conferente_pessoa_id,
         nome_snapshot = v_conferente_nome
   where cq_resultado_id = v_cq_resultado_id
     and papel = 'conferente_mp'
     and ordem = 1;

  for v_formulador in
    select input.ordem::integer ordem, person.id pessoa_id, person.nome
      from unnest(p_formulador_pessoa_ids) with ordinality as input(pessoa_id, ordem)
      join public.cad_pessoas_comerciais person
        on person.id = input.pessoa_id
       and person.status = 'active'
     order by input.ordem
  loop
    update public.pcp_op_cq_participantes
       set pessoa_comercial_id = v_formulador.pessoa_id,
           nome_snapshot = v_formulador.nome
     where cq_resultado_id = v_cq_resultado_id
       and papel = 'formulador'
       and ordem = v_formulador.ordem;
  end loop;

  insert into public.pcp_op_cq_participantes(
    cq_resultado_id,
    op_id,
    papel,
    ordem,
    nome_snapshot,
    pessoa_comercial_id,
    created_by
  )
  values
    (
      v_cq_resultado_id,
      p_op_id,
      'responsavel_cq',
      1,
      v_responsavel_cq_nome,
      p_responsavel_cq_pessoa_id,
      v_actor
    ),
    (
      v_cq_resultado_id,
      p_op_id,
      'responsavel_liberacao',
      1,
      v_responsavel_liberacao_nome,
      p_responsavel_liberacao_pessoa_id,
      v_actor
    );

  select jsonb_agg(
    jsonb_build_object(
      'pessoa_id', participant.pessoa_comercial_id,
      'papel', participant.papel,
      'ordem', participant.ordem,
      'nome_snapshot', participant.nome_snapshot,
      'registrado_por', participant.created_by,
      'registrado_em', participant.created_at
    )
    order by participant.papel, participant.ordem
  )
    into v_participants_after
    from public.pcp_op_cq_participantes participant
   where participant.cq_resultado_id = v_cq_resultado_id;

  perform public.log_audited_rpc_change(
    'pcp',
    'pcp_op_cq_participantes',
    v_cq_resultado_id::text,
    'pcp.cq_participants_registered',
    'pcp.op.finish',
    v_audit_context,
    null,
    v_participants_after,
    jsonb_build_object(
      'op_id', p_op_id,
      'source', 'finalizar_pcp_op_relacional'
    ),
    'database_rpc'
  );

  return v_result;
end;
$$;

revoke all on function public.finalizar_pcp_op(
  bigint, jsonb, text, numeric, numeric, numeric, numeric, numeric,
  text, text, jsonb, text
) from authenticated;

revoke all on function public.finalizar_pcp_op_relacional(
  bigint, jsonb, text, numeric, numeric, numeric, numeric, numeric,
  bigint, bigint, bigint[], bigint, bigint, text
) from public, anon;

grant execute on function public.finalizar_pcp_op_relacional(
  bigint, jsonb, text, numeric, numeric, numeric, numeric, numeric,
  bigint, bigint, bigint[], bigint, bigint, text
) to authenticated;

comment on function public.finalizar_pcp_op_relacional(
  bigint, jsonb, text, numeric, numeric, numeric, numeric, numeric,
  bigint, bigint, bigint[], bigint, bigint, text
) is
  'Finaliza a OP e registra separacao, conferencia, formulacao, CQ e liberacao exclusivamente por pessoas ativas e relacionais.';

comment on table public.pcp_op_cq_participantes is
  'Participantes historicos da OP/CQ. nome_snapshot preserva a exibicao; pessoa_comercial_id e a fonte relacional para novos fatos.';
