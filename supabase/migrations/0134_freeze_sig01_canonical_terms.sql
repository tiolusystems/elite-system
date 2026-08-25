begin;

alter function public.com_pedido_documento_comercial_canonico(
  bigint, integer, uuid, timestamptz, text, boolean
) rename to com_pedido_documento_comercial_canonico_v1_0134;

create or replace function public.com_pedido_documento_comercial_canonico(
  p_pedido_id bigint,
  p_numero_versao integer,
  p_confirmado_por uuid,
  p_confirmado_em timestamptz,
  p_justificativa_comercial text,
  p_descontos_confirmados boolean
)
returns jsonb
language sql
stable
security definer
set search_path = public
as $$
  select jsonb_set(
    jsonb_set(
      public.com_pedido_documento_comercial_canonico_v1_0134(
        p_pedido_id, p_numero_versao, p_confirmado_por, p_confirmado_em,
        p_justificativa_comercial, p_descontos_confirmados
      ),
      '{schema_version}', '2'::jsonb, true
    ),
    '{termos}',
    jsonb_build_array(
      jsonb_build_object(
        'titulo', 'Escopo e natureza',
        'texto', $terms$Aplica-se às operações de venda e fornecimento de insumos agrícolas realizadas com produtores rurais (PF/PJ), revendas, distribuidores e cooperativas agropecuárias. Relação comercial/profissional no âmbito do agronegócio. O e-mail corporativo cadastrado é canal de comunicação e não constitui aceite ou assinatura. O aceite do comprador será comprovado exclusivamente por evidência de assinatura registrada e aceita no Elite System. Os prazos e efeitos operacionais previstos neste informativo contam-se a partir de pedido_efetivado_em, quando o pedido se tornar efetivo no fluxo governado. Se, excepcionalmente, houver enquadramento como relação de consumo, prevalecerão as normas específicas aplicáveis.$terms$
      ),
      jsonb_build_object(
        'titulo', 'Troca e devolução',
        'texto', $terms$Não aceitamos devoluções em nenhuma hipótese. Constatada não conformidade em lote, o produto será substituído por outro idêntico. A constatação poderá ocorrer por laudo interno da VENDEDORA ou por laboratório indicado/aceito pela VENDEDORA.$terms$
      ),
      jsonb_build_object(
        'titulo', 'Ciência e consentimento',
        'texto', $terms$Ao assinar por meio de evidência registrada e aceita no Elite System, o CLIENTE declara ciência e concordância integral com este informativo e com as demais condições do pedido. O envio de e-mail, isoladamente, não produz aceite.$terms$
      ),
      jsonb_build_object(
        'titulo', 'Cancelamento de pedidos (simples faturamento - sem remessa)',
        'texto', $terms$Base de cálculo: valor líquido do pedido (sem tributos recuperáveis e sem frete). Cancelamento até 3 dias após pedido_efetivado_em: multa compensatória de 5%. Do 4º ao 10º dia: multa de 10%. A partir do 11º dia, havendo programação de produção (OP emitida, reserva/compra de insumos, logística agendada): multa de 15%. Havendo execução parcial (OP iniciada, insumo específico já incorporado ao processo ou serviço técnico iniciado): multa de 20%. Produtos/projetos customizados ou com insumo não reaproveitável: multa de até 25%, mediante comprovação documental. Se houver sinal (arras), aplica-se o maior entre a perda do sinal e a multa acima, sem cumulação pelo mesmo fato. O cancelamento deve ser solicitado por e-mail institucional indicado no cabeçalho do pedido. A VENDEDORA responderá com o enquadramento, memória de cálculo e instruções de compensação. Quando o prejuízo efetivo superar a multa pactuada, poderá ser cobrada indenização suplementar limitada ao excedente comprovado.$terms$
      ),
      jsonb_build_object(
        'titulo', 'Atrasos em pagamentos',
        'texto', $terms$Atraso superior a 5 dias implicará protesto do título e negativação automática. Encargos por atraso: multa de 2% sobre o valor em aberto e juros de 0,03% ao dia de atraso.$terms$
      ),
      jsonb_build_object(
        'titulo', 'Tratamento fiscal (simples faturamento)',
        'texto', $terms$A emissão de NF-e de simples faturamento não implica entrega física. Em caso de cancelamento, as partes firmarão distrato comercial. O procedimento fiscal (cancelamento ou manutenção da NF-e de simples faturamento) seguirá a legislação da UF do remetente, sendo adotada a providência cabível e comunicada ao CLIENTE.$terms$
      ),
      jsonb_build_object(
        'titulo', 'Fundamentação e alcance',
        'texto', $terms$Multa compensatória e arras pactuadas conforme legislação civil aplicável; perdas e danos suplementares quando cabíveis e comprovados. Este informativo aplica-se às relações comerciais com produtores rurais, revendas, distribuidores e cooperativas, sem prejuízo de normas específicas eventualmente incidentes.$terms$
      ),
      jsonb_build_object(
        'titulo', 'Solução de controvérsias',
        'texto', $terms$As partes buscarão solução amigável e, não sendo possível, elegem o foro da comarca de Barretos/SP, com renúncia a qualquer outro, por mais privilegiado que seja.$terms$
      ),
      jsonb_build_object(
        'titulo', 'Disposições finais',
        'texto', $terms$Este informativo integra o Pedido de Venda, cujo número consta no cabeçalho do documento. Comunicações oficiais devem ocorrer exclusivamente pelo e-mail institucional indicado no cabeçalho do pedido.$terms$
      )
    ),
    true
  );
$$;

revoke all on function public.com_pedido_documento_comercial_canonico_v1_0134(bigint, integer, uuid, timestamptz, text, boolean)
  from public, anon, authenticated;
revoke all on function public.com_pedido_documento_comercial_canonico(bigint, integer, uuid, timestamptz, text, boolean)
  from public, anon, authenticated;

create or replace function public.consultar_com_pedido_documento_assinavel(p_pedido_id bigint)
returns jsonb language plpgsql stable security definer set search_path = public as $$
declare
  v_result jsonb;
begin
  perform public.require_current_user_permission('pedidos.buyer_signature.view');
  if not public.can_current_user_view_order(p_pedido_id) then raise exception 'pedido fora do escopo do usuario'; end if;
  select jsonb_build_object(
    'confirmacao_comercial_id', confirmation.id,
    'pedido_id', confirmation.pedido_id,
    'numero_versao', confirmation.numero_versao,
    'documento_canonico_sha256', confirmation.documento_canonico_sha256,
    'confirmed_at', confirmation.confirmed_at,
    'status_pedido', orders.status,
    'documento', confirmation.documento_canonico_json
  ) into v_result
    from public.com_pedido_confirmacoes_comerciais confirmation
    join public.com_pedidos orders on orders.id = confirmation.pedido_id
   where confirmation.pedido_id = p_pedido_id
   order by confirmation.numero_versao desc
   limit 1;
  if v_result is null then raise exception 'pedido nao possui confirmacao comercial'; end if;
  if (v_result->'documento'->>'schema_version')::integer < 2
     or jsonb_typeof(v_result->'documento'->'termos') <> 'array'
     or jsonb_array_length(v_result->'documento'->'termos') = 0 then
    raise exception 'documento comercial legado nao possui termos congelados';
  end if;
  return v_result;
end;
$$;

revoke all on function public.consultar_com_pedido_documento_assinavel(bigint) from public, anon;
grant execute on function public.consultar_com_pedido_documento_assinavel(bigint) to authenticated;

create or replace function public.autorizar_com_pedido_assinatura_evidencia(
  p_pedido_id bigint, p_confirmacao_comercial_id bigint, p_documento_canonico_sha256 text
) returns jsonb language plpgsql stable security definer set search_path = public as $$
declare
  v_current public.com_pedido_confirmacoes_comerciais%rowtype;
begin
  perform public.require_current_user_permission('pedidos.buyer_signature.submit');
  if p_pedido_id is null or not public.can_current_user_view_order(p_pedido_id) then
    raise exception 'pedido fora do escopo do usuario';
  end if;
  select * into v_current from public.com_pedido_confirmacoes_comerciais
   where pedido_id = p_pedido_id order by numero_versao desc limit 1;
  if not found
     or v_current.id is distinct from p_confirmacao_comercial_id
     or v_current.documento_canonico_sha256 is distinct from lower(p_documento_canonico_sha256)
     or (v_current.documento_canonico_json->>'schema_version')::integer < 2
     or jsonb_typeof(v_current.documento_canonico_json->'termos') <> 'array' then
    raise exception 'evidencia nao corresponde ao documento comercial vigente';
  end if;
  return jsonb_build_object('pedido_id', p_pedido_id, 'confirmacao_comercial_id', v_current.id, 'documento_canonico_sha256', v_current.documento_canonico_sha256);
end;
$$;

revoke all on function public.autorizar_com_pedido_assinatura_evidencia(bigint,bigint,text) from public, anon;
grant execute on function public.autorizar_com_pedido_assinatura_evidencia(bigint,bigint,text) to authenticated;

alter table public.com_pedido_assinatura_evidencias
  drop constraint if exists com_pedido_assinatura_evidencias_source_check;
alter table public.com_pedido_assinatura_evidencias
  add constraint com_pedido_assinatura_evidencias_source_check check (
    fonte in ('physical_digitized', 'external_digital')
    and artefato_storage_path is not null
  );

create or replace function public.validate_com_pedido_assinatura_documento_schema()
returns trigger language plpgsql security definer set search_path = public as $$
declare v_confirmation public.com_pedido_confirmacoes_comerciais%rowtype;
begin
  select * into v_confirmation from public.com_pedido_confirmacoes_comerciais where id = new.confirmacao_comercial_id;
  if not found or (v_confirmation.documento_canonico_json->>'schema_version')::integer < 2
     or jsonb_typeof(v_confirmation.documento_canonico_json->'termos') <> 'array' then
    raise exception 'documento comercial legado nao e assinavel';
  end if;
  return new;
end;
$$;

revoke all on function public.validate_com_pedido_assinatura_documento_schema() from public, anon, authenticated;
create trigger trg_com_pedido_assinatura_documento_schema
before insert on public.com_pedido_assinatura_evidencias
for each row execute function public.validate_com_pedido_assinatura_documento_schema();

comment on function public.com_pedido_documento_comercial_canonico(bigint, integer, uuid, timestamptz, text, boolean) is
  'ORD-01 SIG01: documento canonico schema 2. Termos e fatos comerciais exibidos na assinatura pertencem ao JSON hashado; documento legado nao e assinavel.';

commit;
