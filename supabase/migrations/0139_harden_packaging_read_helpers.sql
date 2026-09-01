-- Keep packaging read helpers internal without changing the authenticated,
-- RLS-governed projections introduced by migration 0068.

create or replace view public.cad_embalagem_configuracoes_atuais
with (security_invoker = true)
as
with latest_event as (
  select distinct on (version.embalagem_id)
    version.embalagem_id,
    activation.embalagem_versao_id,
    activation.tipo_evento,
    activation.created_at as activated_at
  from public.cad_embalagem_versao_ativacoes activation
  join public.cad_embalagem_versoes version
    on version.id = activation.embalagem_versao_id
  order by version.embalagem_id, activation.created_at desc, activation.id desc
)
select
  package.id as embalagem_id,
  package.descricao,
  package.unidade_id,
  package.volume_litros,
  version.id as embalagem_versao_id,
  version.versao,
  version.peso_tara_kg,
  version.cubagem_m3,
  version.vigencia_inicio,
  version.vigencia_fim,
  latest_event.activated_at,
  version.unidades_embalagem_por_litro
from latest_event
join public.cad_embalagem_versoes version
  on version.id = latest_event.embalagem_versao_id
join public.cad_embalagens package
  on package.id = version.embalagem_id
where latest_event.tipo_evento = 'ativacao'
  and coalesce(
    (
      select review.decisao
      from public.cad_embalagem_versao_revisoes review
      where review.embalagem_versao_id = version.id
      order by review.created_at desc, review.id desc
      limit 1
    ),
    version.review_status
  ) = 'approved'
  and package.status = 'active';

create or replace view public.cad_embalagem_componentes_atuais
with (security_invoker = true)
as
select
  current_package.embalagem_id,
  current_package.embalagem_versao_id,
  component.id as componente_id,
  component.materia_prima_id,
  component.quantidade,
  component.unidade_id,
  current_package.unidades_embalagem_por_litro,
  component.quantidade_un_l
from public.cad_embalagem_configuracoes_atuais current_package
join public.cad_embalagem_componentes component
  on component.embalagem_versao_id = current_package.embalagem_versao_id
where coalesce(
    (
      select review.decisao
      from public.cad_embalagem_versao_revisoes review
      where review.embalagem_versao_id = component.embalagem_versao_id
      order by review.created_at desc, review.id desc
      limit 1
    ),
    (
      select version.review_status
      from public.cad_embalagem_versoes version
      where version.id = component.embalagem_versao_id
    )
  ) = 'approved'
  and not exists (
    select 1
    from public.cad_embalagem_componente_eventos event
    where event.embalagem_componente_id = component.id
      and event.tipo_evento = 'remocao'
  )
  and component.quantidade_un_l is not null;

revoke all on function public.current_cad_embalagem_versao_review_status(bigint)
  from public, anon, authenticated;
revoke all on function public.is_cad_embalagem_componente_active(bigint)
  from public, anon, authenticated;

grant select on public.cad_embalagem_configuracoes_atuais to authenticated;
grant select on public.cad_embalagem_componentes_atuais to authenticated;
revoke all on public.cad_embalagem_configuracoes_atuais from public, anon;
revoke all on public.cad_embalagem_componentes_atuais from public, anon;

comment on function public.current_cad_embalagem_versao_review_status(bigint) is
  'Internal packaging lifecycle helper. Application reads use RLS-governed security-invoker views.';
comment on function public.is_cad_embalagem_componente_active(bigint) is
  'Internal packaging lifecycle helper. Application reads use RLS-governed security-invoker views.';
