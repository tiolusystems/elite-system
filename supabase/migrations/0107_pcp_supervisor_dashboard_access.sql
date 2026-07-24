-- The production overview is a supervisory read model, not an operator default.

insert into public.permission_actions(
  action_key,
  module,
  description,
  default_allowed,
  sort_order,
  runtime_module_key,
  runtime_access_kind
)
values (
  'pcp.dashboard.view',
  'pcp',
  'Consultar painel supervisor da produção',
  false,
  327,
  'pcp',
  'read'
)
on conflict (action_key) do update set
  module = excluded.module,
  description = excluded.description,
  default_allowed = excluded.default_allowed,
  sort_order = excluded.sort_order,
  runtime_module_key = excluded.runtime_module_key,
  runtime_access_kind = excluded.runtime_access_kind;

create or replace function public.get_pcp_supervisor_dashboard()
returns jsonb
language plpgsql
security definer
set search_path = public
as $$
declare
  v_ops_aguardando bigint;
  v_ops_em_producao bigint;
  v_componentes_sem_reserva bigint;
  v_lotes_bloqueados bigint;
begin
  perform public.require_current_user_permission('pcp.dashboard.view');

  select count(*)
    into v_ops_aguardando
    from public.pcp_ordens_producao op
   where op.status in ('draft', 'planned');

  select count(*)
    into v_ops_em_producao
    from public.pcp_ordens_producao op
   where op.status = 'in_process';

  select count(*)
    into v_componentes_sem_reserva
    from public.pcp_op_componentes_planejados component
    join public.pcp_ordens_producao op on op.id = component.op_id
   where op.status in ('draft', 'planned')
     and component.status = 'pending';

  select count(*)
    into v_lotes_bloqueados
    from (
      select lot.id
        from public.est_lotes_mp lot
       where lot.status = 'bloqueado'
      union all
      select lot.id
        from public.est_lotes_pi lot
       where lot.status = 'bloqueado'
      union all
      select lot.id
        from public.est_lotes_pa lot
       where lot.status = 'bloqueado'
    ) blocked_lots;

  return jsonb_build_object(
    'ops_aguardando', v_ops_aguardando,
    'ops_em_producao', v_ops_em_producao,
    'componentes_sem_reserva', v_componentes_sem_reserva,
    'lotes_bloqueados', v_lotes_bloqueados
  );
end;
$$;

revoke all on function public.get_pcp_supervisor_dashboard() from public;
revoke all on function public.get_pcp_supervisor_dashboard() from anon;
grant execute on function public.get_pcp_supervisor_dashboard() to authenticated;

comment on function public.get_pcp_supervisor_dashboard() is
  'Returns production exception counts only after the atomic pcp.dashboard.view permission check.';
