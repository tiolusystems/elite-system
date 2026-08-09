# Validação automatizada de Clientes - 0084

Data: 2026-07-22  
Ambiente: Supabase e frontend de staging  
Deployment: `dpl_9vW4Ko6qPbcvsQ2xDzhJs2Cf8mAT`  
Migration: `0084_complete_customer_master_data.sql`

## Cenário sintético

O cenário foi executado pela interface autenticada, sem dados comerciais reais.
O registro ficou identificado pelo código legado `HML-AUTO-20260722-0345`.

Fluxo validado:

1. criação do cliente;
2. identificação como pessoa jurídica;
3. razão social e nome fantasia;
4. documento CNPJ normalizado;
5. contato de compras;
6. propriedade rural;
7. estabelecimento matriz;
8. endereço fiscal relacionado ao estabelecimento e à propriedade;
9. consulta do resumo e do histórico;
10. consulta de crédito sem escrita pelo domínio Cadastros;
11. tentativa de repetir o CNPJ.

## Resultados

- cliente criado e imediatamente pesquisável;
- documento principal apresentado no resumo;
- contato e propriedade refletidos nos indicadores da ficha;
- endereço preservou os relacionamentos por ID;
- repetição do CNPJ foi negada sem criar nova linha;
- a interface apresentou mensagem de cadastro duplicado em português;
- Crédito permaneceu somente leitura e informou que a alteração pertence ao
  Financeiro;
- shell, menu lateral e manual contextual permaneceram disponíveis;
- não houve rolagem horizontal em `1366 x 768` nem em `390 x 844`;
- o health-check permaneceu `status=ok` e `backendConfigured=true`.

## Segurança comprovada em ambiente descartável

- instalação limpa `0001 -> 0084`;
- upgrade `0083 -> 0084`;
- escrita direta negada;
- RLS ativa nas três tabelas novas;
- seis RPCs disponíveis para `authenticated`;
- nenhuma RPC nova executável por `PUBLIC` ou `anon`;
- operação sem alçada negada;
- smoke concluído com rollback.

## Limitações registradas

- o histórico detalhado de auditoria ainda não é exibido integralmente na ficha;
- a mensagem de duplicidade é genérica e pode ganhar texto específico por tipo
  de documento;
- alteração de crédito deve ser homologada no fluxo próprio do Financeiro;
- o cenário sintético permanece no staging para regressões e não deve ser
  promovido para produção real.

## Conclusão

O cadastro completo de Clientes está tecnicamente homologado por simulação no
staging. A homologação não depende de execução manual de Luciano.
