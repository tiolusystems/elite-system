# Elite System - matriz inicial de perfis e permissoes

Data: 2026-07-12
Decisao: `DEC-005`
Estado: arquitetura autorizada; implementacao pendente

## Objetivo

Definir os conjuntos iniciais de permissoes do Elite System sem transformar
nome de perfil, cargo ou visibilidade de tela em mecanismo de autorizacao.

Cada pessoa possui conta individual. Um usuario pode receber mais de um perfil.
Cada perfil e somente um conjunto versionado de permissoes atomicas. O banco e
o backend validam cada acao efetiva.

## Perfis iniciais autorizados

| Perfil | Responsabilidade principal | Familias de permissao esperadas | Exclusoes iniciais |
|---|---|---|---|
| Administrador | usuarios, perfis, permissoes, runtime, suporte e configuracao | `security.*`, `system.admin`, administracao de Suporte e leitura de auditoria | nao executa automaticamente operacao financeira, estoque ou producao sem perfil combinado |
| PCP / Producao | formulas, OP, reservas produtivas, consumo, CQ, garantias e transformacoes | leitura de cadastros/estoque; `pcp.*`; movimentos de estoque originados por OP | sem ajuste manual de estoque, pagamento, comissao ou administracao de usuarios |
| Estoque | lotes MP/PA/PI, entradas, reservas, inventario, ajustes e reversoes autorizadas | `estoque.*`, leitura de cadastros e documentos-fonte necessarios | sem formula, pagamento, comissao ou privilegio administrativo |
| Comercial / Pedidos | clientes, propriedades, pedidos, credito conforme alcada, carteira e Kanban | `cadastros` comerciais, `pedidos.*`, consultas de status permitidas | sem baixa fisica, emissao fiscal, recebimento ou pagamento de comissao |
| Expedicao / Faturamento | romaneio, separacao, confirmacao, expedicao e documentos fiscais | `romaneios.*`, `faturamento.*`, leitura de pedido e estoque disponivel | sem formula, ajuste financeiro ou administracao de usuarios |
| Financeiro / Recebimentos e Comissoes | recebimentos, alocacoes, liberacao, pagamento e conta corrente de comissao | `financeiro.*`, leitura fiscal/comercial necessaria | sem producao, movimento fisico independente ou administracao de privilegios |
| Consulta / Auditoria | consulta transversal, relatorios, rastreabilidade e evidencias | `*.view`, `audit.view` e reconciliacoes expressamente autorizadas | nenhuma escrita operacional |

Esta tabela define responsabilidade, nao a lista definitiva de action keys. A
implementacao deve materializar e revisar cada permissao atomica contra o
catalogo vigente antes da migration.

## Combinacao de perfis

- um usuario pode possuir zero, um ou varios perfis ativos;
- perfil ativo concede somente suas permissoes atomicas cadastradas;
- ausencia de concessao significa negacao;
- override individual negando uma acao prevalece sobre concessao de perfil;
- concessao individual excepcional exige administrador autorizado e auditoria;
- perfil inativo nao participa do calculo;
- conta ou perfil de usuario inativo nao obtém acesso;
- operacao critica continua sujeita a seus guards de dominio, mesmo quando a
  permissao atomica estiver concedida.

O calculo efetivo deve existir em funcao unica no banco. A aplicacao pode
consultar o resultado, mas nao pode recalcular autorizacao por conta propria.

## Contas individuais

- uma pessoa, uma identidade Auth e um perfil humano vinculavel;
- proibidas contas compartilhadas como `financeiro@`, `estoque@` ou
  `producao@` usadas por varias pessoas;
- e-mail e fator MFA pertencem a pessoa, nao ao setor;
- afastamento ou desligamento desativa a conta individual;
- ator tecnico nao pode ser usado para login humano;
- auditoria registra o usuario real que executou a acao.

## Autorizacao em camadas

Toda operacao protegida precisa passar por:

1. sessao Auth valida;
2. perfil humano ativo;
3. permissao atomica efetiva calculada no banco;
4. modulo disponivel no runtime;
5. regra de escopo do dominio, como `own/any`, familia, evento ou valor;
6. validacao de estado e integridade;
7. auditoria do resultado.

Ocultar menu, botao ou campo melhora a interface, mas nao autoriza nem bloqueia
uma acao por si so.

## Operacoes criticas

Exigem auditoria completa e action key propria:

- mudanca de perfil, permissao ou privilegio;
- convite, ativacao, desativacao e recuperacao administrativa de usuario;
- cancelamento ou estorno operacional;
- ajuste e reversao de estoque;
- emissao, cancelamento ou substituicao fiscal;
- recebimento, reversao, ajuste financeiro e baixa;
- liberacao, ajuste e pagamento de comissao;
- mudanca de ambiente ou rollout de modulo.

Quando o fluxo de MFA estiver disponivel, operacoes financeiras, cancelamentos,
estornos, pagamentos de comissao e mudancas de privilegio devem exigir
reautenticacao ou sessao `aal2`, conforme `DEC-002`, `DEC-003` e `DEC-004`.

## Separacao de funcoes

- Administrador governa acesso, mas nao recebe automaticamente poderes de
  operacao dos demais perfis;
- Consulta / Auditoria nao escreve fato operacional;
- pagamento de comissao e alteracao de sua regra usam permissoes diferentes;
- registrar recebimento e reverter recebimento usam permissoes diferentes;
- executar operacao e aprovar excecao devem ser separaveis por action key;
- combinacao de perfis nao elimina trava de escopo, estado ou MFA.

## Transicao do modelo atual

O schema atual possui `user_profiles.role` como classificacao unica e
`user_permission_overrides` por usuario. A implementacao de `DEC-005` devera:

1. preservar contas e auditoria existentes;
2. criar catalogo versionado de perfis;
3. relacionar perfil com permissao atomica;
4. relacionar usuario com varios perfis;
5. migrar o papel atual para perfil equivalente quando houver correspondencia;
6. criar tratamento explicito para Financeiro, que nao existe como papel Auth
   autonomo no modelo atual;
7. manter overrides durante a transicao;
8. reconciliar permissao efetiva antes e depois;
9. remover dependencia do papel unico somente apos smoke e homologacao.

Nomes de tabelas e assinatura da funcao efetiva serao definidos na tarefa de
implementation design; este documento nao cria schema.

## Auditoria da administracao de perfis

Devem registrar `before/after`, ator, motivo e correlation id:

- criacao, alteracao, ativacao e desativacao de perfil;
- adicao ou remocao de permissao atomica no perfil;
- atribuicao ou retirada de perfil do usuario;
- override individual;
- tentativa negada de mudanca de privilegio;
- versao do perfil usada no momento da decisao.

O ultimo administrador capaz continua protegido contra lockout.

## Criterios de aceite da implementacao futura

- sete perfis iniciais cadastrados por migration;
- combinacao de dois ou mais perfis validada;
- nenhuma conta funcional compartilhada;
- default deny para permissao ausente;
- deny individual prevalece sobre grant de perfil;
- backend e banco negam chamadas diretas sem permissao;
- interface deriva visibilidade da permissao efetiva, sem ser fonte de verdade;
- operacoes criticas geram auditoria completa;
- plano de MFA/AAL2 integrado aos pontos criticos;
- migracao do papel atual reconciliada sem perda de acesso legitimo;
- smoke de escalada e regressao de zero-grant aprovados;
- administrador atual preservado sem criar backdoor permanente.
