---
description: Plano Queimão até 15/12/2026 — zera estoque da loja em todas as Shopee e players com margem controlada
argument-hint: "[diagnosticar|publicar|conferir]"
---

Conduza o Plano Queimão: vender tudo que está na loja física até **15/12/2026**,
em todas as contas Shopee e nos players, com margem apertada e sem furar
preço de custo. Use o agente `queimao` (`.claude/agents/queimao.md`) para
orquestrar.

Argumento recebido: `$ARGUMENTS`

## Modos

- Vazio ou `diagnosticar` → só lê:
  1. Puxa o estoque atual do Argos (apenas itens com saldo > 0).
  2. Cruza com o relatório mais recente do `/espião` (preço de concorrentes
     e volume) e com a planilha de fotos.
  3. Monta a lista final (SKU, estoque, custo, preço sugerido, margem,
     foto da capa, canal de destino) e grava em
     `%USERPROFILE%\Desktop\queimao-<data>.csv`.
  4. **Não** publica nada.
- `publicar` → aplica as mudanças:
  1. Confirma com o operador o CSV do passo anterior.
  2. Em cada conta Shopee (`integrarsve`, demais do grupo) e em cada player
     (Mercado Livre, Magalu, TikTok Shop, Amazon):
     - cria/atualiza a oferta no combo "FREE" e o desconto "Queimão Black"
       dentro das janelas já agendadas (ver screenshots do Seller Center),
     - sobe a capa do anúncio com a foto da planilha + selo "Queimão",
     - trava a janela em 02/11/2026–15/12/2026.
  3. Registra no `/cerebro` o lote publicado e aciona os vigias.
- `conferir` → só confere o publicado:
  - Lê Shopee/players e compara com o CSV; aponta divergências; não corrige
    sozinho.

Qualquer outro argumento → não rode nada; diga que os usos são
`/queimao`, `/queimao publicar` e `/queimao conferir`.

## Matriz de preço (regra de ouro)

| Categoria do item | Margem | Observação |
|---|---:|---|
| **Balões** (todos os SKUs) | **1 %** | Queima absoluta. Precisa gerar caixa. |
| **Loja física — itens listados**: bucha, palha de aço, malas de bordo PP ABS, garrafa de azeite, canetinha 30/40, bolsa pet | **4 %** | Prioridade total até 15/12. |
| **Loja física — demais itens com estoque > 0** | **4 %** | Mesma regra; o Argos é a verdade. |
| **Itens sem estoque na loja (dropship / fornecedor)** | **18 %** | Mantém margem de operação. |

Preço de venda = `custo × (1 + margem) + taxas da plataforma + frete subsidiado`.
Nunca aceitar `preço de venda < custo + taxa Shopee`. Se der negativo, o item
sai do lote e o agente avisa.

## Entradas obrigatórias (sem elas, pare)

1. Argos acessível na máquina da loja (`HUDSONINTEGRAR`) ou no servidor
   `KHAOSOMNI` — se não houver, pare e peça.
2. Planilha de fotos: `%USERPROFILE%\Khaos\queimao\fotos.xlsx` (SKU → URL/arquivo).
3. Relatório do `/espião` com data ≤ 24 h; se mais velho, rode
   `/espiao atualizar` antes.
4. Credenciais Shopee já logadas no Seller Center de cada conta.

## Vigias

O agente `queimao` precisa deixar estes vigias de pé enquanto o plano estiver
ativo (`/verificar-agentes ativar` resolve o que estiver desligado):

- `vigia-queimao-estoque` — a cada 2 h, recarrega o Argos; se um SKU zerou,
  tira do ar nas contas em até 15 min.
- `vigia-queimao-margem` — diário às 06:00, confere se o preço continua
  dentro da matriz (fornecedor pode subir custo).
- `vigia-queimao-prazo` — diário às 07:00, calcula dias restantes até
  15/12/2026 e, se um SKU não vender nada em 72 h, propõe baixar a margem
  mais 1 ponto (precisa aprovação para publicar).
- `vigia-queimao-balao` — a cada 1 h, confere se os balões continuam com
  preço de 1 %; religa se alguém mexer.

## Entrega ao final

Em português, curto, nesta ordem:

1. **Veredito**: diagnosticar / publicou X SKUs em Y contas / conferiu, Z divergências.
2. **Tabela resumo**: por conta × canal, quantos SKUs ficaram ativos e o
   preço médio.
3. **Itens cortados** (preço de custo não deixou passar).
4. **Vigias**: status de cada um dos quatro (ligado, última execução, próxima).
5. **Pendências**: fotos faltando, custo desatualizado, canal sem acesso.
6. Caminho do CSV, dos relatórios de execução e do checkpoint no `/cerebro`.

## Regras

- Nunca publique sem o CSV conferido pela diretoria (Hudson aprova comercial,
  Karina aprova margem).
- Nunca mexa em preço de item **sem estoque** na loja (18 % é para
  dropship/fornecedor contínuo; item sem fluxo nenhum fica de fora).
- Nunca force Shopee quando a plataforma recusar: registre o motivo e passe
  para o próximo.
- A data **15/12/2026** é limite rígido; depois dela a skill desativa os
  descontos sozinha e deixa o preço cheio.
- Toda alteração em preço, capa ou agendamento gera linha no log do
  `/cerebro` para a próxima rodada ter contexto.
