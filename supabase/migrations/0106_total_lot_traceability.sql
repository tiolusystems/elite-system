-- TRACE-01: read-only genealogy derived from operational facts.
-- No parallel traceability ledger is introduced by this migration.

insert into public.permission_actions(
  action_key, module, description, default_allowed, sort_order,
  runtime_module_key, runtime_access_kind
)
values
  ('qualidade.rastreabilidade.view', 'qualidade', 'Consultar rastreabilidade de lotes', false, 761, 'relatorios', 'read'),
  ('qualidade.rastreabilidade.recall_simulate', 'qualidade', 'Simular recolhimento por lote', false, 762, 'relatorios', 'read'),
  ('qualidade.rastreabilidade.export', 'qualidade', 'Exportar rastreabilidade de lotes', false, 763, 'relatorios', 'read')
on conflict (action_key) do update set
  module = excluded.module,
  description = excluded.description,
  default_allowed = excluded.default_allowed,
  sort_order = excluded.sort_order,
  runtime_module_key = excluded.runtime_module_key,
  runtime_access_kind = excluded.runtime_access_kind;

insert into public.sys_module_routes(route_prefix, module_key, match_children)
values ('/qualidade/rastreabilidade', 'relatorios', true)
on conflict (route_prefix) do update set
  module_key = excluded.module_key,
  match_children = excluded.match_children;

create or replace view public.rel_rastreabilidade_arestas
with (security_invoker = true)
as
with expedicao_liquida as (
  select
    movimento.romaneio_id,
    movimento.lote_pa_id,
    sum(movimento.quantidade) as quantidade,
    max(movimento.created_at) as evento_em,
    max(movimento.id) as registro_id
  from public.exp_romaneio_movimentos_pa movimento
  where movimento.lote_pa_id is not null
  group by movimento.romaneio_id, movimento.lote_pa_id
)
select
  consumo.tipo_componente::text as origem_tipo,
  coalesce(consumo.lote_mp_id, consumo.lote_pi_id, consumo.lote_pa_id) as origem_id,
  coalesce(lote_mp.codigo_lote, lote_pi.codigo_lote, lote_pa.codigo_lote)::text as origem_codigo,
  'OP'::text as destino_tipo,
  ordem.id as destino_id,
  ordem.codigo_op::text as destino_codigo,
  consumo.quantidade_consumida::numeric as quantidade,
  coalesce(componente.unidade, case when consumo.tipo_componente = 'MP' then 'UN_BASE' else 'UN' end)::text as unidade,
  consumo.created_at as evento_em,
  'consumo_real'::text as evento,
  'pcp_op_consumos_componentes'::text as registro_fonte,
  consumo.id as registro_id,
  true as ativo
from public.pcp_op_consumos_componentes consumo
join public.pcp_ordens_producao ordem on ordem.id = consumo.op_id
join public.pcp_op_componentes_planejados componente on componente.id = consumo.op_componente_id
left join public.est_lotes_mp lote_mp on lote_mp.id = consumo.lote_mp_id
left join public.est_lotes_pi lote_pi on lote_pi.id = consumo.lote_pi_id
left join public.est_lotes_pa lote_pa on lote_pa.id = consumo.lote_pa_id
union all
select
  'OP', ordem.id, ordem.codigo_op,
  gerado.tipo_produto, coalesce(gerado.lote_pi_id, gerado.lote_pa_id),
  coalesce(lote_pi.codigo_lote, lote_pa.codigo_lote),
  gerado.quantidade, case when gerado.tipo_produto = 'PI' then 'L' else 'UN' end,
  gerado.created_at, 'producao_lote', 'pcp_op_produtos_gerados', gerado.id,
  gerado.status_lote <> 'cancelado'
from public.pcp_op_produtos_gerados gerado
join public.pcp_ordens_producao ordem on ordem.id = gerado.op_id
left join public.est_lotes_pi lote_pi on lote_pi.id = gerado.lote_pi_id
left join public.est_lotes_pa lote_pa on lote_pa.id = gerado.lote_pa_id
union all
select
  reserva.tipo_reserva,
  coalesce(reserva.lote_pi_id, reserva.lote_mp_id),
  coalesce(lote_pi.codigo_lote, lote_mp.codigo_lote),
  'ENVASE', ordem.id, ordem.codigo_ordem,
  reserva.quantidade_reservada,
  case when reserva.tipo_reserva = 'PI' then 'L' else 'UN' end,
  reserva.updated_at, 'consumo_envase', 'pcp_ordem_envase_reservas', reserva.id,
  reserva.status = 'consumida'
from public.pcp_ordem_envase_reservas reserva
join public.pcp_ordens_envase ordem on ordem.id = reserva.ordem_envase_id
left join public.est_lotes_pi lote_pi on lote_pi.id = reserva.lote_pi_id
left join public.est_lotes_mp lote_mp on lote_mp.id = reserva.lote_mp_id
where reserva.status in ('consumida', 'estornada')
union all
select
  'ENVASE', ordem.id, ordem.codigo_ordem,
  'PA', lote.id, lote.codigo_lote,
  gerado.quantidade, 'UN', gerado.created_at,
  'producao_envase', 'pcp_ordem_envase_lotes_pa', gerado.id,
  lote.status <> 'cancelado'
from public.pcp_ordem_envase_lotes_pa gerado
join public.pcp_ordens_envase ordem on ordem.id = gerado.ordem_envase_id
join public.est_lotes_pa lote on lote.id = gerado.lote_pa_id
union all
select
  'PA', lote.id, lote.codigo_lote,
  'ROMANEIO', romaneio.id, romaneio.codigo_romaneio,
  greatest(expedicao.quantidade, 0), 'UN', expedicao.evento_em,
  case when expedicao.quantidade > 0 then 'expedicao_confirmada' else 'expedicao_estornada' end,
  'exp_romaneio_movimentos_pa', expedicao.registro_id,
  expedicao.quantidade > 0
from expedicao_liquida expedicao
join public.est_lotes_pa lote on lote.id = expedicao.lote_pa_id
join public.exp_romaneios romaneio on romaneio.id = expedicao.romaneio_id
union all
select
  'ROMANEIO', romaneio.id, romaneio.codigo_romaneio,
  'PEDIDO', pedido.id, pedido.codigo_pedido,
  null::numeric, null::text, romaneio.created_at,
  'romaneio_do_pedido', 'exp_romaneios', romaneio.id,
  romaneio.status not in ('cancelado', 'estornado')
from public.exp_romaneios romaneio
join public.com_pedidos pedido on pedido.id = romaneio.pedido_id
union all
select
  'PEDIDO', pedido.id, pedido.codigo_pedido,
  'CLIENTE', cliente.id, cliente.nome,
  null::numeric, null::text, pedido.created_at,
  'pedido_do_cliente', 'com_pedidos', pedido.id,
  pedido.status <> 'cancelled'
from public.com_pedidos pedido
join public.cad_clientes cliente on cliente.id = pedido.cliente_id
union all
select
  'PEDIDO', pedido.id, pedido.codigo_pedido,
  'PROPRIEDADE', propriedade.id, propriedade.nome,
  null::numeric, null::text, pedido.created_at,
  'pedido_da_propriedade', 'com_pedidos', pedido.id,
  pedido.status <> 'cancelled'
from public.com_pedidos pedido
join public.cad_cliente_propriedades propriedade on propriedade.id = pedido.propriedade_id
union all
select
  'REFERENCIA_FISCAL', nota.id, concat_ws('-', nota.numero, nullif(nota.serie, '')),
  case when nota.romaneio_id is null then 'PEDIDO' else 'ROMANEIO' end,
  coalesce(nota.romaneio_id, nota.pedido_id),
  coalesce(romaneio.codigo_romaneio, pedido.codigo_pedido),
  nota.valor_nf, 'BRL', nota.created_at,
  'referencia_fiscal_externa', 'fat_notas_fiscais', nota.id,
  nota.status_atual = 'emitida'
from public.fat_notas_fiscais nota
join public.com_pedidos pedido on pedido.id = nota.pedido_id
left join public.exp_romaneios romaneio on romaneio.id = nota.romaneio_id
where nota.origem_registro = 'externa';

create or replace view public.rel_rastreabilidade_lotes_resumo
with (security_invoker = true)
as
select
  'MP'::text as tipo_lote, saldo.lote_mp_id as lote_id, saldo.codigo_lote,
  materia.nome as item, saldo.status, saldo.saldo_fisico, saldo.quantidade_reservada,
  saldo.saldo_disponivel, saldo.data_fabricacao, saldo.data_validade
from public.est_lotes_mp_saldos saldo
join public.cad_materias_primas materia on materia.id = saldo.materia_prima_id
union all
select
  'PI', saldo.lote_pi_id, saldo.codigo_lote,
  produto.nome, saldo.status, saldo.saldo_fisico, saldo.quantidade_reservada,
  saldo.saldo_disponivel, saldo.data_fabricacao, saldo.data_validade
from public.est_lotes_pi_saldos saldo
join public.cad_produtos_base produto on produto.id = saldo.produto_id
union all
select
  'PA', saldo.lote_pa_id, saldo.codigo_lote,
  concat_ws(' - ', produto.nome, embalagem.descricao), saldo.status,
  saldo.saldo_fisico, saldo.quantidade_reservada, saldo.saldo_disponivel,
  saldo.data_fabricacao, saldo.data_validade
from public.est_lotes_pa_saldos saldo
join public.cad_produto_embalagens apresentacao on apresentacao.id = saldo.produto_embalagem_id
join public.cad_produtos_base produto on produto.id = apresentacao.produto_id
join public.cad_embalagens embalagem on embalagem.id = apresentacao.embalagem_id;

create or replace view public.rel_rastreabilidade_destinos_cliente
with (security_invoker = true)
as
with expedicao_liquida as (
  select movimento.romaneio_id, movimento.lote_pa_id, sum(movimento.quantidade) as quantidade,
         max(movimento.created_at) as expedido_em
    from public.exp_romaneio_movimentos_pa movimento
   where movimento.lote_pa_id is not null
   group by movimento.romaneio_id, movimento.lote_pa_id
)
select
  lote.id as lote_pa_id, lote.codigo_lote,
  concat_ws(' - ', produto.nome, embalagem.descricao) as produto,
  lote.status as status_lote,
  saldo.saldo_fisico,
  romaneio.id as romaneio_id, romaneio.codigo_romaneio,
  pedido.id as pedido_id, pedido.codigo_pedido,
  cliente.id as cliente_id, cliente.nome as cliente_nome,
  propriedade.id as propriedade_id, propriedade.nome as propriedade_nome,
  expedicao.quantidade, expedicao.expedido_em,
  nota.id as referencia_fiscal_id,
  concat_ws('-', nota.numero, nullif(nota.serie, '')) as referencia_fiscal,
  coalesce(contatos.itens, '[]'::jsonb) as contatos
from expedicao_liquida expedicao
join public.est_lotes_pa lote on lote.id = expedicao.lote_pa_id
join public.est_lotes_pa_saldos saldo on saldo.lote_pa_id = lote.id
join public.cad_produto_embalagens apresentacao on apresentacao.id = lote.produto_embalagem_id
join public.cad_produtos_base produto on produto.id = apresentacao.produto_id
join public.cad_embalagens embalagem on embalagem.id = apresentacao.embalagem_id
join public.exp_romaneios romaneio on romaneio.id = expedicao.romaneio_id
join public.com_pedidos pedido on pedido.id = romaneio.pedido_id
join public.cad_clientes cliente on cliente.id = pedido.cliente_id
left join public.cad_cliente_propriedades propriedade on propriedade.id = pedido.propriedade_id
left join public.fat_notas_fiscais nota
  on nota.romaneio_id = romaneio.id
 and nota.origem_registro = 'externa'
 and nota.status_atual = 'emitida'
left join lateral (
  select jsonb_agg(
    jsonb_build_object(
      'nome', contato.nome,
      'papel', contato.papel,
      'telefone', contato.telefone,
      'email', contato.email
    ) order by contato.id
  ) as itens
    from public.cad_cliente_contatos contato
   where contato.cliente_id = cliente.id
     and contato.status = 'active'
     and (
       pedido.propriedade_id is null
       or contato.propriedade_id is null
       or contato.propriedade_id = pedido.propriedade_id
     )
) contatos on true
where expedicao.quantidade > 0
  and romaneio.status = 'confirmado';

create or replace view public.rel_rastreabilidade_conciliacao
with (security_invoker = true)
as
select
  'MP'::text as tipo_lote, saldo.lote_mp_id as lote_id, saldo.codigo_lote,
  saldo.quantidade_entrada as quantidade_entrada,
  saldo.quantidade_saida as quantidade_saida,
  saldo.saldo_fisico, saldo.quantidade_reservada, saldo.saldo_disponivel,
  (saldo.quantidade_entrada - saldo.quantidade_saida - saldo.saldo_fisico) as divergencia
from public.est_lotes_mp_saldos saldo
union all
select
  'PI', saldo.lote_pi_id, saldo.codigo_lote,
  saldo.quantidade_entrada, saldo.quantidade_saida, saldo.saldo_fisico,
  saldo.quantidade_reservada, saldo.saldo_disponivel,
  (saldo.quantidade_entrada - saldo.quantidade_saida - saldo.saldo_fisico)
from public.est_lotes_pi_saldos saldo
union all
select
  'PA', saldo.lote_pa_id, saldo.codigo_lote,
  saldo.quantidade_entrada, saldo.quantidade_saida, saldo.saldo_fisico,
  saldo.quantidade_reservada, saldo.saldo_disponivel,
  (saldo.quantidade_entrada - saldo.quantidade_saida - saldo.saldo_fisico)
from public.est_lotes_pa_saldos saldo;

revoke all on public.rel_rastreabilidade_arestas from public, anon, authenticated;
revoke all on public.rel_rastreabilidade_lotes_resumo from public, anon, authenticated;
revoke all on public.rel_rastreabilidade_destinos_cliente from public, anon, authenticated;
revoke all on public.rel_rastreabilidade_conciliacao from public, anon, authenticated;

create or replace function public.consultar_rel_rastreabilidade(
  p_tipo text default null,
  p_codigo text default null,
  p_cliente_id bigint default null,
  p_pedido_id bigint default null,
  p_romaneio_id bigint default null,
  p_referencia_fiscal text default null,
  p_direcao text default 'ambas',
  p_limite integer default 500
)
returns table(
  origem_tipo text, origem_id bigint, origem_codigo text,
  destino_tipo text, destino_id bigint, destino_codigo text,
  quantidade numeric, unidade text, evento_em timestamptz, evento text,
  registro_fonte text, registro_id bigint, ativo boolean,
  profundidade integer
)
language plpgsql
security definer
set search_path = public
as $$
declare
  v_tipo text := nullif(upper(btrim(coalesce(p_tipo, ''))), '');
  v_codigo text := nullif(lower(btrim(coalesce(p_codigo, ''))), '');
  v_direcao text := lower(btrim(coalesce(p_direcao, 'ambas')));
begin
  perform public.require_current_user_permission('qualidade.rastreabilidade.view');
  if v_direcao not in ('frente', 'tras', 'ambas') then raise exception 'invalid trace direction'; end if;
  if p_limite is null or p_limite < 1 or p_limite > 2000 then raise exception 'trace limit must be between 1 and 2000'; end if;
  if v_tipo is null and v_codigo is null and p_cliente_id is null and p_pedido_id is null
     and p_romaneio_id is null and nullif(btrim(coalesce(p_referencia_fiscal, '')), '') is null then
    raise exception 'at least one trace filter is required';
  end if;

  return query
  with recursive nodes as (
    select edge.origem_tipo as tipo, edge.origem_id as id, edge.origem_codigo as codigo
      from public.rel_rastreabilidade_arestas edge
    union
    select edge.destino_tipo, edge.destino_id, edge.destino_codigo
      from public.rel_rastreabilidade_arestas edge
  ), roots as (
    select node.tipo, node.id, node.codigo
      from nodes node
     where (v_tipo is null or node.tipo = v_tipo)
       and (v_codigo is null or lower(node.codigo) like '%' || v_codigo || '%')
       and (p_cliente_id is null or (node.tipo = 'CLIENTE' and node.id = p_cliente_id))
       and (p_pedido_id is null or (node.tipo = 'PEDIDO' and node.id = p_pedido_id))
       and (p_romaneio_id is null or (node.tipo = 'ROMANEIO' and node.id = p_romaneio_id))
       and (nullif(btrim(coalesce(p_referencia_fiscal, '')), '') is null
         or (node.tipo = 'REFERENCIA_FISCAL' and lower(node.codigo) like '%' || lower(btrim(p_referencia_fiscal)) || '%'))
  ), walk as (
    select edge.*, 1 as profundidade,
           array[edge.origem_tipo || ':' || edge.origem_id, edge.destino_tipo || ':' || edge.destino_id]::text[] as caminho
      from public.rel_rastreabilidade_arestas edge
      join roots root on (
        (v_direcao in ('frente', 'ambas') and edge.origem_tipo = root.tipo and edge.origem_id = root.id)
        or (v_direcao in ('tras', 'ambas') and edge.destino_tipo = root.tipo and edge.destino_id = root.id)
      )
    union all
    select edge.*, walk.profundidade + 1,
           walk.caminho || case
             when edge.origem_tipo = walk.destino_tipo and edge.origem_id = walk.destino_id
               then edge.destino_tipo || ':' || edge.destino_id
             else edge.origem_tipo || ':' || edge.origem_id
           end
      from walk
      join public.rel_rastreabilidade_arestas edge on (
        (v_direcao in ('frente', 'ambas') and edge.origem_tipo = walk.destino_tipo and edge.origem_id = walk.destino_id)
        or (v_direcao in ('tras', 'ambas') and edge.destino_tipo = walk.origem_tipo and edge.destino_id = walk.origem_id)
      )
     where walk.profundidade < 12
       and not ((edge.origem_tipo || ':' || edge.origem_id) = any(walk.caminho)
                and (edge.destino_tipo || ':' || edge.destino_id) = any(walk.caminho))
  )
  select distinct
    walk.origem_tipo, walk.origem_id, walk.origem_codigo,
    walk.destino_tipo, walk.destino_id, walk.destino_codigo,
    walk.quantidade, walk.unidade, walk.evento_em, walk.evento,
    walk.registro_fonte, walk.registro_id, walk.ativo, walk.profundidade
  from walk
  order by walk.profundidade, walk.evento_em, walk.registro_id
  limit p_limite;
end;
$$;

create or replace function public.simular_rel_recolhimento(
  p_tipo_lote text,
  p_lote_id bigint
)
returns table(
  lote_pa_id bigint, codigo_lote text,
  produto text, status_lote text, saldo_fisico numeric,
  romaneio_id bigint, codigo_romaneio text,
  pedido_id bigint, codigo_pedido text,
  cliente_id bigint, cliente_nome text,
  propriedade_id bigint, propriedade_nome text,
  quantidade numeric, expedido_em timestamptz,
  referencia_fiscal_id bigint, referencia_fiscal text,
  contatos jsonb
)
language plpgsql
security definer
set search_path = public
as $$
begin
  perform public.require_current_user_permission('qualidade.rastreabilidade.recall_simulate');
  if upper(btrim(coalesce(p_tipo_lote, ''))) not in ('MP', 'PI', 'PA', 'EMBALAGEM') then
    raise exception 'invalid recall lot type';
  end if;
  if p_lote_id is null or p_lote_id <= 0 then raise exception 'recall lot is required'; end if;

  return query
  with recursive descendentes(tipo, id, caminho) as (
    select upper(btrim(p_tipo_lote)), p_lote_id,
           array[upper(btrim(p_tipo_lote)) || ':' || p_lote_id]::text[]
    union all
    select edge.destino_tipo, edge.destino_id,
           descendentes.caminho || edge.destino_tipo || ':' || edge.destino_id
      from descendentes
      join public.rel_rastreabilidade_arestas edge
        on edge.origem_tipo = descendentes.tipo and edge.origem_id = descendentes.id
     where edge.ativo
       and cardinality(descendentes.caminho) < 12
       and not (edge.destino_tipo || ':' || edge.destino_id = any(descendentes.caminho))
  ), lotes_pa as (
    select distinct descendentes.id as lote_pa_id
      from descendentes
     where descendentes.tipo = 'PA'
  )
  select destino.lote_pa_id, destino.codigo_lote,
         destino.produto, destino.status_lote, destino.saldo_fisico,
         destino.romaneio_id, destino.codigo_romaneio,
         destino.pedido_id, destino.codigo_pedido,
         destino.cliente_id, destino.cliente_nome,
         destino.propriedade_id, destino.propriedade_nome,
         destino.quantidade, destino.expedido_em,
         destino.referencia_fiscal_id, destino.referencia_fiscal,
         destino.contatos
    from public.rel_rastreabilidade_destinos_cliente destino
    join lotes_pa on lotes_pa.lote_pa_id = destino.lote_pa_id
   order by destino.expedido_em, destino.romaneio_id;
end;
$$;

create or replace function public.exportar_rel_rastreabilidade(
  p_tipo text default null,
  p_codigo text default null,
  p_cliente_id bigint default null,
  p_pedido_id bigint default null,
  p_romaneio_id bigint default null,
  p_referencia_fiscal text default null,
  p_direcao text default 'ambas'
)
returns table(
  ambiente text, usuario_id uuid, exportado_em timestamptz, filtros jsonb,
  origem_tipo text, origem_id bigint, origem_codigo text,
  destino_tipo text, destino_id bigint, destino_codigo text,
  quantidade numeric, unidade text, evento_em timestamptz, evento text,
  registro_fonte text, registro_id bigint, ativo boolean,
  profundidade integer, divergencia_origem numeric, divergencia_destino numeric
)
language plpgsql
security definer
set search_path = public
as $$
declare
  v_context jsonb;
  v_actor uuid;
begin
  perform public.require_current_user_permission('qualidade.rastreabilidade.export');
  v_actor := public.current_actor_id();
  v_context := public.begin_audited_rpc(
    'qualidade.rastreabilidade.export', 'qualidade', 'rel_rastreabilidade_arestas',
    'read_export', jsonb_build_object('event', 'traceability_export')
  );
  perform public.log_audited_rpc_change(
    'qualidade', 'rel_rastreabilidade_arestas', coalesce(p_codigo, p_referencia_fiscal, 'filtros'),
    'qualidade.rastreabilidade_exportada', 'qualidade.rastreabilidade.export', v_context,
    null, null,
    jsonb_build_object(
      'actor_id', v_actor, 'tipo', p_tipo, 'codigo', p_codigo,
      'cliente_id', p_cliente_id, 'pedido_id', p_pedido_id,
      'romaneio_id', p_romaneio_id, 'referencia_fiscal', p_referencia_fiscal,
      'direcao', p_direcao
    ), 'database_rpc'
  );
  return query
  select
    public.current_system_environment()::text,
    v_actor,
    clock_timestamp(),
    jsonb_build_object(
      'tipo', p_tipo, 'codigo', p_codigo, 'cliente_id', p_cliente_id,
      'pedido_id', p_pedido_id, 'romaneio_id', p_romaneio_id,
      'referencia_fiscal', p_referencia_fiscal, 'direcao', p_direcao
    ),
    trace.origem_tipo, trace.origem_id, trace.origem_codigo,
    trace.destino_tipo, trace.destino_id, trace.destino_codigo,
    trace.quantidade, trace.unidade, trace.evento_em, trace.evento,
    trace.registro_fonte, trace.registro_id, trace.ativo, trace.profundidade,
    origem.divergencia, destino.divergencia
  from public.consultar_rel_rastreabilidade(
    p_tipo, p_codigo, p_cliente_id, p_pedido_id, p_romaneio_id,
    p_referencia_fiscal, p_direcao, 2000
  ) trace
  left join public.rel_rastreabilidade_conciliacao origem
    on origem.tipo_lote = trace.origem_tipo and origem.lote_id = trace.origem_id
  left join public.rel_rastreabilidade_conciliacao destino
    on destino.tipo_lote = trace.destino_tipo and destino.lote_id = trace.destino_id;
end;
$$;

revoke all on function public.consultar_rel_rastreabilidade(text, text, bigint, bigint, bigint, text, text, integer)
  from public, anon;
revoke all on function public.simular_rel_recolhimento(text, bigint)
  from public, anon;
revoke all on function public.exportar_rel_rastreabilidade(text, text, bigint, bigint, bigint, text, text)
  from public, anon;
grant execute on function public.consultar_rel_rastreabilidade(text, text, bigint, bigint, bigint, text, text, integer)
  to authenticated;
grant execute on function public.simular_rel_recolhimento(text, bigint)
  to authenticated;
grant execute on function public.exportar_rel_rastreabilidade(text, text, bigint, bigint, bigint, text, text)
  to authenticated;

comment on view public.rel_rastreabilidade_arestas is
  'Read-only genealogy derived from actual consumption, production, packaging and shipping facts.';
comment on view public.rel_rastreabilidade_conciliacao is
  'Read-only lot balance reconciliation. Reservations remain separate from physical stock.';
