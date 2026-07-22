# Validação de pedidos especiais 0085

## Contrato

- Venda, bonificação, mostruário e troca são escolhidos no mesmo formulário.
- Todo pedido nasce bloqueado e depende de liberação gerencial.
- Bonificação exige justificativa e não gera comissão.
- Mostruário não gera comissão.
- Troca referencia pedido e item de origem; o banco recalcula a quantidade já
  trocada antes de gravar.
- PDF e impressão ficam disponíveis somente após a liberação.

## Segurança

- Bonificação e mostruário usam vínculo ativo entre cliente e vendedor.
- A data do pedido precisa estar dentro da vigência do vínculo.
- A troca só aceita pedido do próprio vendedor, da equipe gerenciada ou de
  administrador autorizado.
- A implementação interna da troca não pode ser executada por `authenticated`,
  `anon` ou `PUBLIC`.
- Escritas permanecem em RPCs `SECURITY DEFINER`, com permissão e auditoria.

## Evidências

- instalação limpa `0001 -> 0085`: `PG_VALIDATE_0085_CLEAN_INSTALL_OK`;
- upgrade isolado `0084 -> 0085`: `PG_VALIDATE_0085_UPGRADE_OK`;
- privilégios: RPC especial `authenticated=true`, `anon=false`; implementação
  interna da troca `authenticated=false`;
- containers e volumes: `elite-validation-0085-clean` e
  `elite-validation-0085-upgrade`, sem contato com runtime ativo ou staging;
- suíte Python, ESLint, TypeScript, build Next.js e `git diff --check` aprovados.

Somente dados sintéticos são permitidos no smoke de staging.
