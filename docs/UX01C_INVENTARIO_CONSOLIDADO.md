# UX-01C - inventario consolidado de Cadastros

## Finalidade

Este documento consolida o gate de dados do macrociclo UX-01C. Ele nao
autoriza migration, RPC, RLS ou alteracao de regra de negocio. Partes seguras
podem ser implementadas sobre contratos existentes; lacunas estruturais ficam
pendentes ate decisao humana.

Classificacao primaria: `Texto livre`, `Valor controlado`, `Relacionamento` ou
`Calculado`.

## UX-01C.2 - Clientes e propriedades

| Campo | Finalidade | Atual | Classe correta | Fonte de verdade | Valor interno / rotulo PT-BR | Dependencia e obrigatoriedade | Estado |
|---|---|---|---|---|---|---|---|
| Tipo de pessoa | Distinguir PF/PJ | Inexistente | Valor controlado | Regra cadastral | Decisao pendente / Pessoa fisica, Pessoa juridica | Obrigatorio no cliente | Falta campo e regra |
| Tipo de cliente/canal | Distinguir agricultor, revenda, loja, distribuidor e outros modelos autorizados | Inexistente | Valor controlado | Politica comercial | Decisao pendente / Rotulos a homologar | Obrigatorio antes de operar revendas e lojas | Falta catalogo, regra e vigencia |
| Estabelecimento | Representar matriz, filial ou unidade comercial | Inexistente | Relacionamento | Cliente pessoa juridica | ID / Estabelecimento | Condicional para revenda, loja ou distribuidor | Falta entidade e regra de principalidade |
| Nome principal | Identidade | `cad_clientes.nome` | Texto livre | Operador | Texto / Nome ou razao social | Obrigatorio | Existe |
| Nome fantasia | Identidade comercial | Inexistente | Texto livre | Operador | Texto / Nome fantasia | Opcional para PJ | Falta campo |
| Situacao | Uso operacional | `status` | Valor controlado | Constraint existente | `active`, `pending_review`, `inactive` / Ativo, Em revisao, Inativo | Obrigatorio | Existe; UI antiga exibe enum cru |
| Codigo legado | Rastreio Excel | `codigo_legado` | Valor controlado de auditoria | Importacao | Texto / Codigo legado | Opcional; somente leitura quando importado | Existe apenas no cliente |
| Origem | Distinguir sistema/Excel | `origem_dados` | Calculado | Sistema/importacao | `sistema`, `excel_legado` / Sistema, Excel legado | Nao editavel | Existe apenas no cliente |
| Apelidos | Busca historica | `apelidos_json` | Texto livre governado | Operador/importacao | Lista / Apelidos | Opcional | Existe |
| Grafias historicas | Busca e deduplicacao | Inexistente | Relacionamento historico | Importacao/revisao | Alias tipado / Grafias historicas | Opcional | Falta estrutura consultavel |
| Documento | CPF, CNPJ, IE | `cad_cliente_documentos` | Valor controlado | Tipo documental + numero normalizado | `cpf`, `cnpj`, `ie`, `outro` / CPF, CNPJ, IE, Outro | Cliente obrigatorio; propriedade opcional | Existe; sem RPC auditada |
| UF | Localizacao | Texto de 2 caracteres | Relacionamento | Catalogo oficial | ID/codigo / UF | Obrigatorio | Falta catalogo e FK |
| Municipio | Localizacao | Texto livre | Relacionamento dependente | Catalogo oficial IBGE | ID / Municipio | Depende da UF; obrigatorio | Falta catalogo e FK |
| Endereco | Entrega/cobranca | Inexistente | Relacionamento | Cliente ou propriedade | Tipo controlado / Endereco | Opcional | Falta tabela e regra de principalidade |
| Propriedade | Fazenda/unidade | `cad_cliente_propriedades` | Relacionamento | Cliente | `cliente_id` / Cliente proprietario | Cliente e nome obrigatorios | Existe; sem RPC auditada |
| CNPJ da propriedade | Identidade fiscal propria | Texto e documento possivel | Valor controlado | Documento normalizado | CNPJ / CNPJ | Opcional | Modelo duplicado precisa ser unificado |
| Contato | Compras, gerente etc. | `cad_cliente_contatos` | Relacionamento | Cliente/propriedade | ID / Contato | Telefone ou e-mail obrigatorio | Existe; sem RPC auditada |
| Papel do contato | Funcao do contato | Texto livre | Valor controlado | Catalogo inexistente | Decisao pendente / Compras, Gerente etc. | Obrigatorio | Falta catalogo |
| Vendedor vinculado | Atendimento | `cad_cliente_vendedores` | Relacionamento temporal | Pessoa comercial + papel | IDs / Pessoa e papel | Cliente; propriedade opcional | Existe; sem RPC operacional |
| Area comercial | Carteira/regiao | `cad_cliente_areas_comerciais` | Relacionamento temporal | `cad_areas_comerciais` | IDs / Area comercial | Cliente; propriedade opcional | Existe; sem RPC operacional |
| Duplicidade | Evitar cliente repetido | Issue generica | Calculado | Nome, documento, aliases | Indicador / Possivel duplicidade | Antes de confirmar criacao | Parcial |
| Unificacao | Consolidar duplicados | Inexistente | Relacionamento/evento | Cliente mantido e absorvido | IDs / Unificar clientes | Motivo e alcada obrigatorios | Falta contrato auditado |

## UX-01C.3 - Pessoas e vinculos comerciais

| Campo | Finalidade | Atual | Classe correta | Fonte de verdade | Valor interno / rotulo PT-BR | Dependencia e obrigatoriedade | Estado |
|---|---|---|---|---|---|---|---|
| Nome | Identidade | `nome` | Texto livre | Operador | Texto / Nome | Obrigatorio | Existe |
| Codigo legado | Rastreio | `codigo_legado` | Valor controlado de auditoria | Importacao | Texto / Codigo legado | Opcional | Existe |
| Tipo comercial | Classificacao inicial | Enum textual | Valor controlado | Constraint existente | Valores atuais / rotulos centralizados | Obrigatorio conforme papel | Existe; UI central exibe enum cru |
| Papeis | Vendedor, agente, gerente, tecnico, entregador, comissionado | JSON + tabela relacional de papeis | Valor controlado multiplo | Contrato de pessoas | Valores atuais / rotulos PT-BR | Ao menos um | Existe; duas representacoes exigem fonte unica na leitura |
| Vendedor responsavel | Vinculo de agente | FK para pessoa | Relacionamento | Pessoa ativa com papel vendedor | ID / Vendedor responsavel | Obrigatorio para agente vinculado | Existe |
| Apelidos | Busca | JSON/aliases | Relacionamento historico | Operador/importacao | Alias / Apelidos | Opcional | Existe |
| Grafias incorretas | Busca historica | JSON/aliases | Relacionamento historico | Importacao/revisao | Alias / Grafias historicas | Opcional | Existe |
| Situacao | Uso operacional | `status` | Valor controlado | Constraint | Valores atuais / Ativo, Em revisao, Inativo | Obrigatorio | Existe |
| Papel no cliente | Cadastrou, atende, gerencia, apoio | Catalogo relacional | Relacionamento | `cad_cliente_vinculo_papeis` | ID / Nome do papel | Cliente e pessoa obrigatorios | Existe; sem RPC operacional |
| Propriedade atendida | Escopo do vinculo | FK composta | Relacionamento dependente | Propriedades do cliente | ID / Propriedade | Opcional | Existe |
| Vigencia | Historico comercial | Datas | Valor controlado | Regra temporal | Datas / Inicio e fim | Intervalos nao podem sobrepor | Existe |
| Area comercial | Regiao de atuacao | Relacao temporal | Relacionamento | `cad_areas_comerciais` | ID / Area | Opcional | Existe; sem manutencao governada |

## UX-01C.4 - Materias-primas e insumos

| Campo | Finalidade | Atual | Classe correta | Fonte de verdade | Valor interno / rotulo PT-BR | Dependencia e obrigatoriedade | Estado |
|---|---|---|---|---|---|---|---|
| SKU | Identidade operacional | `sku_corrigido` | Valor controlado | Regra unica | Codigo / SKU | Obrigatorio e unico | Existe com RPC por eixo |
| Nome | Identidade | `nome` | Texto livre | Operador | Texto / Nome | Obrigatorio | Existe |
| Codigo legado | Rastreio | `codigo_legado` | Auditoria | Importacao | Texto / Codigo legado | Opcional | Existe |
| Tipo de insumo | Liquido, solido, embalagem etc. | Texto livre | Valor controlado | Catalogo inexistente | Decisao pendente / Tipo | Obrigatorio para regras tecnicas futuras | Falta catalogo |
| Unidade base | Estoque e formula | Texto + FK sincronizada | Relacionamento | `cad_unidades_medida` | ID/codigo / Unidade base | Obrigatorio | Fonte existe; UI especializada ja usa select |
| Densidade | Conversoes massa/volume | Numerico | Valor controlado estruturado | Laudo/fornecedor | Decimal / Densidade | Opcional, positiva | Existe |
| Estoque minimo | Politica de reposicao | Numerico | Valor controlado estruturado | Gestor de estoque | Decimal / Estoque minimo | Opcional, nao negativo | Existe |
| NCM | Fiscal | Texto validado | Valor controlado estruturado | Classificacao fiscal | 8 digitos / NCM | Opcional | Existe |
| IBAMA | Regulatorio | Texto | Texto livre estruturado | Documento oficial | Texto / Registro IBAMA | Opcional | Existe |
| ADS | Regulatorio | Texto | Texto livre estruturado | Documento oficial | Texto / Codigo ADS | Opcional | Existe |
| Situacao | Uso operacional | `status` | Valor controlado | Constraint | Valores atuais / Ativa, Em revisao, Inativa | Obrigatorio | Existe |
| Origem | Sistema/Excel | `origem_dados` | Calculado | Sistema/importacao | Valores atuais / Sistema, Excel legado | Nao editavel | Existe |

## UX-01C.5 - Produtos, apresentacoes, embalagens e conversoes

| Campo | Finalidade | Atual | Classe correta | Fonte de verdade | Valor interno / rotulo PT-BR | Dependencia e obrigatoriedade | Estado |
|---|---|---|---|---|---|---|---|
| Codigo do produto | Identidade PA/PI | `codigo_produto` | Valor controlado | Regra 0001-9999 | Codigo / Codigo | Obrigatorio e unico | Existe |
| Nome do produto | Identidade | `nome` | Texto livre | Operador | Texto / Nome | Obrigatorio | Existe |
| Grupo | Linha/familia | Codigo + `grupo_id` | Relacionamento | `cad_grupos_produto` | ID/codigo / Grupo | Opcional | Fonte existe e criacao resolve por catalogo |
| Validade | Prazo em meses | Inteiro | Valor controlado estruturado | Produto | Inteiro / Validade em meses | Opcional, positivo | Existe |
| Densidade | Massa/volume | Numerico | Valor controlado estruturado | Tecnico | Decimal / Densidade kg/L | Opcional, positiva | Existe |
| MAPA, NCM, IBAMA, ADS | Dados regulatorios | Textos | Estruturado | Documentos oficiais | Textos / Rotulos proprios | Opcionais | Existem |
| Situacao do produto | Uso operacional | `status` | Valor controlado | Constraint | Valores atuais / Ativo, Em revisao, Inativo | Obrigatorio | Existe |
| Embalagem | Apresentacao fisica | `cad_embalagens` | Relacionamento | Catalogo de embalagens | ID / Embalagem | Obrigatoria no item vendavel | Existe |
| Descricao da embalagem | Identidade | Texto | Texto livre | Operador | Texto / Descricao | Obrigatorio | Existe |
| Unidade da embalagem | Medida | Texto + FK | Relacionamento | `cad_unidades_medida` | ID/codigo / Unidade | Obrigatorio | Existe |
| Volume | Capacidade | Numerico | Valor controlado estruturado | Especificacao | Decimal / Volume em litros | Opcional | Existe |
| Controla estoque | Embalagem como insumo | Booleano | Valor controlado | Regra operacional | Booleano / Controlar como insumo | MP obrigatoria quando verdadeiro | Existe |
| MP vinculada | Insumo de embalagem | FK | Relacionamento | Materias-primas ativas | ID / MP de estoque | Condicional | Existe |
| Codigo do item | Identidade produto+embalagem | `codigo_item` | Valor controlado | Regra do item vendavel | Codigo / Codigo da apresentacao | Obrigatorio e unico | Existe |
| Conversao de MP | Unidade da NF para estoque | Relacao com unidades | Relacionamento temporal | MP + unidades canonicas | IDs/fator / Conversao | Obrigatoria por regra cadastrada | Existe |
| Fator | Conversao quantitativa | Numerico | Valor controlado estruturado | Regra tecnica | Decimal / Fator | Positivo | Existe |
| Vigencia | Periodo da conversao | Datas | Valor controlado | Regra temporal | Datas / Vigencia | Intervalo valido | Existe |
| Edicao/desativacao | Manter produto, embalagem e item | Ausente | Acao auditada | Dominio Cadastros | Motivo / Acao | Alcada obrigatoria | Faltam RPCs por eixo |
| Composicao da embalagem | Componentes versionados | Tabelas DEC-008 | Relacionamento versionado | Embalagem e MP | IDs / Componentes | Versao e ativacao | Existe no banco; sem UI/RPC operacional completa |

## UX-01C.6 - Veiculos, logistica, tecnicos e validacao

| Campo | Finalidade | Atual | Classe correta | Fonte de verdade | Valor interno / rotulo PT-BR | Dependencia e obrigatoriedade | Estado |
|---|---|---|---|---|---|---|---|
| Descricao do veiculo | Identidade | `descricao` | Texto livre | Operador | Texto / Veiculo | Obrigatorio | Existe; sem RPC |
| Placa | Identidade legal | Texto normalizado | Valor controlado estruturado | Documento do veiculo | Placa / Placa | Opcional e unica | Existe; sem RPC |
| Capacidade | Limite de carga | Numerico | Valor controlado estruturado | Veiculo | Decimal / Capacidade | Opcional, positiva | Existe |
| Unidade da capacidade | Medida | FK | Relacionamento | `cad_unidades_medida` | ID / Unidade | Obrigatoria quando ha capacidade | Existe |
| Situacao do veiculo | Uso operacional | `status` | Valor controlado | Constraint | Valores atuais / Ativo, Em revisao, Inativo | Obrigatorio | Existe |
| Codigo/origem legados | Rastreio | Campos existentes | Auditoria | Importacao | Valores internos / Rotulos PT-BR | Nao editavel quando importado | Existe |
| Unidades canonicas | Medidas oficiais do sistema | Catalogo DEC-007 | Relacionamento | `cad_unidades_medida` | ID/codigo / Unidade | Governado | Existe; somente leitura operacional |
| Alias de unidade | XML e historico | Catalogo | Relacionamento temporal | `cad_unidade_aliases` | ID/texto / Alias | Contexto obrigatorio | Existe; sem RPC operacional |
| Nutrientes | Garantias e especificacoes | Catalogo | Relacionamento | `cad_nutrientes` | ID / Nutriente | Governado | Existe; somente leitura operacional |
| Alias de nutriente | Nomes historicos | Catalogo | Relacionamento temporal | `cad_nutriente_aliases` | ID/texto / Alias | Contexto obrigatorio | Existe; sem RPC operacional |
| Parametro tecnico | pH, densidade etc. | Catalogo | Relacionamento | `cad_parametros_tecnicos` | ID / Parametro | Tipo e unidade dependentes | Existe; sem UI/RPC operacional |
| Tipo de valor | Numerico ou texto | Enum | Valor controlado | Constraint | `numeric`, `text` / Numerico, Texto | Parametro obrigatorio | Existe |
| Fila de validacao | Pendencias cadastrais | `cadastro_validation_issues` | Calculado/relacionamento | Validadores | Status e severidade / Rotulos PT-BR | Somente leitura inicial | Existe |
| Entidade/codigo da issue | Diagnostico interno | Exibido cru | Calculado traduzido | Mapa de entidades/codigos | Chave tecnica / Mensagem operacional | Nao exibir cru | UI atual viola governanca |
| Resolver pendencia | Fechar revisao | Campos de resolucao | Acao auditada | Fila de validacao | Motivo/status / Resolver | Alcada obrigatoria | Falta RPC operacional |

## Componentes compartilhados aprovados no desenho

- mapa centralizado de situacoes, origens, tipos e estados de revisao;
- `StatusSelect`, `UfSelect`, busca relacional e campo dependente;
- autocomplete que persiste ID sem interpretar texto;
- painel de consulta, filtros, estados e mensagens operacionais;
- formularios dedicados, uma acao principal por vez;
- confirmacao com motivo para desativacao, substituicao, ativacao e unificacao;
- adaptacao desktop, notebook e mobile sem rolagem horizontal.

## Matriz decisoria estrutural unica

| Bloco | Lacuna | Mudanca minima proposta | Ownership | Impacto |
|---|---|---|---|---|
| Clientes | PF/PJ, nome fantasia e grafias | Ampliar identidade e criar aliases consultaveis | Cadastros | Migration + RPCs de identidade |
| Clientes comerciais | Revendas, lojas, distribuidores, matriz e filiais | Catalogo de tipo de cliente e estabelecimentos relacionados | Cadastros/Comercial/Fiscal | Decisao funcional + migration + RPCs auditadas |
| Localizacao | UF/municipio livres | Catalogos oficiais e FKs dependentes | Cadastros | Migration, carga de catalogo e backfill sem inventar dados |
| Enderecos | Entidade ausente | Tabela cliente/propriedade com tipo e principalidade | Cadastros | Migration + RPCs auditadas |
| Propriedades/documentos/contatos | Tabelas sem escrita governada | RPCs por acao, soft-delete e auditoria | Cadastros | Permission actions + RPC + testes RLS |
| Contatos | Papel livre | Catalogo de papeis de contato | Cadastros | Migration + FK/backfill pendente |
| Vinculos comerciais | Sem operacao auditada | RPCs temporais para pessoa e area | Cadastros | RPC + alçadas + logs correlacionados |
| Duplicidades | Sem unificacao segura | Evento append-only de unificacao e redirecionamento | Cadastros | Regra nova; exige decisao funcional |
| Materias-primas | Tipo livre | Catalogo de tipos de insumo | Cadastros/Estoque | Migration + FK; valores atuais ficam em revisao |
| Produtos/embalagens | Apenas criacao | RPCs de edicao por eixo e desativacao | Cadastros/Producao/Estoque | Alçadas e auditoria por risco |
| Composicao de embalagem | Sem fluxo operacional | RPCs de versao, componentes e ativacao | Cadastros/Estoque | Usa tabelas DEC-008 existentes |
| Veiculos | Sem RPC/tela | CRUD auditado com soft-delete | Cadastros/Expedicao | Permission actions + RPCs |
| Catalogos tecnicos | Somente leitura | RPCs de criar, revisar, ativar e desativar | Cadastros/Producao | Alçadas tecnicas; fatos historicos preservados |
| Validacao | Chaves tecnicas visiveis e sem resolucao | Mapa PT-BR e RPC de tratamento | Cadastros/Auditoria | Sem expor payload ou erro bruto |

## Decisoes necessarias antes da implementacao

1. Autorizar um pacote de migrations pequenas por ownership, nunca uma migration monolitica.
2. Adotar catalogos de UF e municipio baseados em fonte oficial IBGE, persistidos no banco para nao depender de API durante a operacao.
3. Adotar PF/PJ como classificacao do cliente e manter documentos em tabela relacional.
4. Criar enderecos opcionais de cobranca, entrega e outro, vinculados ao cliente ou a uma propriedade.
5. Criar papeis de contato governados, com `Outro` exigindo detalhe e revisao.
6. Implementar unificacao como evento auditado, sem apagar o cliente absorvido.
7. Criar alçadas/RPCs por eixo para os cadastros hoje somente leitura ou somente criacao.
8. Tratar dados existentes sem correspondencia de catalogo como `pending_review`, sem inventar classificacao.
9. Homologar separadamente o modelo de revenda, loja e distribuidor, incluindo matriz/filial, documentos, enderecos e regras fiscais; o layout de agricultor nao autoriza essa modelagem.

## Gate atual

A Onda 1 implementa consulta, busca, criacao e edicao de clientes, alem da
leitura relacional de propriedades e vendedores, usando somente contratos
existentes. Criacao e manutencao de propriedades, catalogo de municipios,
enderecos, contatos e unificacao continuam pendentes porque exigem alteracao
estrutural. O layout foi homologado para o fluxo atual de agricultor; revendas,
lojas e distribuidores permanecem fora do escopo funcional ate decisao propria.
Nenhuma dessas mudancas foi criada por este inventario.
