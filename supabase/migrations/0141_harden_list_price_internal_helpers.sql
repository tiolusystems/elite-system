revoke all on function public.prevent_com_lista_preco_import_fact_changes() from public, anon, authenticated;
revoke all on function public.normalizar_com_lista_preco_valor_bruto(text) from public, anon, authenticated;
revoke all on function public.normalize_client_search_text(text) from public, anon;
grant execute on function public.normalize_client_search_text(text) to authenticated;
