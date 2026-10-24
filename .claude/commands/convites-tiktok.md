---
description: Convida afiliados do TikTok Shop sem amostra pelo perfil do coletor TikTok (simula por padrão; "enviar" envia; "retorno" só lê)
argument-hint: "[enviar|retorno]"
---

Faça a rodada de convites a afiliados do TikTok Shop da **LITERACAMP LTDA**,
**sem amostra grátis**, seguindo o `docs/22-convites-afiliados-tiktok.md`.

Argumento recebido: `$ARGUMENTS`

## 0. Onde rodar

Só na `HUDSONINTEGRAR`, onde está o perfil do Chrome logado do coletor
TikTok. Em outra máquina, pare e diga onde rodar.

## 1. Conferir antes de tudo

1. Leia o `docs/22-convites-afiliados-tiktok.md` inteiro.
2. Abra `C:\Argos\vigia-tiktok\config.json`. Se não existir, crie com o
   modelo do doc 22 e **pare**. Se `comissao_direcionada` estiver vazio, ou
   `filtros.categorias` vazio, **pare** e pergunte esses valores ao Hudson.
   Nunca escolha comissão por conta própria.
3. Confira se o coletor TikTok está rodando agora (processo com o perfil
   dele). Se estiver, espere ele terminar: o perfil só abre num processo por
   vez.
4. Confira se há janela do Chrome aberta **à mão** nesse perfil. Se houver,
   peça para a pessoa fechar. Você não fecha.

## 2. Agente

- Se o agente de convites ainda não existe, construa conforme a seção
  *Frente 2* do doc 22, como etapa do coletor TikTok (preferido) ou como
  tarefa separada com trava de perfil. Faça em Playwright, no mesmo jeito do
  coletor. Leia a tela de verdade antes de escrever seletor; prefira texto
  visível a classe CSS.
- Depois de construir, rode **só** `--simular` nesta primeira vez, mesmo que
  o argumento seja `enviar`, e mostre a lista para a pessoa conferir.

## 3. Rodar

- Argumento vazio → `--simular`: mostre quantos convidaria, os primeiros 20
  criadores (nome, seguidores, categoria), os produtos, a comissão, a
  mensagem e o limite do dia lido na tela.
- `enviar` → `--enviar`, respeitando `teto_convites_dia` e o limite da
  plataforma.
- `retorno` → `--retorno`: aceites, recusas, vencidos, mensagens de
  criadores.
- Qualquer outro argumento → não rode nada; diga que os usos são
  `/convites-tiktok`, `/convites-tiktok enviar` e `/convites-tiktok retorno`.

## 4. Entregar

Em português, curto:

1. **Veredito** em uma linha (quantos enviados / quantos simulados, e por que
   parou).
2. *Integridade da conta*: limpa ou o aviso que apareceu.
3. Enviados, pulados (já convidados, afiliado ativo, recusou), limite do dia.
4. Retorno: aceites, recusas, mensagens de criadores **para responder**.
5. Próximo passo do cronograma do doc 22 (subir o teto ou não, e por quê).

## Regras

- **Amostra grátis sempre desligada.** Não aprove solicitação de amostra.
- Não mude comissão, produto, preço, estoque ou configuração da loja.
- Não responda criador: só avise.
- Captcha, "limite atingido", "atividade incomum" ou pedido de verificação →
  pare a rodada, registre e avise. Não tente de novo no mesmo dia.
- Nunca digite, peça ou guarde senha. Sessão caída: peça login à mão no
  perfil do coletor e que fechem a janela depois.
- Não invente número: tudo no relatório sai da tela ou do log.
