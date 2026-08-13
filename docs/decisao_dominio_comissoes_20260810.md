# DEC-COMM-01 — Domínio de comissões

Data: 2026-08-10  
Status: aprovado para implementação incremental

## Objetivo

Transformar comissão em um domínio explícito, versionado e auditável. Regras de negócio não podem ficar dispersas em telas, Server Actions ou condicionais duplicadas em SQL.

## Invariantes

1. **Somente pedidos de venda geram comissão.**
   Bonificação, devolução, troca, mostruário e outras modalidades não criam novo direito de comissão.

2. **Uma venda pode gerar vários direitos independentes de comissão.**
   Agente, vendedor, gerente, técnico de campo e outro participante autorizado podem coexistir no mesmo pedido. Não se trata de dividir uma única comissão; cada participante possui sua própria política e memória de cálculo.

3. **Recebimento não encerra a possibilidade de incluir participante.**
   Recebimento parcial ou total controla a liberação financeira. Um participante adicional pode ser registrado depois, com justificativa e revisão, e recebe proporcionalmente o que já estiver financeiramente liberável.

4. **Relacionamentos comerciais são opcionais.**
   Um agente pode ou não estar vinculado a vendedor. Um vendedor pode ou não estar vinculado a gerente.

5. **Relacionamentos possuem vigência.**
   A cadeia comercial atual não reescreve vendas anteriores.

6. **O pedido preserva snapshot da estrutura usada.**
   Mudanças futuras em agente, vendedor ou gerente não reinterpretam silenciosamente a venda histórica.

7. **Política de comissão é versionada.**
   A pessoa pode ser comissionável ou não. Percentuais são definidos por pessoa, grupo de produto e papel, com vigência. Alterar condição comercial cria nova versão.

8. **Percentuais são dados de domínio normalizados.**
   Valores como 2%, 3% ou 5% não são constantes em código e não ficam escondidos em JSON livre.

9. **Meta e liberação financeira continuam subdomínios diferentes.**
   O ledger append-only de metas já existente permanece a fonte de vendido líquido por período. Recebimento continua sendo o gatilho de liberação financeira.

10. **Devolução por qualidade não penaliza meta comercial.**
    Mantém-se a regra já existente do ledger de metas. Demais devoluções podem gerar abatimento conforme motivo auditado.

11. **Alteração posterior de comissão exige confirmação em duas etapas.**
    Etapa 1 prepara a alteração e exibe antes/depois/impacto. Etapa 2 confirma. A etapa 1 não grava o novo direito financeiro.

12. **Mudança de contexto invalida confirmação.**
    Se pedido, pessoa, recebimentos ou composição mudarem entre revisão e confirmação, a proposta deve ser refeita.

13. **Idempotência é obrigatória.**
    Repetir clique ou requisição não pode criar direito ou movimento financeiro duplicado.

14. **Ledger financeiro é append-only.**
    Pagamentos, créditos, estornos e compensações são movimentos. Não se apaga fato financeiro para “corrigir saldo”.

## Objetos de domínio

- `CommercialRelationship`
- `CommissionPolicy`
- `CommissionGroupRate`
- `CommercialStructureSnapshot`
- `CommissionEntitlement`
- `CommissionChangeRequest`
- `CommissionRelease`
- `CommissionMovement`
- `TargetPeriod`
- `TargetMovement`

A implementação pode usar SQL e TypeScript sem transformar cada conceito em classe. O requisito é encapsular invariantes e responsabilidades, não produzir hierarquia artificial de classes.

## Fluxo de alteração manual

1. Operador escolhe pedido de venda.
2. Sistema resolve pedido por ID, sem depender da página atual da busca.
3. Operador informa participante, papel, percentual e justificativa.
4. Sistema cria **proposta** e calcula impacto.
5. Tela apresenta revisão.
6. Operador confirma.
7. Backend compara o hash do contexto.
8. Se o contexto mudou, nada é gravado e uma nova revisão é exigida.
9. Se confirmado, cria-se novo direito de comissão.
10. Havendo recebimentos anteriores, gera-se somente a liberação proporcional ainda inexistente para aquele novo direito.

## Entregas

### Fase 1 — fundação e segurança
- relacionamentos comerciais temporais;
- políticas versionadas pessoa × grupo × papel;
- snapshot estrutural;
- proposta/confirmacão;
- inclusão posterior a recebimento;
- consulta de pedido por ID;
- remoção do bloqueio que tornava venda recebida “inelegível”.

### Fase 2 — interface e automação
- cadastro visual de política na pessoa;
- lookup contextual do Financeiro;
- revisão com antes/depois/impacto;
- materialização automática da comissão do vendedor;
- derivação opcional agente → vendedor → gerente;
- snapshot no momento da venda.

### Fase 3 — metas e aceleradores
- usar `com_meta_periodos` e `com_meta_movimentos` existentes;
- configurar faixas por pessoa/período/grupo;
- congelar a regra aplicada em cada direito;
- tratar excedente de meta sem recalcular história.

## Antipadrões explicitamente proibidos

- percentual fixo no código;
- regra de comissão dentro de componente React;
- lookup genérico apresentando registros que a operação rejeita;
- busca de registro selecionado apenas dentro da página atual;
- edição destrutiva de movimento financeiro;
- atualização de política histórica em vez de nova versão;
- cadeia comercial inferida hoje para recalcular venda antiga;
- JSON livre como fonte primária de percentuais ou faixas.
