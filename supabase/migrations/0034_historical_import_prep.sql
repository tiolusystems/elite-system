alter table public.user_profiles
  add column if not exists is_system_actor boolean not null default false,
  add column if not exists system_actor_key text;

alter table public.user_profiles
  drop constraint if exists user_profiles_system_actor_key_check,
  drop constraint if exists user_profiles_system_actor_inactive_check;

alter table public.user_profiles
  add constraint user_profiles_system_actor_key_check check (
    (is_system_actor = false and system_actor_key is null)
    or (
      is_system_actor = true
      and nullif(trim(system_actor_key), '') is not null
      and system_actor_key = lower(trim(system_actor_key))
    )
  ),
  add constraint user_profiles_system_actor_inactive_check check (
    is_system_actor = false or status = 'inactive'
  );

create unique index if not exists idx_user_profiles_system_actor_key
  on public.user_profiles(system_actor_key)
  where system_actor_key is not null;

comment on column public.user_profiles.is_system_actor is
  'Marca perfis nao-humanos usados como referencia auditavel, sem login operacional.';
comment on column public.user_profiles.system_actor_key is
  'Chave tecnica unica para ator de sistema, como migracao_historica.';

do $$
declare
  v_actor_id uuid := '00000000-0000-4000-8000-000000000034';
begin
  begin
    insert into auth.users(id)
    values (v_actor_id)
    on conflict (id) do nothing;
  exception
    when others then
      raise notice 'historical migration auth user bootstrap skipped: %', sqlerrm;
  end;

  if exists (select 1 from auth.users where id = v_actor_id) then
    if exists (
      select 1
        from public.user_profiles
       where system_actor_key = 'migracao_historica'
    ) then
      update public.user_profiles
         set display_name = 'Migracao Historica',
             role = 'auditoria',
             status = 'inactive',
             is_system_actor = true,
             system_actor_key = 'migracao_historica'
       where system_actor_key = 'migracao_historica';
    else
      insert into public.user_profiles(
        id,
        display_name,
        role,
        status,
        is_system_actor,
        system_actor_key
      )
      values (
        v_actor_id,
        'Migracao Historica',
        'auditoria',
        'inactive',
        true,
        'migracao_historica'
      )
      on conflict (id) do update set
        display_name = excluded.display_name,
        role = excluded.role,
        status = excluded.status,
        is_system_actor = excluded.is_system_actor,
        system_actor_key = excluded.system_actor_key;
    end if;
  else
    raise notice 'historical migration system actor profile not created because auth.users row is absent; provision auth user id % before historical import', v_actor_id;
  end if;
end;
$$;

do $$
declare
  v_table text;
  v_constraint text;
begin
  foreach v_table in array array[
    'com_pedidos',
    'com_pedido_itens',
    'cad_clientes',
    'cad_pessoas_comerciais',
    'cad_materias_primas',
    'cad_produtos_base',
    'cad_embalagens',
    'cad_produto_embalagens'
  ]
  loop
    v_constraint := v_table || '_origem_dados_check';

    execute format('alter table public.%I add column if not exists origem_dados text', v_table);
    execute format('alter table public.%I add column if not exists codigo_legado text', v_table);
    execute format('alter table public.%I drop constraint if exists %I', v_table, v_constraint);
    execute format(
      'alter table public.%I add constraint %I check (origem_dados is null or origem_dados in (''sistema'', ''excel_legado''))',
      v_table,
      v_constraint
    );
    execute format(
      'comment on column public.%I.origem_dados is %L',
      v_table,
      'Origem estrutural do registro: sistema ou excel_legado. Nulo enquanto a origem ainda nao foi classificada.'
    );
    execute format(
      'comment on column public.%I.codigo_legado is %L',
      v_table,
      'Identificador original do Excel legado, quando existir. Nao substitui o codigo definitivo do Elite System.'
    );
  end loop;
end;
$$;

create index if not exists idx_com_pedidos_codigo_legado
  on public.com_pedidos(codigo_legado)
  where codigo_legado is not null;

create index if not exists idx_com_pedido_itens_codigo_legado
  on public.com_pedido_itens(codigo_legado)
  where codigo_legado is not null;

comment on index public.idx_com_pedidos_codigo_legado is
  'Apoia rastreio e reconciliacao de pedidos importados do Excel legado.';
comment on index public.idx_com_pedido_itens_codigo_legado is
  'Apoia rastreio item a item de pedidos importados do Excel legado.';
