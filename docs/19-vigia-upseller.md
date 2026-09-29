# 19. Vigia do UpSeller — especificação (nível 1: vigiar e imprimir)

Este documento é a **especificação** de um agente que ainda não existe. Ele foi
escrito para o Claude Code do **KHAOSOMNI**, que tem o cérebro e acesso à
máquina das impressoras, e que vai construir e ativar o agente lá.

## O que o agente faz — e só isso

A cada **30 minutos**, entre **07:00 e 20:00** (ajustável):

1. Abre o UpSeller (`https://app.upseller.com/pt/`) num **perfil do Chrome
   só dele**, já logado. Ele **nunca** digita nem guarda a senha.
2. **Lê** as contagens e os pedidos de *Processando Pedidos*:

   | Aba | URL | O que ler |
   |---|---|---|
   | Para Emitir | `/pt/order/pending-invoice` | sub-abas *Para Emitir*, *Emitindo*, **Falha na Emissão** (com o texto do erro), *Falha ao subir* |
   | Para Enviar | `/pt/order/to-ship` | *Para Programar* e o prazo "Expira em" |
   | Para Imprimir | (menu *Para Imprimir*) | pedidos com etiqueta/DANFE prontos |

3. **Imprime** o que está em *Para Imprimir*: baixa o PDF da etiqueta/DANFE para
   `C:\Argos\NotasFiscais\Entrada`. O `argos-notas-fiscais.ps1` (doc 18) manda
   para a BIXOLON **Etiqueta Fiscal**. O vigia não fala com a impressora.
4. **Avisa por WhatsApp** só quando há algo para uma pessoa fazer:
   - pedido em **Falha na Emissão**, com o erro, em uma linha;
   - pedido perto de expirar (menos de 6 h em "Expira em");
   - pedido em *Para Programar* (programar envio é com a pessoa);
   - sessão do UpSeller expirada ("faça login no perfil do vigia").

   A mesma falha não se repete a cada 30 min: um aviso por pedido e por erro,
   e um lembrete se continuar parado 3 h depois.

5. Registra cada rodada em `%LOCALAPPDATA%\Argos\vigia-upseller.log` e grava um
   resumo do dia no cérebro, como manda a REGRA-MEMORIA-CLAUDE.

## O que o agente NUNCA faz no nível 1

- **Não emite** nota fiscal (não clica em *Emitir Nota Fiscal*).
- **Não programa** envio.
- **Não altera** Classe de Impostos, Empresas, cadastro de produto nem nenhuma
  configuração. Erro fiscal vira **aviso** com a proposta de correção tirada do
  cérebro, e quem corrige é uma pessoa.
- Não cancela, não oculta e não edita pedido.

O **nível 2** (emitir os pedidos sem erro) só entra depois de uma semana de
resumos conferidos, e numa mudança separada.

## Contexto fiscal visto em 29/09

Em *Configurações › Notas Fiscais › Brasil NF-e › Classe de Impostos*, três
empresas, todas **MG, Simples Nacional**, cada uma com **uma** classe
predefinida "Simples Nacional ou MEI":

| Empresa | Classe |
|---|---|
| LITERACAMP LTDA | 355659 |
| KHAOS OMNI LTDA | 332940 |
| INTEGRAR SVE LTDA | 891894 |

O pedido `#UP6TME015808` (Mercado Livre / Literacamp, destino Sorocaba-SP,
comprador PJ) falhou duas vezes com: *"Classe de Imposto [355659]: está faltando
o cenário Saída – Fora do estado – ICMS, Tipo de Comprador: Pessoa Jurídica"*.
**Reemitir não resolve.** Falta cadastrar esse cenário na classe, com a regra do
cérebro, validada por quem responde pela parte fiscal. Venda interestadual para
PJ é justamente o caso em que as outras duas classes podem ter a mesma lacuna.

## Como construir (orientação para o Claude do KHAOSOMNI)

- **Playwright** (Python ou Node, o que a máquina já tiver) com
  `launch_persistent_context` num diretório próprio, por exemplo
  `C:\Argos\vigia-upseller\perfil-chrome`. O primeiro login é feito **à mão**
  pela Karina nesse perfil.
- **Leia a tela de verdade antes de escrever seletor.** Prefira texto visível
  ("Falha na Emissão", "Para Programar") a classes CSS, que mudam.
- Tarefa agendada `ARGOS - Vigia UpSeller`, **Interactive** (usuário logado), a
  cada 30 min, `MultipleInstances IgnoreNew`. Entra também na lista
  `scripts/windows/rotinas-essenciais.txt` do `/verificar-agentes`.
- **WhatsApp:** reaproveite o que o cérebro já usa para mandar mensagem. Se não
  houver nada pronto, **pare e pergunte**: não crie conta, API ou serviço novo
  sem aprovação. O número de destino fica num arquivo de configuração local
  (`C:\Argos\vigia-upseller\config.json`), **nunca** no Git.
- Um modo `-Simular` / `--simular` que lê tudo e só **mostra** o aviso que
  mandaria, sem baixar nem enviar nada. Primeira semana: rodar em simulação
  uma vez e conferir com a tela.

## Testes de aceitação

- [ ] Em simulação, o resumo bate com as contagens da tela (*Para Emitir*,
      *Falha na Emissão*, *Para Enviar*, *Para Imprimir*).
- [ ] O erro do `#UP6TME015808` chega no WhatsApp uma vez, com a proposta de
      correção, e não se repete a cada 30 min.
- [ ] Um pedido em *Para Imprimir* sai na **Etiqueta Fiscal** sem ninguém tocar.
- [ ] Com o UpSeller deslogado, chega "sessão expirada", e o vigia não tenta
      digitar senha.
- [ ] Depois de reiniciar a máquina, a tarefa roda sozinha no próximo ciclo.
- [ ] Nenhum pedido teve nota emitida, envio programado ou configuração
      alterada pelo vigia.
