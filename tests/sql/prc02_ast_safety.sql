\set ON_ERROR_STOP on
begin;

create function pg_temp.node(p_op text,p_left jsonb,p_right jsonb) returns jsonb language sql immutable as $$
  select jsonb_build_object('kind','operation','op',p_op,'args',jsonb_build_array(p_left,p_right))
$$;
create function pg_temp.constant(p_value text,p_unit text) returns jsonb language sql immutable as $$
  select jsonb_build_object('kind','constant','value',p_value,'unit',p_unit)
$$;
create function pg_temp.document(p_root jsonb,p_unit text default 'BRL_L') returns jsonb language sql immutable as $$
  select jsonb_build_object('schema','prc-formula-ast-v1','result_unit',p_unit,'root',p_root)
$$;
create function pg_temp.must_reject(p_case text,p_ast jsonb,p_params jsonb,p_values jsonb,p_evaluate boolean,p_error text)
returns void language plpgsql as $$
declare v_error text;
begin
  begin
    perform precificacao_internal.validar_prc_formula_ast(p_ast,p_params);
    if p_evaluate then perform precificacao_internal.avaliar_prc_formula_ast(p_ast,p_values); end if;
  exception when others then
    get stacked diagnostics v_error = message_text;
    if position(p_error in v_error)>0 then return; end if;
    raise exception 'AST %: erro inesperado: %',p_case,v_error;
  end;
  raise exception 'AST %: entrada invalida aceita',p_case;
end $$;

do $safety$
declare
  v_brl jsonb:=pg_temp.constant('1','BRL_L');
  v_fraction jsonb:=pg_temp.constant('1','FRACTION');
  v_ast jsonb;
  v_root jsonb;
  v_i integer;
begin
  perform pg_temp.must_reject('unknown operator',pg_temp.document(pg_temp.node('execute',v_brl,v_brl)),'{}','{}',false,'operador AST invalido');
  perform pg_temp.must_reject('unknown kind',pg_temp.document(jsonb_build_object('kind','sql','query','select 1')),'{}','{}',false,'tipo de no AST invalido');
  perform pg_temp.must_reject('unexpected key',pg_temp.document(v_brl||jsonb_build_object('sql','select 1')),'{}','{}',false,'chave AST desconhecida');
  perform pg_temp.must_reject('missing parameter',pg_temp.document(jsonb_build_object('kind','parameter','code','missing')),'{}','{}',false,'parametro nao declarado');
  perform pg_temp.must_reject('incompatible unit',pg_temp.document(pg_temp.node('add',v_brl,v_fraction)),'{}','{}',false,'unidade incompativel');

  v_root:=v_brl;
  for v_i in 1..32 loop v_root:=pg_temp.node('add',v_root,v_brl); end loop;
  perform pg_temp.must_reject('depth 33',pg_temp.document(v_root),'{}','{}',false,'profundidade maxima');
  v_root:=v_brl;
  for v_i in 1..9 loop v_root:=pg_temp.node('add',v_root,v_root); end loop;
  perform pg_temp.must_reject('513+ nodes',pg_temp.document(v_root),'{}','{}',false,'quantidade maxima de nos');

  v_ast:=pg_temp.document(pg_temp.node('div',v_brl,pg_temp.constant('0','SCALAR')));
  perform pg_temp.must_reject('division by zero',v_ast,'{}','{}',true,'divisao por zero');
  v_ast:=pg_temp.document(pg_temp.node('pow',pg_temp.constant('-2','SCALAR'),pg_temp.constant('0.5','SCALAR')),'SCALAR');
  perform pg_temp.must_reject('negative fractional power',v_ast,'{}','{}',true,'potencia fora do dominio');
  v_ast:=pg_temp.document(pg_temp.node('pow',pg_temp.constant('0','SCALAR'),pg_temp.constant('0','SCALAR')),'SCALAR');
  perform pg_temp.must_reject('zero to zero',v_ast,'{}','{}',true,'potencia fora do dominio');
  v_ast:=pg_temp.document(pg_temp.node('pow',pg_temp.constant('0','SCALAR'),pg_temp.constant('-1','SCALAR')),'SCALAR');
  perform pg_temp.must_reject('zero to negative',v_ast,'{}','{}',true,'potencia fora do dominio');
  v_ast:=pg_temp.document(pg_temp.node('pow',pg_temp.constant('2','SCALAR'),pg_temp.constant('33','SCALAR')),'SCALAR');
  perform pg_temp.must_reject('power exponent cap',v_ast,'{}','{}',true,'expoente excede limite');
  perform pg_temp.must_reject('decimal token cap',pg_temp.document(pg_temp.constant(repeat('9',65),'BRL_L')),'{}','{}',false,'decimal excede tamanho maximo');
end $safety$;

rollback;
\echo PG_PRC02_AST_SAFETY_OK
