# Plano Queimão — até 15/12/2026

Zerar o estoque da loja física em todas as contas Shopee e nos players
(Mercado Livre, Magalu, TikTok Shop, Amazon) com margem controlada e sem
furar preço de custo. Toda a rotina está formalizada na skill
`/queimao` e no agente `queimao`.

## Por que agora

- Caixa precisa entrar: a mercadoria da loja tem de virar dinheiro.
- Janela já agendada no Seller Center: combo **FREE**
  (02/11/2026 07:00 → 30/11/2026 08:00) e desconto **Queimão Black**
  (02/11/2026 06:00 → 30/11/2026 07:00). O plano estende até 15/12/2026
  para absorver a segunda quinzena.

## Matriz de preço

| Categoria | Margem | Nota |
|---|---:|---|
| Balões (todos os SKUs) | **1 %** | Queima absoluta |
| Loja física — itens prioritários (bucha, palha de aço, malas de bordo PP ABS, garrafa de azeite, canetinha 30/40, bolsa pet) | **4 %** | Prioridade total |
| Loja física — demais itens com estoque > 0 no Argos | **4 %** | Mesma regra |
| Itens sem estoque na loja (dropship / fornecedor contínuo) | **18 %** | Margem de operação normal |

Preço = `custo × (1 + margem) + taxa variável da plataforma + subsídio de frete`.
Piso = `custo + taxa fixa da plataforma`. Se o preço calculado ficar abaixo
do piso, o item sai do lote.

## Entradas obrigatórias

1. **Argos** com estoque atualizado — fonte da verdade dos SKUs e dos custos.
2. **Planilha de fotos**: `%USERPROFILE%\Khaos\queimao\fotos.xlsx`
   (SKU → arquivo da capa).
3. **Relatório do `/espião`** com ≤ 24 h de idade.
4. **Credenciais Shopee** e dos players já logadas na máquina de operação.

## Vigias do plano

- `vigia-queimao-estoque` (a cada 2 h): tira SKU do ar quando o Argos zera.
- `vigia-queimao-margem` (diário, 06:00): confere se o preço continua dentro
  da matriz.
- `vigia-queimao-prazo` (diário, 07:00): se um SKU não vende em 72 h,
  propõe baixar 1 ponto de margem; precisa aprovação.
- `vigia-queimao-balao` (a cada 1 h): mantém balões a 1 %; religa se alguém
  mexer.

## Como rodar

```powershell
# Só diagnosticar e gerar o CSV, sem publicar
claude /queimao

# Aplicar o lote em todas as contas
claude /queimao publicar

# Conferir o que está publicado contra o CSV
claude /queimao conferir
```

Em sessão de nuvem (sem Argos nem Shopee na mão), o `/queimao` só prepara o
CSV com o que der para montar e devolve o pedido para rodar `publicar` numa
máquina da operação.

## Diretoria

- **Hudson**: aprova o comercial (lista final, prioridades, prazo).
- **Karina**: aprova a margem (confere piso, taxas e saldo esperado).
- **Bruna**: garante acesso (Argos, Shopee, players, vigias).

## Depois de 15/12/2026

O agente desativa a janela "Queimão Black", devolve o preço cheio e deixa
os vigias do plano em modo passivo (só leitura) por mais 7 dias para
conferir a cauda. Depois disso são removidos até o próximo Queimão.
