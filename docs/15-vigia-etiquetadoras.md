# Vigia das etiquetadoras - especificacao do agente de rotina diaria

Este documento e a ESPECIFICACAO de um script que ainda nao existe:
`scripts/windows/10-vigia-etiquetadoras.ps1`. Ele foi escrito para ser lido por
quem (ou o que) vai implementar o script. Se voce esta procurando como usar o
vigia depois de pronto, va para a secao "Uso" no fim.

## Por que este agente existe

Em 14/09/2026, na HUDSONINTEGRAR, as duas BIXOLON XD3-40t pararam de imprimir
TRES vezes no mesmo dia. Nenhuma vez por defeito de impressora. Todas as tres
pela mesma causa:

**A fila do Windows continuou apontando para uma porta USB que nao existe mais.**

As duas BIXOLON nao tem numero de serie util:

- uma reporta `0000000000000001`
- a outra nao reporta nada (instance id com prefixo `5&`)

Sem numero de serie, o Windows so consegue distinguir uma da outra pela porta
USB. E porta USB troca de lugar: basta trocar o cabo de entrada, reiniciar a
maquina, ou desligar e ligar a impressora. Quando isso acontece, a fila fica
apontada para uma porta morta.

**Fila em porta morta e o pior tipo de falha que existe aqui:** ela ACEITA o
trabalho. O spooler nao acusa erro. O Argos Estoque diz que imprimiu. O
operador fica olhando para uma impressora muda sem nenhuma mensagem na tela.

Na sequencia do dia 14/09 aconteceu, nesta ordem:

1. as portas vivas mudaram de `USB001/USB002` para `USB002/USB005`, e a fila
   `Etiqueta Fiscal` ficou presa na `USB001` morta;
2. as duas impressoras fisicas estavam trocadas entre si, o que exigiu remapear
   tres filas de uma vez;
3. o operador desligou e ligou a fiscal na tomada, o Windows a enumerou como
   dispositivo NOVO na `USB006` e criou sozinho uma fila duplicada chamada
   `BIXOLON XD3-40t - BPL-Z`.

O estado que ficou funcionando no fim do dia:

| Fila | Porta |
|---|---|
| `Etiqueta Fiscal` | USB006 |
| `Codigo de Barra` | USB005 |
| `ARGOS - Codigo Estoque` | USB005 |

Esse estado nao e estavel. Ele so vale ate o proximo reboot ou a proxima queda
de energia. O vigia existe para descobrir o desalinhamento de manha, antes do
primeiro pedido do dia, em vez de descobrir com o cliente esperando.

## O que o vigia tem que fazer

### 1. Ler as portas que tem impressora LIGADA agora

Esta e a unica fonte de verdade. O instance id de cada dispositivo `USBPRINT`
termina no nome da porta:

    USBPRINT\BIXOLON_XD3-40T\6&36A51FC3&2&USB002
                                          ^^^^^^

A tecnica ja esta provada em `scripts/windows/6-configurar-etiquetadora.ps1`:

```powershell
$portasVivas = @()
if (Get-Command 'Get-PnpDevice' -ErrorAction SilentlyContinue) {
    $portasVivas = @(@(Get-PnpDevice -PresentOnly -ErrorAction SilentlyContinue |
        Where-Object { $_.InstanceId -like 'USBPRINT\*' } |
        ForEach-Object { if ($_.InstanceId -match '(USB\d+)$') { $Matches[1] } }) |
        Select-Object -Unique)
}
```

Se `Get-PnpDevice` nao existir, o vigia nao pode concluir nada sobre portas
mortas. Nesse caso ele diz isso em voz alta e NAO repara nada - nunca adivinha.

### 2. Cruzar cada fila BIXOLON com essa lista

**Esta e a verificacao que falta no `5-diagnostico-etiquetadora.ps1`.** O
script 5 lista as portas vivas e lista as portas das filas, mas nunca cruza as
duas - por isso ele passou por cima das tres quebras do dia 14/09 sem apontar
nenhuma delas. O vigia tem que cruzar.

Para cada fila cujo `Name` ou `DriverName` bata com `BIXOLON|BPL`:

- `PortName` esta na lista de portas vivas -> OK
- `PortName` e `LPT*`, `COM*` ou uma `USB00x` que nao esta viva -> **PORTA MORTA**

### 3. Apontar fila duplicada criada sozinha pelo Windows

Quando a impressora e re-enumerada numa porta nova, o Windows cria uma fila
nova com o nome do modelo. Sinais: nome batendo com
`BIXOLON XD3-40t`, `#\d`, `\(Copiar \d+\)`, `\(Copy \d+\)`.

Fila duplicada e perigosa por si so: ela aparece no Ctrl+P do Chrome com nome
parecido e o operador escolhe pelo palpite - e a etiqueta sai na impressora
errada. Isso ja aconteceu nesta maquina e foi o motivo do
`7-nomear-impressoras.ps1`.

### 4. Apontar job preso

`Get-PrintJob` por fila. Reportar:

- job em estado de erro (`JobStatus` batendo com `Error|Blocked|Offline|Paused`)
- job parado ha mais de N minutos (padrao 15) mesmo em estado `Normal` - foi
  exatamente assim que a fiscal ficou no dia 14/09: aceitava, enfileirava
  `Normal`, e nao escoava
- fila com `WorkOffline = True` ou `PrinterStatus` de erro

### 5. Escrever o relatorio

Mesmo padrao dos scripts 5 e 8: `.txt` na Area de Trabalho, com fallback para
`%TEMP%` quando a Area de Trabalho nao aceita escrita. A Area de Trabalho aqui
e redirecionada pelo OneDrive (`C:\Users\hudso\OneDrive\Area de Trabalho`),
entao usar SEMPRE `[Environment]::GetFolderPath('Desktop')`, nunca
`"$env:USERPROFILE\Desktop"`.

Como o vigia roda todo dia, o relatorio precisa de data no nome
(`vigia-etiquetadoras-AAAA-MM-DD.txt`) e de uma limpeza dos relatorios com mais
de 30 dias, senao a Area de Trabalho vira um deposito.

### 6. Sair com codigo de saida util

- `0` - tudo alinhado
- `1` - achou problema (o Agendador de Tarefas marca a execucao como falha, e
  isso aparece sozinho no historico)

## O que o vigia NAO pode fazer

Isto nao e preferencia de estilo, e o que separa um vigia util de um vigia que
manda etiqueta de nota fiscal para a impressora de codigo de barra:

1. **Por padrao ele NAO altera nada.** Sem `-Confirmar` ele so relata. Mesma
   convencao dos scripts 6 e 7.

2. **Ele nunca repara fila de identidade ambigua.** Com `-Confirmar`, so pode
   religar uma fila numa porta viva quando existe UMA unica porta viva orfa
   (viva e sem nenhuma fila apontada para ela) e UMA unica fila morta. Duas de
   cada lado significa que ele teria que adivinhar qual e a fiscal - e errar
   isso e mandar etiqueta fiscal para a impressora errada no meio do despacho.
   Com duas ou mais de cada lado ele PARA e manda o operador rodar
   `7-nomear-impressoras.ps1 -Identificar`, que resolve a duvida imprimindo um
   papel por fila.

3. **Ele nunca apaga job sozinho, nunca.** Job na fila e trabalho de alguem -
   pode ser a etiqueta de envio de um pedido ja faturado. Ele relata e para.

4. **Ele nunca remove fila sozinho**, nem a duplicada. Relata e mostra o
   comando `Remove-Printer` pronto para o operador copiar.

5. **Ele nunca renomeia nada.** Renomear e trabalho do script 7, que so age
   depois da prova em papel.

## Convencoes do repositorio

- PowerShell 5.1 (`#Requires -Version 5.1`); nada de `&&`, nada de
  `?:`, nada de operador ternario
- **Somente ASCII** no arquivo inteiro - sem acento, sem emoji. Console do
  Windows em code page 850 embaralha o resto
- Portugues nas mensagens, `[OK]` / `[ERRO]` / `[!]` como prefixo
- Cabecalho `<# ... #>` explicando o problema real que o script resolve, nao so
  a sintaxe
- Nomes de variavel em portugues, como nos scripts 5 a 8
- Atencao: nome de variavel em PowerShell NAO diferencia maiusculas. Ja houve
  um bug aqui onde `$origem` local apagou o parametro `$Origem`

## Instalacao como tarefa diaria

O vigia so serve se rodar sozinho. Pede uma tarefa no Agendador, e o proprio
script deve saber se instalar com um `-Instalar`:

```powershell
$acao    = New-ScheduledTaskAction -Execute 'powershell.exe' `
    -Argument "-NoProfile -ExecutionPolicy Bypass -File `"$PSCommandPath`""
$gatilho = New-ScheduledTaskTrigger -Daily -At '07:30'
Register-ScheduledTask -TaskName 'ARGOS - Vigia das etiquetadoras' `
    -Action $acao -Trigger $gatilho -User $usuario -RunLevel Highest
```

07:30 e antes do expediente: da tempo de consertar antes do primeiro pedido.

**Armadilha ja documentada, nao repetir:** numa sessao SSH o Windows reporta
`USERDOMAIN=WORKGROUP`, e `Register-ScheduledTask -User "$env:USERDOMAIN\$env:USERNAME"`
morre com `0x80070534` ("nenhum mapeamento entre nomes de conta e ids de
seguranca"). Usar a saida de `whoami` ou o SID da conta.

## A correcao definitiva nao e software

O vigia detecta o desalinhamento cedo. Ele nao impede o desalinhamento - nenhum
script impede, porque a causa e fisica: duas impressoras identicas, sem numero
de serie, em portas USB intercambiaveis.

A correcao definitiva custa dois pedacos de fita crepe:

1. escrever `FISCAL` e `BARRA` nas duas impressoras;
2. escrever a mesma coisa nas duas portas USB do gabinete, e sempre plugar cada
   uma na sua.

Com o cabo sempre na mesma porta, a porta para de trocar e o vigia passa o ano
inteiro dizendo `[OK]`.

## Uso (depois do script pronto)

```powershell
# so relata - nao altera nada
powershell -ExecutionPolicy Bypass -File .\10-vigia-etiquetadoras.ps1

# relata e repara o caso sem ambiguidade
powershell -ExecutionPolicy Bypass -File .\10-vigia-etiquetadoras.ps1 -Confirmar

# instala a tarefa diaria das 07:30 (como Administrador)
powershell -ExecutionPolicy Bypass -File .\10-vigia-etiquetadoras.ps1 -Instalar
```

## Como saber que ele funciona

Testar sem quebrar a producao: criar uma fila de mentira apontada para uma
porta morta e ver se o vigia a acusa.

```powershell
Add-Printer -Name 'TESTE VIGIA' -DriverName 'Generic / Text Only' -PortName 'LPT3:'
powershell -ExecutionPolicy Bypass -File .\10-vigia-etiquetadoras.ps1
Remove-Printer -Name 'TESTE VIGIA'
```

O vigia tem que acusar `TESTE VIGIA` em porta morta e, por ela nao ser BIXOLON,
NAO tentar reparar. Se ele reparar essa fila, a regra 2 esta frouxa.
