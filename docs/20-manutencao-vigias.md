# 20. Manutenção dos vigias da loja (`/vigias-loja`)

Na **`HUDSONINTEGRAR`** rodam três vigias do Argos, cada um numa tarefa do
Agendador, e um guardião que confere se eles estão em dia:

| Vigia | Tarefa | Log |
|---|---|---|
| Vigia UpSeller (doc 19) | `ARGOS - Vigia UpSeller`, a cada 30 min | `%LOCALAPPDATA%\Argos\vigia-upseller.log` |
| Agente de ações | `ARGOS - Acoes UpSeller`, a cada 30 min | `%LOCALAPPDATA%\Argos\vigia-acoes.log` |
| Coletor TikTok | `ARGOS - Vigia TikTok coletor` | `%LOCALAPPDATA%\Argos\` |

O código dos vigias e do guardião está **na máquina**, não neste repositório.
O que fica aqui é o `scripts/windows/vigias-loja.ps1`, que diagnostica e
destrava os vigias **por fora**, sem depender do código deles.

## O caso de 15/10

O guardião abriu este aviso:

- os três vigias **ATRASADOS desde 15/10 às 08:54**: 552, 462 e 488 minutos
  sem rodada nova (limites de 35, 40 e 75 min);
- **"VOLTOU:** não consegui ler o Agendador: não respondeu em 90 s";
- **"VOLTOU:** o PowerShell não respondeu em 60 s lendo as impressoras
  (spooler/USB travada)";
- e-mail da máquina: SMTP não configurado no cofre (faltam `SMTP_HOST`,
  `SMTP_USER`, `SMTP_PASS`).

Três vigias parados **no mesmo minuto** não são três defeitos: é uma causa só.
As suspeitas, da mais provável para a menos:

1. **Rodada presa + IgnoreNew.** As tarefas são "se já estiver rodando, não
   inicie outra". Se uma rodada trava (Chrome esperando o spooler, perfil do
   Chrome preso), o Agendador **pula todas as seguintes sem registrar erro**
   até o limite de tempo da tarefa, que no padrão do Windows é de **72 horas**.
2. **Spooler travado.** Tudo que pergunta pelas impressoras fica esperando,
   inclusive o Chrome do vigia e a etiqueta fiscal.
3. **WMI travado.** `Get-ScheduledTask` e `Get-Printer` passam **os dois** pelo
   WMI. Se ele trava, o guardião acusa "Agendador" e "impressoras" juntos,
   exatamente o par de avisos de 15/10.

## Como rodar

No Claude Code aberto na HUDSONINTEGRAR, dentro deste repositório:

| Comando | O que faz |
|---|---|
| `/vigias-loja` | Só diagnostica e mostra o plano. Não muda nada. |
| `/vigias-loja reparar` | Diagnostica e aplica o plano. |

Direto no PowerShell (como **administrador**, se o spooler precisar ser
reiniciado):

```powershell
cd <repositório>\scripts\windows
powershell -ExecutionPolicy Bypass -File .\vigias-loja.ps1            # diagnóstico
powershell -ExecutionPolicy Bypass -File .\vigias-loja.ps1 -Reparar   # diagnóstico + reparo
```

O relatório sai na tela e numa cópia na Área de Trabalho
(`vigias-loja-AAAAMMDD-HHMM.txt`). Saída `0` = tudo certo, `1` = problema.

## O que o diagnóstico olha

Cada teste roda num `powershell.exe` separado, com limite de tempo. Se travar,
o processo é encerrado e o relatório diz `[TRAVADO]`, em vez de o script
travar junto.

| Seção | O que mostra |
|---|---|
| O Windows está respondendo? | WMI, Agendador pelo WMI **e** pelo COM, serviço Spooler, impressoras pelo winspool **e** pelo WMI. A comparação diz qual das três suspeitas é |
| Vigias | estado, última e próxima vez, resultado, intervalo, **limite de tempo**, o que faz se já estiver rodando, e a rodada em andamento com a idade dela |
| Processos | node/python/powershell/Chrome dos vigias; separa **Chrome de automação** de **Chrome aberto à mão** no perfil do vigia |
| Logs | últimas linhas de cada log de vigia e há quantos minutos ele não anda |
| Eventos | desligamento, sono, serviço caído (7031/7034: é aí que aparece o spooler derrubado por driver) e, se o histórico do Agendador estiver ligado, o evento **322**: "rodada ignorada porque a anterior ainda rodava", a prova direta da suspeita 1 |
| E-mail | se `SMTP_HOST/USER/PASS` existem (só o nome, nunca o valor) |

## O que o `-Reparar` faz, e o que não faz

Só age no que o diagnóstico apontou, nesta ordem:

1. Salva o XML de cada vigia em `C:\Argos-Backups\_checkpoints\<carimbo>_vigias\`.
2. **Spooler** sem resposta → para e sobe de novo (precisa de administrador).
   **Não apaga** trabalho de impressão: pode ser etiqueta de verdade.
3. **Rodada presa** (rodando há mais de 2× o intervalo) → encerra o processo
   e os filhos dele (o Chrome do vigia é filho) e limpa o estado no Agendador.
4. **Chrome de automação órfão** no perfil do vigia → fecha.
5. **Limite de tempo** maior que o intervalo → põe intervalo − 5 min (25 min
   nos vigias de 30). Liga "rodar assim que possível se perder o horário" e
   religa vigia desligado. Tarefa que guarda senha não é regravada: o
   relatório diz onde ajustar à mão.
6. Dispara uma rodada de cada vigia que estava parado e **lê de volta**: só
   diz `[OK]` se o Agendador mostrar a rodada nova.

Nunca: fecha janela do Chrome aberta **à mão**, reinicia a máquina, reinicia o
WMI, cria ou apaga tarefa, abre UpSeller ou TikTok, mexe em pedido, nota ou
configuração.

> **Por que o limite de tempo resolve de vez:** com 25 min de limite, uma
> rodada que trava é encerrada pelo próprio Windows antes da próxima, e o vigia
> perde **uma** rodada em vez de um dia inteiro.

## Pendências (atualizado em 15/10/2026, fim da tarde)

### Vigias, nesta máquina

| # | Pendência | Quem | Como |
|---|---|---|---|
| 1 | Vigias parados desde 08:54 | Claude da máquina | `/vigias-loja`, conferir o diagnóstico, `/vigias-loja reparar` |
| 2 | Janela do Chrome do **perfil do vigia** aberta depois do login | quem logou | Fechar a janela. O login fica salvo no perfil, e o vigia só consegue abrir o perfil com ela fechada |
| 3 | WMI sem resposta (se o diagnóstico confirmar) | pessoa | Reiniciar a máquina **fora** do horário de expedição e rodar `/vigias-loja` de novo |
| 4 | SMTP: os avisos só aparecem na tela desta máquina | Hudson | Decidir qual conta envia e gravar `SMTP_HOST/USER/PASS` no cofre do Argos. Nunca no Git |
| 5 | Histórico do Agendador desligado (se o relatório disser) | Claude da máquina | Agendador › *Habilitar histórico de todas as tarefas*: deixa o evento 322 visível no próximo diagnóstico |

### No código dos vigias (Claude da máquina)

O `vigias-loja.ps1` destrava por fora. Para não travar de novo, por dentro:

- **Prazo por rodada no próprio vigia**: timeout em cada `goto`/espera do
  Playwright e um prazo total (ex.: 20 min). Estourou → registra no log e sai
  com erro, em vez de ficar esperando.
- **Perfil em uso**: se o `launch_persistent_context` falhar porque o perfil
  está aberto, registrar no log "perfil do vigia aberto à mão: feche a janela"
  e sair. Não tentar de novo em loop.
- **Guardião sem WMI**: ler as tarefas pelo COM (`Schedule.Service`) em vez de
  `Get-ScheduledTask`, e as impressoras pelo winspool em vez de `Get-Printer`,
  cada leitura em processo separado com limite. Assim o guardião continua
  enxergando os vigias mesmo com o WMI travado, e o aviso diz qual dos dois
  travou.
- **Tarefas novas** já nascem com `-ExecutionTimeLimit` de intervalo − 5 min
  (nunca o padrão de 72 h).

### UpSeller: painel às 18h de 15/10

Lido da tela *Home* (conta da Karina). O vigia nível 1 só **avisa**: nada
daqui é feito por ele.

| Item | Qtd. | Quem resolve |
|---|---:|---|
| Pedidos › Para Reservar | 2 | expedição |
| Pedidos › **Para Emitir** | 1 | pessoa emite. Se cair em *Falha na Emissão*, conferir se é o caso do cenário interestadual PJ (doc 19, `#UP6TME015808`) |
| Pedidos › **Para Enviar** | 2 | pessoa programa o envio |
| Pedidos › Expirará em breve | 0 | — |
| Pedidos › Para Imprimir | 0 | — (Argos imprime quando aparecer) |
| Pedidos › Retirada / Falha na Retirada | 12 / 0 | acompanhar coleta |
| Estoque › **Sem Estoque** | 78 | compras/estoque: revisar anúncios ativos sem saldo |
| Estoque › Qtd. Mín. / MELI Full | 0 | — |
| SAC › **Reclamação pendente** | 2 | SAC |
| SAC › **Devolução** | 6 | SAC |
| SAC › Perguntas / Mensagens não lidas | 0 / 0 | — |
| Plano Avançado (12/10 a 11/11) | 5.978 de 6.000 pedidos restantes | — |

### Conta do UpSeller

- **Senha sem troca há 282 dias**: o próprio UpSeller pede a troca. Quando
  trocar, a sessão do perfil do vigia cai: o vigia avisa "sessão expirada", e
  alguém refaz o login **à mão** no perfil do vigia e **fecha a janela**
  depois (pendência 2). O vigia nunca recebe nem guarda a senha.
- **Telefone não verificado**: *Verifique Agora* na faixa amarela da Home.

### Do doc 19, ainda em aberto

- Pendência fiscal do `#UP6TME015808`: cadastrar o cenário *Saída – Fora do
  estado – ICMS, Pessoa Jurídica* na Classe de Impostos 355659 (e conferir
  332940 e 891894), validado por quem responde pela parte fiscal.
- Testes de aceitação do vigia (doc 19): conferir depois do reparo,
  principalmente "depois de reiniciar a máquina, a tarefa roda sozinha no
  próximo ciclo".
- O **agente de ações** (`ARGOS - Acoes UpSeller`) e o **coletor TikTok**
  não têm especificação neste repositório. Antes de qualquer nível 2 do
  vigia, documentar o que o agente de ações faz no UpSeller.
