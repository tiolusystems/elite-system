# Unidades e conversoes de materia-prima

## Finalidade

Este fluxo governa as unidades usadas em cadastro, XML de NF, estoque e
formulas. Uma conversao informa como uma quantidade recebida em determinada
unidade deve ser convertida para a unidade-base da materia-prima.

Exemplo: uma NF pode informar toneladas, enquanto o estoque da materia-prima e
controlado em quilogramas.

## Permissoes

A consulta exige usuario autenticado e perfil ativo com acesso a Cadastros.
Criacao de conversao usa RPC auditada e permissao atomica. Escrita direta nas
tabelas permanece proibida.

## Consultar unidades

1. Acesse **Cadastros > Unidades**.
2. Consulte o codigo, nome, simbolo, dimensao e situacao.
3. Use somente unidades ativas em novos relacionamentos.
4. Uma unidade inativa vinculada a dado historico continua legivel.

## Consultar conversoes

1. Na mesma tela, localize **Conversoes cadastradas**.
2. Confira a materia-prima, unidade de origem, unidade de destino, fator,
   vigencia e situacao da revisao.
3. Leia a expressao como: `1 unidade de origem = fator x unidade de destino`.

## Cadastrar conversao

1. Acione **Nova conversao**.
2. Selecione a materia-prima por ID.
3. Selecione a unidade de origem no catalogo governado.
4. Selecione como destino a unidade-base da materia-prima.
5. Informe fator positivo e vigencia.
6. Informe justificativa suficiente para auditoria.
7. Salve e confira a mensagem operacional.

Origem e destino precisam ser diferentes. Unidade, fator ou data nao devem ser
inventados quando o documento fiscal ou a regra tecnica nao os comprovar.

## Efeito no sistema

A conversao e usada na conferencia semiautomatica do XML/NF antes da entrada do
lote no estoque. Ela nao altera lotes antigos, nao recalcula movimentos ja
confirmados e nao muda a unidade-base da materia-prima.

## Estados e erros esperados

- **Sem conversoes:** a tela orienta criar a primeira regra.
- **Sem permissao:** a operacao e negada sem exibir SQL ou nome de RPC.
- **Unidade inativa:** permanece consultavel, mas nao pode receber novo vinculo.
- **Fator invalido:** valor nulo, zero ou negativo e recusado.
- **Vigencia invalida:** data final anterior a inicial e recusada.
- **Regra repetida:** a chave canonica e a concorrencia sao protegidas no banco.

## Limitacoes vigentes

- a tela ainda precisa de gate visual final no macrociclo UX-01C;
- aprovacao e revisao funcional devem seguir o contrato ja existente;
- alteracao de conversao vigente deve preservar historico, nunca sobrescrever
  silenciosamente uma regra que ja participou de entrada de estoque.
