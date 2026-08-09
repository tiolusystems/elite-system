-- Restores the read contract lost when migration 0050 recreated these views.

do $$
declare
  v_view text;
begin
  foreach v_view in array array[
    'cad_garantias_produto_mapa_atuais',
    'cad_garantias_lote_mp_atuais'
  ]
  loop
    if not exists (
      select 1
        from pg_class relation
        join pg_namespace namespace on namespace.oid = relation.relnamespace
       where namespace.nspname = 'public'
         and relation.relname = v_view
         and relation.relkind = 'v'
         and coalesce(relation.reloptions, array[]::text[]) @> array['security_invoker=true']
    ) then
      raise exception 'view public.% must exist with security_invoker=true', v_view;
    end if;
  end loop;
end;
$$;

revoke all privileges on
  public.cad_garantias_produto_mapa_atuais,
  public.cad_garantias_lote_mp_atuais
from public, anon, authenticated;

grant select on
  public.cad_garantias_produto_mapa_atuais,
  public.cad_garantias_lote_mp_atuais
to authenticated;

comment on view public.cad_garantias_produto_mapa_atuais is
  'Current approved MAPA guarantees. Session users read through security_invoker and base-table RLS.';
comment on view public.cad_garantias_lote_mp_atuais is
  'Current approved MP lot guarantees. Session users read through security_invoker and base-table RLS.';
