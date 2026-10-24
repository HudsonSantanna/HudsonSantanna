# 22. Convites a afiliados do TikTok Shop sem amostra — plano de guerra

Objetivo: pôr o **máximo possível de criadores** vendendo os produtos da
**LITERACAMP LTDA** no TikTok Shop, **sem amostra grátis**, com o mínimo de
trabalho manual e sem arriscar a conta.

Este documento é o plano e a **especificação** do agente de convites. O agente
é construído pelo Claude Code da **`HUDSONINTEGRAR`**, a máquina onde já roda o
`ARGOS - Vigia TikTok coletor` com o perfil do Chrome logado no Seller Center.
O código fica na máquina, como o dos outros vigias (doc 20). Quem roda é o
`/convites-tiktok`.

## Ponto de partida (tela de 24/10)

*Afiliados › Programa de afiliados*, conta LITERACAMP LTDA:

| Item | Valor |
|---|---:|
| Solicitações de amostra | 0 |
| Mensagens de criadores | 0 |
| **Amostras não habilitadas** | **338** |
| Produtos recomendados | 0 |

Os 338 produtos estão sem amostra. Para este plano isso não é problema: o
convite vai **sem amostra**. O que compensa a falta de amostra é **comissão**
e **volume de convites**.

## As três frentes

Sem amostra, nenhum convite sozinho chega ao "máximo possível". O alcance vem
de três frentes juntas, cada uma com um dono:

| # | Frente | Alcance | Quem faz |
|---|---|---|---|
| 1 | **Colaboração aberta** com todos os produtos elegíveis | **Todos** os afiliados do TikTok Shop podem achar e promover, sem convite | **Pessoa**, uma vez: é a comissão da loja |
| 2 | **Colaboração direcionada** (convites), sem amostra | Criadores escolhidos, até o limite diário que o TikTok mostrar | **Agente**, todo dia |
| 3 | **Acompanhamento**: aceites, recusas, mensagens de criadores | Converte convite em vídeo | Agente **lê e avisa**; pessoa responde |

A frente 1 é o maior alcance e não depende de agente. Sem ela, o agente gasta
o limite diário de convites em criadores que poderiam ter achado o produto
sozinhos.

## Frente 1 — Colaboração aberta (pessoa, uma vez)

1. *Afiliados › Colaboração aberta* → incluir **todos** os produtos com
   estoque e margem que aguentem comissão.
2. Definir a **comissão da colaboração aberta**. Decisão de dinheiro: é do
   Hudson, nunca do agente.
3. Não ligar amostra.

## Frente 2 — Agente de convites (colaboração direcionada)

### O que o agente faz — e só isso

Uma rodada por dia, num horário fora das rodadas do coletor (ver *Perfil do
Chrome*):

1. **Confere a conta antes de tudo.** Abre *Integridade da conta*. Qualquer
   violação, advertência ou restrição nova → **não convida**, avisa e sai.
2. **Lê o limite do dia.** Usa o limite de convites que o próprio Seller Center
   mostrar; não usa número fixo. Sem limite visível → usa o teto do
   `config.json` (`teto_convites_dia`).
3. **Busca criadores** em *Colaboração direcionada › Encontrar criadores* com
   os filtros do `config.json` (categoria, seguidores, país BR, vendas/GMV
   quando o filtro existir).
4. **Tira os repetidos.** Pula quem está no `convidados.csv` dos últimos
   `dias_sem_reconvidar` dias, quem já é afiliado ativo e quem recusou.
5. **Cria o convite** com:
   - os produtos do lote do dia (`produtos` no config; vazio = os da
     colaboração aberta);
   - a **comissão direcionada** do config;
   - **amostra grátis: desligada**, sempre;
   - a mensagem do config (modelo abaixo);
   - validade do convite do config.
6. **Envia em lotes**, num ritmo de pessoa (pausa aleatória entre ações), até
   o limite do dia ou o teto do config, o que vier primeiro.
7. **Registra** cada criador convidado no `convidados.csv` (id, nome,
   seguidores, data, produtos, comissão) e a rodada no log.
8. **Lê o retorno** (frente 3): aceites, recusas, convites vencidos e
   mensagens de criadores, e põe no resumo do dia.

### O que o agente NUNCA faz

- **Nunca liga amostra**, nunca aprova solicitação de amostra, nunca promete
  amostra ou produto grátis na mensagem.
- **Não muda comissão** da colaboração aberta nem de convite já enviado.
- Não altera produto, preço, estoque, anúncio ou configuração da loja.
- Não responde mensagem de criador: só **avisa** que chegou.
- **Não insiste.** Diante de captcha, "limite atingido", "atividade incomum",
  pedido de verificação ou qualquer aviso da plataforma, **para a rodada**,
  registra no log e avisa. Não tenta de novo no mesmo dia.
- Não digita nem guarda senha. Sessão caída vira aviso "faça login no perfil
  do coletor TikTok à mão e feche a janela depois".
- Não roda sem `comissao_direcionada` preenchida no config: sem esse número,
  sai com erro dizendo o que falta.

### Perfil do Chrome

O agente usa o **mesmo perfil já logado** do coletor TikTok, mas um perfil do
Chrome só abre em **um processo por vez**. Se os dois rodarem juntos, um deles
falha com `Target page, context or browser has been closed`. É o mesmo erro
do Vigia UpSeller em 24/10, quando havia outro Chrome aberto (doc 20,
pendência 2). Por isso:

- **Preferido:** os convites são uma **etapa do próprio coletor**, uma vez por
  dia, depois da coleta, na mesma rodada e no mesmo processo.
- **Se for tarefa separada** (`ARGOS - Convites TikTok`): horário que não
  coincide com o coletor, trava por arquivo (`C:\Argos\vigia-tiktok\perfil.lock`)
  respeitada pelos dois, `MultipleInstances IgnoreNew` e `ExecutionTimeLimit`
  menor que o intervalo, nunca o padrão de 72 h.
- **Nunca** deixar uma janela do Chrome aberta à mão nesse perfil.

### Configuração local

`C:\Argos\vigia-tiktok\config.json`, **fora do Git**:

```json
{
  "comissao_direcionada": null,
  "teto_convites_dia": 100,
  "dias_sem_reconvidar": 30,
  "validade_convite_dias": 30,
  "filtros": {
    "categorias": [],
    "seguidores_min": 1000,
    "seguidores_max": null,
    "pais": "BR"
  },
  "produtos": [],
  "mensagem": "Oi, {nome}! Somos a Literacamp e achamos que nossos produtos combinam com o seu público. Convidamos você para uma parceria com comissão de {comissao}% em todas as vendas pelo seu link. Os produtos já estão no catálogo de afiliados: é só aceitar e começar a divulgar. Qualquer dúvida, fale com a gente por aqui."
}
```

- `comissao_direcionada` começa **vazio de propósito**: é a decisão do
  Hudson. Para convite sem amostra converter, ela costuma precisar ficar
  **acima** da comissão da colaboração aberta.
- `teto_convites_dia` é um freio nosso, **abaixo** do limite da plataforma
  na primeira semana. Sobe por etapas (ver *Cronograma*).
- `categorias` vazio → o agente para e pede, em vez de convidar qualquer
  categoria.

### Modos

| Modo | O que faz |
|---|---|
| `--simular` (padrão) | Lê a integridade da conta, o limite do dia e a busca, e **mostra** os criadores que convidaria, os produtos, a comissão e a mensagem. Não envia nada |
| `--enviar` | Faz a rodada de verdade |
| `--retorno` | Só lê aceites, recusas e mensagens. Não convida |

### Arquivos

| Arquivo | O que tem |
|---|---|
| `C:\Argos\vigia-tiktok\config.json` | configuração acima |
| `C:\Argos\vigia-tiktok\convidados.csv` | um criador por linha, para não reconvidar |
| `%LOCALAPPDATA%\Argos\convites-tiktok.log` | uma linha por rodada: modo, limite lido, convidados, pulados, motivo de parada |

## Cronograma

| Quando | O quê | Quem |
|---|---|---|
| **Dia 0** | Frente 1 (colaboração aberta) e definir `comissao_direcionada` e `categorias` | Hudson |
| Dia 0 | Construir o agente, rodar `--simular` e conferir a lista com a tela | Claude da máquina |
| **Dias 1–3** | `--enviar` com `teto_convites_dia` em **30** | agente |
| Dias 4–7 | Teto em **60**, se a *Integridade da conta* seguir limpa e houver aceite | agente, revisado no resumo |
| **Semana 2+** | Teto = **limite da plataforma** | agente |
| Toda semana | Ler *Análise da colaboração*: taxa de aceite, vídeos publicados, vendas por afiliado. Aceite baixo → subir comissão ou trocar categoria, nunca aumentar o volume | Hudson |

Subir o teto aos poucos protege a conta. Muitos convites iguais num dia só,
logo de cara, é o tipo de padrão que a plataforma pode tratar como spam.

## Resumo do dia

Mesma regra do vigia do UpSeller (doc 19): uma linha no log por rodada e um
resumo no cérebro. Formato (números de exemplo):

```
Convites TikTok DD/MM: 58 enviados (limite do dia 60), 212 pulados (ja convidados),
aceites 7, recusas 3, vencidos 0, mensagens de criadores 2 (responder).
Integridade da conta: limpa.
```

Avisa a pessoa **só** quando há algo para ela: mensagem de criador,
integridade da conta com aviso, sessão caída, rodada parada por captcha ou
limite.

## Testes de aceitação

- [ ] Sem `comissao_direcionada` no config, o agente sai com erro e não abre
      o Chrome.
- [ ] Em `--simular`, a lista bate com a busca feita à mão com os mesmos
      filtros, e nada é enviado.
- [ ] Todo convite enviado tem **amostra desligada**. Conferir 3 na tela.
- [ ] Um criador convidado não recebe outro convite em 30 dias.
- [ ] Com a *Integridade da conta* mostrando aviso, a rodada não convida.
- [ ] Em captcha ou "limite atingido", a rodada para, registra e não insiste.
- [ ] Coletor e convites nunca abrem o perfil ao mesmo tempo (log dos dois
      sem `Target page, context or browser has been closed`).
- [ ] O `/vigias-loja` enxerga a tarefa dos convites, se ela for separada.
