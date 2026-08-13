# Pessoas e vinculos comerciais

## Finalidade

Manter pessoas comerciais, seus papeis e relacionamentos operacionais sem
confundir papel comercial com perfil de acesso ao sistema.

## Distincao essencial

- **papel comercial** identifica vendedor, agente, gerente ou outra funcao de negocio;
- **usuario do sistema** possui e-mail, autenticacao, perfil e permissoes no modulo Seguranca;
- alterar papel comercial nao concede acesso ao sistema;
- conceder acesso nao deve ser feito no cadastro comercial.

## Nova pessoa

1. Abra **Cadastros > Pessoas**.
2. Pesquise nome, apelido ou codigo legado.
3. Revise pessoas semelhantes apresentadas pelo sistema.
4. Informe a identidade e os papeis comerciais aplicaveis.
5. Se for um homonimo real, confirme e registre justificativa suficiente.
6. Grave e confira o historico da ficha.

## Papeis e responsavel

- uma pessoa pode possuir mais de um papel;
- inclusoes e remocoes de papeis ficam explicitas na auditoria;
- vendedor responsavel e selecionado por ID;
- mudanca de papel exige motivo padronizado e, quando aplicavel, detalhe.

## Areas comerciais

1. Escolha uma area ativa.
2. Informe papel na area e inicio da vigencia.
3. Encerre o vinculo quando a atuacao terminar.
4. Crie novo vinculo para uma nova vigencia; nao edite o periodo encerrado.

O banco recusa sobreposicao temporal invalida e repeticao concorrente do mesmo
vinculo ativo. Area inativa continua legivel no historico, mas nao pode receber
novo vinculo.

## Desativacao e reativacao

- desativacao preserva papeis, aliases, areas e fatos anteriores;
- reativacao exige permissao e justificativa;
- reativar a pessoa nao reabre automaticamente areas encerradas;
- nao crie outra pessoa para contornar uma desativacao.

## Possiveis duplicidades

Nome igual nao prova duplicidade. O sistema usa codigo legado, nomes
normalizados, apelidos, grafias historicas e vinculos como sinais para revisao.
Codigos legados iguais sao bloqueados; homonimos podem prosseguir somente com
confirmacao justificada e auditada.


## Estrutura comercial canônica

A hierarquia comercial não é inferida de um único campo de responsável.

Os vínculos possíveis são independentes e opcionais:

- **Agente → Vendedor**
- **Vendedor → Gerente**

Cada vínculo possui início e fim de vigência. Encerrar ou criar um novo vínculo
não altera vendas históricas. O campo `vendedor_responsavel_id` permanece
somente como compatibilidade para dados anteriores e não deve ser usado como
fonte canônica por novas funcionalidades.

## Política de comissão da pessoa

A pessoa pode ser marcada como comissionável ou não com uma política versionada.

Quando comissionável, cada versão registra percentuais por grupo de produto,
papel na comissão e vigência. Uma nova versão publicada encerra a vigência da
versão anterior sem apagá-la.

A ausência de política ou de taxa para determinado grupo não autoriza o sistema
a inventar percentual.
