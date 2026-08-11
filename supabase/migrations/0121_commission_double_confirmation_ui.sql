-- COMM-02A: interface transacional de comissionamento e idempotencia da dupla confirmacao.
-- Depende de 0120_commission_policy_domain.sql.
--
-- Esta migration nao implementa ainda a materializacao automatica por politica.
-- Ela fecha o fluxo manual seguro: proposta -> revisao -> confirmacao.

alter table public.com_comissao_alteracao_solicitacoes
  add column if not exists request_key uuid;

create unique index if not exists idx_com_comissao_alteracao_request_key
  on public.com_comissao_alteracao_solicitacoes(requested_by, request_key)
  where request_key is not null;

comment on column public.com_comissao_alteracao_solicitacoes.request_key is
  'Chave idempotente fornecida pela interface para impedir propostas duplicadas por retry ou duplo clique.';

create or replace function public.propor_com_pedido_comissao_idempotente(
  p_request_key uuid,
  p_pedido_id bigint,
  p_pessoa_id bigint,
  p_papel_comissao text,
  p_percentual_comissao numeric,
  p_justificativa text
)
returns jsonb
language plpgsql
security definer
set search_path = public
as $$
declare
  v_actor uuid;
  v_existing public.com_comissao_alteracao_solicitacoes%rowtype;
  v_result jsonb;
  v_request_id uuid;
begin
  perform public.require_current_user_permission('financeiro.commissions.revision.request');
  perform public.require_current_user_permission('pedidos.commissions.assign');

  if p_request_key is null then
    raise exception 'commission request key is required';
  end if;

  v_actor := public.current_actor_id();
  if v_actor is null then
    raise exception 'active user is required';
  end if;

  perform pg_advisory_xact_lock(
    hashtextextended('commission_change_request:' || p_request_key::text, 0)
  );

  select *
    into v_existing
    from public.com_comissao_alteracao_solicitacoes request
   where request.requested_by = v_actor
     and request.request_key = p_request_key
   for update;

  if v_existing.id is not null then
    if v_existing.pedido_id is distinct from p_pedido_id
       or v_existing.pessoa_id is distinct from p_pessoa_id
       or v_existing.papel_comissao is distinct from p_papel_comissao
       or v_existing.percentual_comissao is distinct from p_percentual_comissao
       or btrim(v_existing.justificativa) is distinct from btrim(p_justificativa) then
      raise exception 'commission request key reused with different payload';
    end if;

    return jsonb_build_object(
      'solicitacao_id', v_existing.id,
      'status', v_existing.status,
      'expires_at', v_existing.expires_at,
      'preview', v_existing.preview_json,
      'request_key', v_existing.request_key,
      'comissionado_id', v_existing.comissionado_id
    );
  end if;

  v_result := public.propor_com_pedido_comissao(
    p_pedido_id,
    p_pessoa_id,
    p_papel_comissao,
    p_percentual_comissao,
    p_justificativa
  );

  v_request_id := nullif(v_result->>'solicitacao_id', '')::uuid;

  update public.com_comissao_alteracao_solicitacoes
     set request_key = p_request_key
   where id = v_request_id
     and requested_by = v_actor;

  if not found then
    raise exception 'commission change request could not be keyed';
  end if;

  return v_result || jsonb_build_object('request_key', p_request_key);
end;
$$;

revoke all on function public.propor_com_pedido_comissao_idempotente(
  uuid, bigint, bigint, text, numeric, text
) from public, anon;
grant execute on function public.propor_com_pedido_comissao_idempotente(
  uuid, bigint, bigint, text, numeric, text
) to authenticated;

revoke execute on function public.propor_com_pedido_comissao(
  bigint, bigint, text, numeric, text
) from authenticated;

create or replace function public.confirmar_com_pedido_comissao_idempotente(
  p_solicitacao_id uuid
)
returns jsonb
language plpgsql
security definer
set search_path = public
as $$
declare
  v_actor uuid;
  v_request public.com_comissao_alteracao_solicitacoes%rowtype;
  v_release_count integer := 0;
begin
  perform public.require_current_user_permission('financeiro.commissions.revision.confirm');
  perform public.require_current_user_permission('pedidos.commissions.assign');

  if p_solicitacao_id is null then
    raise exception 'commission change request id is required';
  end if;

  v_actor := public.current_actor_id();

  select *
    into v_request
    from public.com_comissao_alteracao_solicitacoes request
   where request.id = p_solicitacao_id
   for update;

  if v_request.id is null then
    raise exception 'commission change request not found';
  end if;
  if v_request.requested_by <> v_actor then
    raise exception 'commission change request must be confirmed by the requesting operator';
  end if;

  if v_request.status = 'confirmed' then
    select count(*)
      into v_release_count
      from public.com_comissao_liberacoes release
     where release.comissionado_id = v_request.comissionado_id
       and release.status = 'liberada';

    return jsonb_build_object(
      'solicitacao_id', v_request.id,
      'status', 'confirmed',
      'comissionado_id', v_request.comissionado_id,
      'liberacoes_recebimentos_existentes', v_release_count,
      'idempotent_replay', true
    );
  end if;

  if v_request.status <> 'pending' then
    raise exception 'commission change request is not pending';
  end if;

  return public.confirmar_com_pedido_comissao(p_solicitacao_id);
end;
$$;

revoke all on function public.confirmar_com_pedido_comissao_idempotente(uuid)
  from public, anon;
grant execute on function public.confirmar_com_pedido_comissao_idempotente(uuid)
  to authenticated;

revoke execute on function public.confirmar_com_pedido_comissao(uuid)
  from authenticated;

comment on function public.propor_com_pedido_comissao_idempotente(
  uuid, bigint, bigint, text, numeric, text
) is
  'Etapa 1 idempotente: prepara e congela a revisao, sem criar novo direito de comissao.';

comment on function public.confirmar_com_pedido_comissao_idempotente(uuid) is
  'Etapa 2 idempotente: confirma uma revisao ainda valida; retry nao duplica direito ou liberacao.';
