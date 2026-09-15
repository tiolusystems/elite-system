-- IAM-01A follow-up: self-service password capability and fail-closed route access.

-- Every active human access profile may change only its own password. This
-- capability grants no administrative or operational domain access.
insert into public.security_access_profile_permissions(profile_id, action_key)
select profile.id, 'security.change_own_password'
  from public.security_access_profiles profile
 where profile.status = 'active'
on conflict (profile_id, action_key) do nothing;

-- A seller can create and consult its own commercial orders, but price-list
-- management is not part of the seller workspace.
delete from public.security_access_profile_permissions permission
 using public.security_access_profiles profile
 where permission.profile_id = profile.id
   and profile.profile_key = 'comercial_vendedor'
   and permission.action_key = 'pedidos.price_lists.view';

-- Profile-adopted users resolve scope from effective IAM permissions. Accounts
-- still in the legacy transition retain the narrower pre-IAM portfolio scope.
create or replace function public.current_user_manages_seller(p_seller_id bigint)
returns boolean
language sql
stable
security definer
set search_path = public
as $$
  with actor as (
    select public.current_commercial_person_id() as person_id,
           exists (
             select 1
               from public.security_access_profile_adoptions adoption
              where adoption.user_id = auth.uid()
           ) as adopted
  )
  select ((actor.adopted and public.can_current_user('system.admin'))
          or (not actor.adopted and public.current_user_is_admin()))
    or exists (
      select 1
        from public.cad_pessoas_comerciais seller, actor
       where seller.id = p_seller_id
         and seller.status = 'active'
         and seller.vendedor_responsavel_id = actor.person_id
    )
    or exists (
      select 1
        from public.cad_pessoa_areas_comerciais seller_area
        join public.cad_areas_comerciais area
          on area.id = seller_area.area_id and area.status = 'active'
        cross join actor
       where seller_area.pessoa_id = p_seller_id
         and seller_area.status = 'active'
         and (seller_area.vigencia_inicio is null or seller_area.vigencia_inicio <= current_date)
         and (seller_area.vigencia_fim is null or seller_area.vigencia_fim >= current_date)
         and (area.gerente_id = actor.person_id or exists (
           select 1
             from public.cad_pessoa_areas_comerciais manager_area
            where manager_area.area_id = seller_area.area_id
              and manager_area.pessoa_id = actor.person_id
              and manager_area.papel_area in ('gerente', 'supervisor')
              and manager_area.status = 'active'
              and (manager_area.vigencia_inicio is null or manager_area.vigencia_inicio <= current_date)
              and (manager_area.vigencia_fim is null or manager_area.vigencia_fim >= current_date)
         ))
    )
    from actor
$$;

create or replace function public.can_current_user_view_order(p_order_id bigint)
returns boolean
language sql
stable
security definer
set search_path = public
as $$
  with actor as (
    select public.current_commercial_person_id() as person_id,
           exists (
             select 1
               from public.security_access_profile_adoptions adoption
              where adoption.user_id = auth.uid()
           ) as adopted
  )
  select exists (
    select 1
      from public.com_pedidos orders
      cross join actor
     where orders.id = p_order_id
        and (
          (actor.adopted and (
            public.can_current_user('system.admin')
            or public.can_current_user('pedidos.view')
          ))
          or (
            (not actor.adopted or public.can_current_user('pedidos.view.own'))
            and orders.vendedor_gerador_id = actor.person_id
          )
          or (
            (not actor.adopted or public.can_current_user('pedidos.view.team'))
            and public.current_user_manages_seller(orders.vendedor_gerador_id)
          )
          or (not actor.adopted and public.current_user_is_admin())
        )
  )
$$;

create or replace function public.can_current_user_view_client(p_client_id bigint)
returns boolean
language sql
stable
security definer
set search_path = public
as $$
  with actor as (
    select public.current_commercial_person_id() as person_id,
           exists (
             select 1
               from public.security_access_profile_adoptions adoption
              where adoption.user_id = auth.uid()
           ) as adopted
  )
  select (actor.adopted and (
            public.can_current_user('system.admin')
            or public.can_current_user('pedidos.view')
          ))
    or (not actor.adopted and public.current_user_is_admin())
    or exists (
      select 1
        from public.cad_cliente_vendedores relation
        join public.cad_cliente_vinculo_papeis role_catalog
          on role_catalog.id = relation.papel_vinculo_id
        cross join actor
        where relation.cliente_id = p_client_id
         and relation.status = 'active'
         and role_catalog.concede_visibilidade = true
         and (relation.vigencia_inicio is null or relation.vigencia_inicio <= current_date)
         and (relation.vigencia_fim is null or relation.vigencia_fim >= current_date)
         and (
            ((not actor.adopted or public.can_current_user('pedidos.view.own'))
              and relation.pessoa_id = actor.person_id)
            or ((not actor.adopted or public.can_current_user('pedidos.view.team'))
              and public.current_user_manages_seller(relation.pessoa_id))
          )
    )
    from actor
$$;

-- A view owner must not bypass the scoped RLS policy on com_pedidos.
alter view public.com_pedidos_kanban set (security_invoker = true);

-- The route resolver is a governed read surface. It evaluates the effective
-- IAM permission union before the web layer can render or route a workspace.
create or replace function public.get_current_route_capability_access(p_pathname text)
returns table (
  pathname text,
  module_key text,
  allowed boolean,
  reason text
)
language plpgsql
volatile
security definer
set search_path = public
as $$
declare
  v_pathname text;
  v_requirement record;
  v_allowed boolean;
begin
  if public.current_actor_id() is null then
    raise exception 'active user profile required';
  end if;

  v_pathname := coalesce(nullif(split_part(trim(p_pathname), '?', 1), ''), '/');
  if left(v_pathname, 1) <> '/' then
    v_pathname := '/' || v_pathname;
  end if;

  select * into v_requirement
    from (values
      ('/', 'core', array[]::text[], false),
      ('/modulos', 'core', array['system.admin']::text[], true),
      ('/cadastros', 'cadastros', array['cadastros.manage']::text[], true),
      ('/pedidos', 'pedidos', array['pedidos.view.own','pedidos.view.team','pedidos.view']::text[], true),
      ('/pedidos/listas-precos', 'pedidos', array['pedidos.price_lists.view']::text[], true),
      ('/pedidos/financeiro', 'financeiro', array['financeiro.receipts.view','financeiro.receipts.register','financeiro.commissions.view']::text[], true),
      ('/custos-precos', 'precificacao', array['precificacao.view']::text[], true),
      ('/kanban', 'pedidos', array['pedidos.view.own','pedidos.view.team','pedidos.view']::text[], true),
      ('/producao/ordens', 'pcp', array['pcp.op.view']::text[], true),
      ('/producao/transformacoes', 'pcp', array['pcp.op.view']::text[], true),
      ('/producao/formulas', 'pcp', array['pcp.formula.view']::text[], true),
      ('/producao/envase', 'pcp', array['pcp.envase.view']::text[], true),
      ('/producao/qualidade', 'pcp', array['pcp.op.view']::text[], true),
      ('/producao/garantias', 'pcp', array['pcp.guarantee.view']::text[], true),
      ('/producao/estoque', 'estoque', array['estoque.mp.view','estoque.pi.view','estoque.pa.view']::text[], true),
      ('/producao', 'pcp', array['pcp.op.view','pcp.formula.view','pcp.envase.view','pcp.pop.read','pcp.dashboard.view','pcp.guarantee.view']::text[], true),
      ('/romaneios', 'expedicao', array['romaneios.view']::text[], true),
      ('/importacao-xml', 'importacao', array['importacao.nfe_xml.stage']::text[], true),
      ('/qualidade/pops', 'pcp', array['pcp.pop.read']::text[], true),
      ('/qualidade/rastreabilidade', 'relatorios', array['qualidade.rastreabilidade.view']::text[], true),
      ('/relatorios', 'relatorios', array['reports.view']::text[], true),
      ('/importacao-historica/mp', 'auditoria', array['audit.view']::text[], true),
      ('/seguranca', 'seguranca', array['security.manage_users','security.manage_permissions']::text[], true),
      ('/login/trocar-senha', 'seguranca', array['security.change_own_password']::text[], false)
    ) as requirements(route_prefix, module_key, action_keys, match_children)
   where v_pathname = requirements.route_prefix
      or (
        requirements.match_children
        and requirements.route_prefix <> '/'
        and v_pathname like requirements.route_prefix || '/%'
      )
   order by length(requirements.route_prefix) desc
   limit 1;

  if not found then
    return query select v_pathname, null::text, false, 'route_not_registered'::text;
    return;
  end if;

  if coalesce(cardinality(v_requirement.action_keys), 0) = 0 then
    return query select v_pathname, v_requirement.module_key, true, 'allowed'::text;
    return;
  end if;

  select bool_or(public.can_current_user(action_key)) into v_allowed
    from unnest(v_requirement.action_keys) action(action_key);

  return query select v_pathname, v_requirement.module_key, coalesce(v_allowed, false),
    case when coalesce(v_allowed, false) then 'allowed' else 'permission_denied' end;
end;
$$;

revoke all on function public.get_current_route_capability_access(text) from public, anon;
grant execute on function public.get_current_route_capability_access(text) to authenticated;

comment on function public.get_current_route_capability_access(text) is
  'Fail-closed effective-permission route access resolver; module rollout availability is separate.';

-- PCP and stock facts are operationally sensitive. The legacy active-actor
-- read policies exposed them to every authenticated profile, including sellers.
-- Keep the web role read-only, but make each row visible only through a
-- capability that represents the owning operational surface.
insert into public.permission_actions(
  action_key,
  module,
  description,
  default_allowed,
  sort_order,
  runtime_module_key,
  runtime_access_kind
)
values
  ('pcp.formula.view', 'pcp', 'Consultar formulas versionadas de producao', false, 328, 'pcp', 'read'),
  ('pcp.op.view', 'pcp', 'Consultar ordens de producao, componentes, reservas, consumos e CQ', false, 329, 'pcp', 'read'),
  ('pcp.guarantee.view', 'pcp', 'Consultar garantias e conciliacoes tecnicas de producao', false, 330, 'pcp', 'read')
on conflict (action_key) do update set
  module = excluded.module,
  description = excluded.description,
  default_allowed = excluded.default_allowed,
  sort_order = excluded.sort_order,
  runtime_module_key = excluded.runtime_module_key,
  runtime_access_kind = excluded.runtime_access_kind;

insert into public.security_access_profile_permissions(profile_id, action_key)
select profile.id, grant_set.action_key
  from (values
    ('pcp_producao', 'pcp.formula.view'),
    ('pcp_producao', 'pcp.op.view'),
    ('pcp_producao', 'pcp.guarantee.view'),
    ('qualidade', 'pcp.formula.view'),
    ('qualidade', 'pcp.op.view')
  ) as grant_set(profile_key, action_key)
  join public.security_access_profiles profile
    on profile.profile_key = grant_set.profile_key
   and profile.status = 'active'
on conflict (profile_id, action_key) do nothing;

drop policy if exists "active user read pcp_formula_versoes" on public.pcp_formula_versoes;
drop policy if exists "active user read pcp_formula_itens" on public.pcp_formula_itens;
drop policy if exists "active user read pcp_formula_ativacoes" on public.pcp_formula_ativacoes;
drop policy if exists "active user read pcp_ordens_producao" on public.pcp_ordens_producao;
drop policy if exists "active user read pcp_op_componentes_planejados" on public.pcp_op_componentes_planejados;
drop policy if exists "active user read pcp_op_reservas_componentes" on public.pcp_op_reservas_componentes;
drop policy if exists "active user read pcp_op_consumos_componentes" on public.pcp_op_consumos_componentes;
drop policy if exists "active user read pcp_op_cq_resultados" on public.pcp_op_cq_resultados;
drop policy if exists "active user read pcp_op_produtos_gerados" on public.pcp_op_produtos_gerados;
drop policy if exists "active user read pcp_op_cq_participantes" on public.pcp_op_cq_participantes;
drop policy if exists "active user read pcp guarantee results" on public.pcp_op_garantia_resultados;
drop policy if exists "active user read pcp_garantia_fontes_historicas" on public.pcp_garantia_fontes_historicas;
drop policy if exists "active user read pcp_garantia_reconciliacao_eventos" on public.pcp_garantia_reconciliacao_eventos;

create policy "permitted read pcp_formula_versoes" on public.pcp_formula_versoes
  for select to authenticated using (public.can_current_user('pcp.formula.view'));
create policy "permitted read pcp_formula_itens" on public.pcp_formula_itens
  for select to authenticated using (public.can_current_user('pcp.formula.view'));
create policy "permitted read pcp_formula_ativacoes" on public.pcp_formula_ativacoes
  for select to authenticated using (public.can_current_user('pcp.formula.view'));
create policy "permitted read pcp_ordens_producao" on public.pcp_ordens_producao
  for select to authenticated using (public.can_current_user('pcp.op.view'));
create policy "permitted read pcp_op_componentes_planejados" on public.pcp_op_componentes_planejados
  for select to authenticated using (public.can_current_user('pcp.op.view'));
create policy "permitted read pcp_op_reservas_componentes" on public.pcp_op_reservas_componentes
  for select to authenticated using (public.can_current_user('pcp.op.view'));
create policy "permitted read pcp_op_consumos_componentes" on public.pcp_op_consumos_componentes
  for select to authenticated using (public.can_current_user('pcp.op.view'));
create policy "permitted read pcp_op_cq_resultados" on public.pcp_op_cq_resultados
  for select to authenticated using (public.can_current_user('pcp.op.view'));
create policy "permitted read pcp_op_produtos_gerados" on public.pcp_op_produtos_gerados
  for select to authenticated using (public.can_current_user('pcp.op.view'));
create policy "permitted read pcp_op_cq_participantes" on public.pcp_op_cq_participantes
  for select to authenticated using (public.can_current_user('pcp.op.view'));
create policy "permitted read pcp_op_garantia_resultados" on public.pcp_op_garantia_resultados
  for select to authenticated using (public.can_current_user('pcp.op.view'));
create policy "permitted read pcp_garantia_fontes_historicas" on public.pcp_garantia_fontes_historicas
  for select to authenticated using (public.can_current_user('pcp.guarantee.view'));
create policy "permitted read pcp_garantia_reconciliacao_eventos" on public.pcp_garantia_reconciliacao_eventos
  for select to authenticated using (public.can_current_user('pcp.guarantee.view'));

drop policy if exists "authenticated read est_lotes_pa" on public.est_lotes_pa;
drop policy if exists "authenticated read est_movimentos_pa" on public.est_movimentos_pa;
drop policy if exists "authenticated read est_reservas_pa" on public.est_reservas_pa;
drop policy if exists "authenticated read est_reserva_pa_eventos" on public.est_reserva_pa_eventos;
drop policy if exists "authenticated read est_lotes_mp" on public.est_lotes_mp;
drop policy if exists "authenticated read est_movimentos_mp" on public.est_movimentos_mp;
drop policy if exists "authenticated read est_lotes_pi" on public.est_lotes_pi;
drop policy if exists "authenticated read est_movimentos_pi" on public.est_movimentos_pi;

create policy "permitted read est_lotes_pa" on public.est_lotes_pa
  for select to authenticated using (public.can_current_user('estoque.pa.view'));
create policy "permitted read est_movimentos_pa" on public.est_movimentos_pa
  for select to authenticated using (public.can_current_user('estoque.pa.view'));
create policy "permitted read est_reservas_pa" on public.est_reservas_pa
  for select to authenticated using (public.can_current_user('estoque.pa.view'));
create policy "permitted read est_reserva_pa_eventos" on public.est_reserva_pa_eventos
  for select to authenticated using (public.can_current_user('estoque.pa.view'));
create policy "permitted read est_lotes_mp" on public.est_lotes_mp
  for select to authenticated using (public.can_current_user('estoque.mp.view'));
create policy "permitted read est_movimentos_mp" on public.est_movimentos_mp
  for select to authenticated using (public.can_current_user('estoque.mp.view'));
create policy "permitted read est_lotes_pi" on public.est_lotes_pi
  for select to authenticated using (public.can_current_user('estoque.pi.view'));
create policy "permitted read est_movimentos_pi" on public.est_movimentos_pi
  for select to authenticated using (public.can_current_user('estoque.pi.view'));

alter view public.pcp_formula_ativa set (security_invoker = true);
alter view public.est_lotes_pa_saldos set (security_invoker = true);
alter view public.est_lotes_mp_saldos set (security_invoker = true);
alter view public.est_lotes_pi_saldos set (security_invoker = true);

revoke all on public.pcp_formula_versoes,
  public.pcp_formula_itens,
  public.pcp_formula_ativacoes,
  public.pcp_ordens_producao,
  public.pcp_op_componentes_planejados,
  public.pcp_op_reservas_componentes,
  public.pcp_op_consumos_componentes,
  public.pcp_op_cq_resultados,
  public.pcp_op_produtos_gerados,
  public.pcp_op_cq_participantes,
  public.pcp_op_garantia_resultados,
  public.pcp_garantia_fontes_historicas,
  public.pcp_garantia_reconciliacao_eventos,
  public.est_lotes_pa,
  public.est_movimentos_pa,
  public.est_reservas_pa,
  public.est_reserva_pa_eventos,
  public.est_lotes_mp,
  public.est_movimentos_mp,
  public.est_lotes_pi,
  public.est_movimentos_pi,
  public.pcp_formula_ativa,
  public.est_lotes_pa_saldos,
  public.est_lotes_mp_saldos,
  public.est_lotes_pi_saldos
from public, anon;

grant select on public.pcp_formula_versoes,
  public.pcp_formula_itens,
  public.pcp_formula_ativacoes,
  public.pcp_ordens_producao,
  public.pcp_op_componentes_planejados,
  public.pcp_op_reservas_componentes,
  public.pcp_op_consumos_componentes,
  public.pcp_op_cq_resultados,
  public.pcp_op_produtos_gerados,
  public.pcp_op_cq_participantes,
  public.pcp_op_garantia_resultados,
  public.pcp_garantia_fontes_historicas,
  public.pcp_garantia_reconciliacao_eventos,
  public.est_lotes_pa,
  public.est_movimentos_pa,
  public.est_reservas_pa,
  public.est_reserva_pa_eventos,
  public.est_lotes_mp,
  public.est_movimentos_mp,
  public.est_lotes_pi,
  public.est_movimentos_pi,
  public.pcp_formula_ativa,
  public.est_lotes_pa_saldos,
  public.est_lotes_mp_saldos,
  public.est_lotes_pi_saldos
to authenticated;
