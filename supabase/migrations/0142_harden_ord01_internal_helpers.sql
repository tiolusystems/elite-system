revoke all on function public.ord01_comparacao_original_persistida(bigint) from public, anon, authenticated;
revoke all on function public.ord01_revision_current_pre_effective_state(bigint) from public, anon, authenticated;
revoke all on function public.ord01_revision_impact_mask(jsonb, jsonb) from public, anon, authenticated;
revoke all on function public.avaliar_com_pedido_efetividade(bigint) from public, anon, authenticated;
revoke all on function public.ord01_contract_genesis_state(bigint) from public, anon, authenticated;
alter function public.ord01_revision_impact_mask(jsonb, jsonb) set search_path = public;
