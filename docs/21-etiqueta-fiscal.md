# 21. Etiqueta Fiscal parada (`/etiqueta-fiscal`)

## O aviso de 22/10, 17:34

O guardião da **`HUDSONINTEGRAR`** abriu:

> [ARGOS] IMPRESSORA DE ETIQUETA: 1 problema(s)
> NOVO - O guardião não conseguiu ler as impressoras do Windows: o PowerShell
> não respondeu em 60 s (leitura do spooler/USB travada).
> O que fazer: ver se o serviço 'Spooler de Impressão' está rodando na loja.

O guardião lê as impressoras com `Get-Printer`, que passa pelo **WMI** e pelo
**spooler**. Se qualquer um dos dois trava, ele só consegue dizer "não
respondeu". São causas diferentes, com consertos diferentes:

| Causa | A etiqueta imprime? | Conserto |
|---|---|---|
| **Spooler travado** | Não. E o agente de notas fica parado esperando | Reiniciar o spooler |
| **Fila em porta morta** (doc 15) | Não, e **sem erro nenhum**: a fila aceita e some | Religar a fila na porta viva |
| **Fila pausada, offline ou em erro** | Não | Retomar; papel, ribbon, tampa, cabo |
| **Trabalho parado** na fila | Não: ele segura os seguintes | A pessoa decide pela fila |
| **Agente de notas parado** | Não: os PDFs ficam na `Entrada` | Disparar a tarefa |
| **Só o WMI travado** | **Pode estar normal**: só o guardião não lê | Reiniciar a máquina fora da expedição |

## Como rodar

No Claude Code aberto na HUDSONINTEGRAR, dentro deste repositório:

| Comando | O que faz |
|---|---|
| `/etiqueta-fiscal` | Só diagnostica e mostra o plano. Não muda nada. |
| `/etiqueta-fiscal reparar` | Diagnostica e aplica o plano. |

Direto no PowerShell, **como administrador**:

```powershell
cd <repositório>\scripts\windows
powershell -ExecutionPolicy Bypass -File .\etiqueta-fiscal.ps1            # diagnóstico
powershell -ExecutionPolicy Bypass -File .\etiqueta-fiscal.ps1 -Reparar   # diagnóstico + reparo
```

O relatório sai na tela e numa cópia na Área de Trabalho
(`etiqueta-fiscal-AAAAMMDD-HHMM.txt`). Saída `0` = imprimindo, `1` = problema.

## Sem o script, na hora

Se a expedição está parada e não dá para esperar:

1. Olhe a impressora: ligada, luz sem erro, papel e ribbon, cabo USB no
   computador.
2. PowerShell **como administrador**:
   ```powershell
   Restart-Service Spooler -Force
   ```
   Se ficar parado mais de 30 s: `taskkill /IM spoolsv.exe /F` e depois
   `Start-Service Spooler`.
3. Imprima de novo a última etiqueta. Se a fila aceitar e **nada sair**, é
   porta morta: rode o script.

## O que o diagnóstico olha

Cada teste roda num `powershell.exe` separado, com limite de tempo. Se travar,
o processo é encerrado e o relatório diz `[TRAVADO]`, em vez de o script
travar junto.

| Seção | O que mostra |
|---|---|
| O Windows está respondendo? | Serviço Spooler; filas pelo **winspool** (sem WMI); o mesmo `Get-Printer` do guardião; WMI; portas USB com impressora ligada (`pnputil`, sem WMI). A comparação diz se é o spooler ou o WMI |
| Fila `Etiqueta Fiscal` | porta, driver, pausada/offline/em erro, e cada trabalho com a idade (parado = mais de 15 min ou em erro) |
| Impressoras USB ligadas | cada porta viva e a fila que aponta para ela; se a fiscal está numa porta **morta** |
| Agente de notas fiscais | tarefa `ARGOS - Notas Fiscais`, arquivos esperando na `Entrada`, arquivos em `Erro` nas últimas 24 h, SumatraPDF preso, fim do log |
| Eventos | quedas do spooler (7031/7034) e erros do serviço de impressão nas últimas 24 h |

## O que o `-Reparar` faz, e o que não faz

Só age no que o diagnóstico apontou, nesta ordem:

1. **Spooler** sem resposta → para e sobe de novo. **Não apaga** trabalho da
   fila: ao voltar, o spooler imprime o que estava esperando.
2. **SumatraPDF preso** (impressão sem janela há mais de 10 min) que continuar
   preso depois do spooler → fecha. O arquivo vai para `Erro\`: confira no
   papel e, se não saiu, mova de volta para a `Entrada`.
3. **Fila pausada** → retoma.
4. **Porta morta** → religa a fiscal na porta viva **só sem dúvida**: ela é a
   única fila em porta morta e há uma única porta viva sem fila (ou só com a
   fila duplicada que o Windows cria sozinho). Com qualquer dúvida, para e
   pede o `7-nomear-impressoras.ps1 -Identificar`, que imprime um papel por
   fila. Errar aqui é mandar nota fiscal para a impressora de código de barra.
5. **Agente parado** → dispara a tarefa e confere que ficou rodando.
6. Lê tudo de volta e espera a `Entrada` andar.

Nunca: apaga trabalho de impressão, remove ou renomeia fila (nem a duplicada:
ele mostra o `Remove-Printer` pronto), muda a impressora padrão, reinicia a
máquina ou o WMI, abre o UpSeller.

## O agente de notas também mudou

O `argos-notas-fiscais.ps1` tinha dois pontos que paravam a impressão sem
avisar:

- **Esperava o SumatraPDF sem prazo.** Com o spooler travado, o SumatraPDF
  nunca termina, o agente ficava parado nele e nenhuma etiqueta saía mais,
  sem erro no log. Agora o prazo é de 120 s (`-PrazoImpressao`). Estourou, o
  agente encerra o SumatraPDF, registra o motivo e manda o arquivo para
  `Erro\`.
- **Lia a fila pelo `Get-Printer` ao subir.** Com o WMI travado, o agente
  nunca chegava a começar. Agora lê a fila direto do spooler.

O agente que já está rodando continua com o código antigo até reiniciar: no
fim do reparo, pare e dispare de novo a tarefa `ARGOS - Notas Fiscais`, ou
reinicie a máquina fora da expedição.

## Ainda falta (fora deste repositório)

- **Guardião sem WMI** (pendência do doc 20): o guardião deveria ler as
  impressoras pelo winspool, como este script, para avisar *qual* travou:
  spooler ou WMI.
- **SMTP**: o aviso só aparece na tela da loja até `SMTP_HOST/USER/PASS`
  estarem no cofre do Argos.
- **Fita crepe** (doc 15): `FISCAL` e `BARRA` nas impressoras e nas portas
  USB. É o que impede a porta de trocar de lugar.
