# Identidade visual do Elite System

## Objetivo

Este documento governa o uso da identidade oficial da Elite Agrociências no
Elite System. A interface deve ser institucional, legível e operacional. A
marca identifica o sistema, mas não compete com o conteúdo de trabalho.

## Arquivo mestre e origem

- Arquivo mestre: `Logo Elite curva OK - registrado - sem fundo.pdf`.
- Origem: acervo oficial fornecido por Luciano em 16/07/2026.
- Tipo: PDF vetorial, página de 510,2362 x 215,4331 pt.
- Derivado web permitido: `apps/web/public/brand/elite-agrociencias-logo.png`.
- Derivado web: PNG RGBA de 2126 x 898 px, gerado diretamente do PDF mestre.
- O JPEG fornecido é somente referência visual e não é o arquivo mestre.

O repositório não mantém material de impressão, conversões intermediárias ou
duplicações do arquivo mestre. Não existe símbolo compacto oficial separado;
portanto, nenhum `mark`, monograma ou ícone de marca deve ser inventado.

## Versões permitidas

1. Logomarca integral sobre fundo claro.
2. Logomarca integral, sem deformação, reduzida proporcionalmente até o tamanho
   mínimo definido neste documento.

Não há versão negativa ou monocromática autorizada nesta fase. Sobre fundo
escuro, a marca deve permanecer em uma superfície branca com área de proteção,
sem recoloração.

## Paleta e origem

As cores institucionais foram amostradas do arquivo oficial fornecido. As cores
de estado são derivações funcionais destinadas a contraste e acessibilidade.

| Token | HEX | Uso |
| --- | --- | --- |
| `brand-primary` | `#1CABE3` | azul institucional e indicador ativo |
| `brand-primary-strong` | `#0879A8` | links, foco e texto de destaque |
| `brand-secondary` | `#02A74B` | verde institucional e apoio |
| `brand-accent` | `#FDF001` | amarelo institucional, uso pontual |
| `surface` | `#FFFFFF` | superfície principal |
| `surface-muted` | `#F3F7F9` | fundo operacional secundário |
| `border` | `#D4E0E6` | bordas e divisórias |
| `text` | `#231F1E` | texto principal, extraído da marca |
| `text-muted` | `#5E6D75` | texto secundário |
| `focus` | `#0879A8` | foco de teclado |
| `success` | `#16834A` | sucesso operacional |
| `warning` | `#A56700` | atenção e pendência |
| `danger` | `#B4232D` | erro e bloqueio crítico |
| `info` | `#0879A8` | informação operacional |

Os tokens CSS usam o prefixo `--brand-`. Eles são aplicados ao shell
autenticado sem alterar silenciosamente os contratos visuais do UX-01A.

## Proporção, proteção e tamanho mínimo

- Proporção oficial do arquivo: aproximadamente 2,367:1.
- Nunca definir largura e altura que alterem essa proporção.
- Área de proteção mínima: 10% da altura renderizada em todos os lados.
- Desktop: largura recomendada de 132 px; mínimo de 112 px.
- Mobile: largura recomendada de 82 px; mínimo de 76 px.
- Se o espaço não comportar o mínimo, usar apenas o nome do produto "Elite
  System". Não recortar nem separar letras da logomarca.

## Aplicação em fundo claro e escuro

No shell atual, a marca aparece uma única vez no cabeçalho branco. Em fundos
escuros futuros, deve ser colocada sobre superfície branca sem sombra, efeito,
contorno ou recoloração. A barra verde-amarela pertence à marca e não deve ser
recriada como decoração da interface.

## Desktop e notebook

- Cabeçalho compacto com logomarca integral à esquerda.
- Página e módulo atual permanecem textualmente identificados.
- Ambiente e usuário ficam separados da marca.
- Navegação lateral usa azul institucional somente para o item ativo.
- Verde e amarelo não dominam menus, botões ou superfícies.

## Mobile

- Botão de menu permanece o primeiro controle e possui área de toque adequada.
- Logomarca integral é exibida proporcionalmente quando couber.
- Módulo atual aparece ao lado da marca, sem comprimir a imagem.
- O drawer contém navegação, identidade do usuário, troca de usuário e saída.
- Não existe navegação horizontal nem rolagem lateral causada pelo shell.

## Rodapé institucional

O rodapé autenticado exibe de forma discreta: Elite System, Elite
Agrociências, ambiente, versão, ano e "Desenvolvido por TioLu Systems". A
logomarca não é repetida no rodapé.

## Estados do sistema

- Carregamento: `info`.
- Vazio: `text-muted`.
- Erro: `danger`.
- Bloqueado/atenção: `warning`.
- Sucesso: `success`.

Cor nunca é o único sinal. Cada estado deve possuir título, descrição e ação
textual quando aplicável.

## Acessibilidade

- A imagem possui texto alternativo "Elite Agrociências".
- Controles possuem foco visível.
- Texto branco não deve ser aplicado sobre o azul claro `brand-primary` quando
  o contraste for insuficiente; usar `brand-primary-strong` para ações.
- Links, estados e módulo ativo devem possuir sinal textual ou estrutural além
  da cor.
- Tamanho da marca nunca pode tornar "Agrociências" ilegível.

## Usos proibidos

- Redesenhar, reconstruir ou gerar a marca por inteligência artificial.
- Alterar letras, símbolo de registro, cores ou proporção.
- Inclinar, esticar, comprimir, recortar, sombrear ou aplicar efeitos.
- Criar monograma, ícone ou símbolo compacto não oficial.
- Converter raster em SVG falso.
- Usar a faixa verde-amarela isoladamente como elemento decorativo.
- Repetir a logomarca várias vezes na mesma tela.

## Governança

Este documento orienta UX-01B e as fases UX-01C a UX-01H. Mudança de arquivo
mestre, paleta institucional, proporção ou versão da marca exige autorização
explícita de Luciano antes da implementação.
