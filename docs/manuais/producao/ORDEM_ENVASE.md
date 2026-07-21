# OP MAPA e Ordem de Envase

## Quando usar

Use este fluxo depois que a produção operacional gerou um lote PI e o Controle
de Qualidade liberou esse lote. A OP MAPA é documental. A Ordem de Envase é a
operação física que consome PI e embalagens e gera um ou mais lotes PA.

## Emitir

1. Acesse **Produção > OP MAPA e envase**.
2. Selecione a fórmula MAPA ativa.
3. Selecione o lote PI liberado.
4. Selecione o produto e sua embalagem comercial.
5. Informe o volume em litros.
6. Acione **Emitir documentos**.

O sistema confirma que fórmula, PI e apresentação pertencem ao mesmo produto,
que existe composição de embalagem aprovada e que o saldo PI é suficiente. A
OP MAPA e a Ordem de Envase nascem juntas e ficam vinculadas.

## Separar embalagens

Em cada componente previsto, selecione um lote disponível e informe a
quantidade. A reserva reduz o saldo disponível, mas ainda não baixa o saldo
físico. Todos os componentes precisam estar integralmente reservados.

## Imprimir e executar

Acione **Imprimir ordem**. O documento informa lote PI, apresentação,
embalagens, usuário emissor, data, hora e terminal. Os operadores preenchem
fisicamente os horários de início e término e assinam o papel. Não há múltiplos
logins na Ordem de Envase.

## Finalizar

1. Acione **Iniciar envase** depois de conferir as reservas.
2. Informe a quantidade de cada lote PA de destino. Podem existir vários lotes.
3. A soma deve ser exatamente igual à quantidade PA planejada.
4. Acione **Finalizar e gerar PA**.

Na mesma transação, o sistema baixa o PI, baixa as embalagens, encerra as
reservas e cria os lotes PA. Esses lotes passam a alimentar Romaneio.

## Rastreabilidade

`PI liberado -> OP MAPA -> Ordem de Envase -> embalagens reservadas -> consumo PI/embalagens -> lote PA -> Romaneio`

IP, geolocalização e identificação ampliada do dispositivo pertencem ao
controle global de Segurança e Sessões. A Ordem registra o terminal disponível
na sessão de emissão e não inventa coordenadas ausentes.
