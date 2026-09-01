# Superficies SQL governadas

O resolver autenticado `resolver_com_referencia_comercial` permanece
`SECURITY DEFINER`, com `search_path` fixo e autorizacao explicita. Ele e
`VOLATILE` porque a autorizacao e avaliada em execucao dentro da funcao; isso
nao altera a regra de resolucao comercial nem os valores retornados.

A segurança SQL distingue RPCs governadas SECURITY DEFINER, leituras
SECURITY INVOKER protegidas por RLS, helpers privados e helpers de trigger.
As classificações executáveis ficam registradas em
security_sql_surface_contracts e são verificadas pelo gate global.

Helpers internos não recebem EXECUTE para PUBLIC, anon ou authenticated.
normalize_client_search_text permanece disponível somente a leituras
autenticadas que dependem dele. O resolvedor comercial mantém sua entrada
autenticada e valida a permissão antes das leituras privilegiadas.

As migrations 0141–0144 são aditivas e não alteram semântica de negócio,
políticas RLS ou migrations históricas.
