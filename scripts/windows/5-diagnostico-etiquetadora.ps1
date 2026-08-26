#Requires -Version 5.1
<#
    5-diagnostico-etiquetadora.ps1 - Radiografia da etiquetadora BIXOLON, do
    agente ArgosPrint e da pistola de codigo de barras.

    SOMENTE LEITURA. Nao instala, nao renomeia, nao compartilha, nao apaga fila,
    nao mexe em impressora nenhuma - inclusive a BIXOLON FISCAL do UpSeller.

    Segue a ordem oficial de diagnostico da nota do Cerebro
    "IMPRESSORA ETIQUETAS - Bixolon XD3-40t (ZPL) Argos Estoque":
        dispositivo USB -> spooler -> compartilhamento -> agente 9110 -> navegador
    A causa mais comum e a mais boba: o teste 1 responde em 2 segundos.

    Uso:
      powershell -ExecutionPolicy Bypass -File .\5-diagnostico-etiquetadora.ps1
#>
[CmdletBinding()]
param(
    [int]   $Porta = 9110,
    [string]$Saida = "$env:USERPROFILE\Desktop\diagnostico-etiquetadora-$(Get-Date -Format 'yyyyMMdd-HHmm').txt"
)

$ErrorActionPreference = 'SilentlyContinue'
$script:Linhas = New-Object System.Collections.ArrayList
$script:Faltas = New-Object System.Collections.ArrayList

function Escrever([string]$Texto = '') {
    Write-Host $Texto
    [void]$script:Linhas.Add($Texto)
}
function Titulo([string]$Texto) {
    Escrever ''
    Escrever ('=' * 72)
    Escrever "  $Texto"
    Escrever ('=' * 72)
}
function OK([string]$Texto)    { Escrever "  [OK]    $Texto" }
function Falta([string]$Texto) { Escrever "  [FALTA] $Texto"; [void]$script:Faltas.Add($Texto) }
function Aviso([string]$Texto) { Escrever "  [!]     $Texto" }

Escrever "ARGOS - diagnostico da etiquetadora  $(Get-Date -Format 'dd/MM/yyyy HH:mm')"
Escrever 'SOMENTE LEITURA - nada nesta maquina e alterado por este script.'

# ------------------------------------------------------------- 0. identidade
Titulo '0. ESTA MAQUINA'
$ativo   = (Get-ItemProperty 'HKLM:\SYSTEM\CurrentControlSet\Control\ComputerName\ActiveComputerName').ComputerName
$proximo = (Get-ItemProperty 'HKLM:\SYSTEM\CurrentControlSet\Control\ComputerName\ComputerName').ComputerName
Escrever "  Nome agora .......: $ativo"
Escrever "  Usuario ..........: $env:USERNAME"
$ips = Get-NetIPAddress -AddressFamily IPv4 |
        Where-Object { $_.IPAddress -notlike '127.*' -and $_.IPAddress -notlike '169.254.*' }
foreach ($ip in $ips) { Escrever "  IP ...............: $($ip.IPAddress)  ($($ip.InterfaceAlias))" }

if ($proximo -ne $ativo) {
    Aviso "RENOMEACAO PENDENTE: depois de reiniciar esta maquina passa a se chamar '$proximo'."
    Aviso "CONFIRA A GRAFIA antes de reiniciar. Se estiver errada, renomeie de novo ANTES do reboot."
    [void]$script:Faltas.Add("renomeacao pendente: $ativo -> $proximo (conferir grafia)")
}

# ------------------------------------------------- 1. o dispositivo USB existe?
# Teste 1 da nota: se a impressora nao existe pro Windows AGORA, o resto e
# perda de tempo. VID_1504 = BIXOLON. VID_0483&PID_0011 = pistola C3TECH LB-50BK.
Titulo '1. DISPOSITIVO USB  (o teste que responde em 2 segundos)'
$usb = Get-PnpDevice -PresentOnly |
        Where-Object { $_.InstanceId -like 'USBPRINT\*' -or $_.InstanceId -match 'VID_1504' }
if ($usb) {
    foreach ($d in $usb) { Escrever ("  {0,-8} {1}" -f $d.Status, $d.InstanceId) }
    $bixolon = @($usb | Where-Object { $_.InstanceId -match 'VID_1504' -or $_.InstanceId -match 'BIXOLON' })
    if ($bixolon.Count -gt 0) { OK "BIXOLON presente ($($bixolon.Count) dispositivo(s))" }
    else { Falta 'nenhum dispositivo com VID_1504 (BIXOLON) - ver se a XD3-40t esta ligada e no cabo' }
} else {
    Falta 'NENHUM dispositivo USBPRINT presente - impressora desligada ou cabo USB fora'
}

Escrever ''
$pistola = Get-PnpDevice -PresentOnly | Where-Object { $_.InstanceId -match 'VID_0483&PID_0011' }
if ($pistola) {
    foreach ($p in $pistola) { Escrever ("  {0,-8} {1}" -f $p.Status, $p.InstanceId) }
    OK 'pistola C3TECH LB-50BK presente (ela e um teclado HID)'
} else {
    $hid = @(Get-PnpDevice -PresentOnly -Class 'Keyboard' | Where-Object { $_.InstanceId -like 'HID\*' })
    Escrever "  teclados HID presentes: $($hid.Count)"
    foreach ($h in $hid) { Escrever ("    {0}" -f $h.InstanceId) }
    Falta 'pistola C3TECH (VID_0483&PID_0011) nao encontrada - conferir se esta plugada'
}

# --------------------------------------------------------------- 2. spooler
Titulo '2. SPOOLER'
$sp = Get-Service -Name Spooler
if ($sp) {
    $spCim = Get-CimInstance Win32_Service -Filter 'Name="Spooler"'
    Escrever "  Servico Spooler: $($sp.Status)  (inicio: $($spCim.StartMode))"
    if ($sp.Status -eq 'Running') { OK 'spooler rodando' } else { Falta 'spooler PARADO' }
} else {
    Falta 'servico Spooler nao encontrado'
}

# ---------------------------------------------- 3. impressoras e compartilhamento
Titulo '3. IMPRESSORAS INSTALADAS  (nao mexer na FISCAL do UpSeller)'
$imps = Get-CimInstance Win32_Printer | Sort-Object Name
if (-not $imps) {
    Falta 'nenhuma impressora instalada nesta maquina'
} else {
    foreach ($i in $imps) {
        Escrever ''
        Escrever "  $($i.Name)"
        Escrever "     driver .......: $($i.DriverName)"
        Escrever "     porta ........: $($i.PortName)"
        Escrever "     compartilhada : $($i.Shared)   ShareName: $($i.ShareName)"
        Escrever "     padrao Windows: $($i.Default)"
        Escrever "     status .......: $($i.PrinterStatus)  WorkOffline: $($i.WorkOffline)"
    }
    Escrever ''
    $padrao = @($imps | Where-Object { $_.Default })
    if ($padrao.Count -gt 0) { Escrever "  Impressora PADRAO do Windows: $($padrao[0].Name)" }

    # a fila do estoque nesta maquina chama "ARGOS - Codigo Estoque" (nota 05/08),
    # nao "BXS" - aqui ja existe a BIXOLON FISCAL do UpSeller, que fica intocada
    $estoque = @($imps | Where-Object { $_.ShareName -eq 'ARGOS - Codigo Estoque' })
    if ($estoque.Count -gt 0) { OK "fila do estoque compartilhada como 'ARGOS - Codigo Estoque'" }
    else { Falta "nao existe fila compartilhada com ShareName 'ARGOS - Codigo Estoque'" }

    $genericas = @($imps | Where-Object { $_.DriverName -match 'Generic.*Text' })
    if ($genericas.Count -gt 0) {
        OK "driver 'Generic / Text Only' presente em: $(($genericas | ForEach-Object { $_.Name }) -join ' . ')"
    } else {
        Falta "nenhuma impressora com driver 'Generic / Text Only' (o caminho ZPL/RAW precisa dele)"
    }

    $fiscal = @($imps | Where-Object { $_.Name -match 'fiscal' -or $_.ShareName -match 'fiscal' })
    if ($fiscal.Count -gt 0) {
        Aviso "BIXOLON FISCAL encontrada: $(($fiscal | ForEach-Object { $_.Name }) -join ' . ') - NAO TOCAR"
    }
}

# ------------------------------------------------------------------ 4. filas
Titulo '4. FILAS  (job preso nao escoou = nao imprimiu)'
foreach ($i in $imps) {
    $jobs = @(Get-PrintJob -PrinterName $i.Name)
    if ($jobs.Count -gt 0) {
        Escrever "  $($i.Name): $($jobs.Count) job(s) PRESO(S)"
        foreach ($j in $jobs) { Escrever ("     id {0}  {1}  enviado {2}" -f $j.Id, $j.JobStatus, $j.SubmittedTime) }
        [void]$script:Faltas.Add("fila com job preso em '$($i.Name)'")
    } else {
        Escrever "  $($i.Name): fila vazia"
    }
}

# ------------------------------------------------------- 5. agente ArgosPrint
Titulo ("5. AGENTE ArgosPrint  (127.0.0.1:$Porta)")
$proc = Get-Process -Name 'ArgosPrint' -ErrorAction SilentlyContinue
$pasta = $null
if ($proc) {
    foreach ($p in $proc) { Escrever "  processo rodando: PID $($p.Id)   $($p.Path)" }
    if ($proc[0].Path) { $pasta = Split-Path $proc[0].Path -Parent }
    OK 'ArgosPrint.exe em execucao'
} else {
    Falta 'ArgosPrint.exe NAO esta rodando'
}

if (-not $pasta) {
    # procurar so nos lugares conhecidos - varrer o disco inteiro demora demais
    $candidatos = @(
        "$env:USERPROFILE\Desktop",
        "$env:USERPROFILE\Scripts",
        "$env:USERPROFILE\ArgosPrint",
        'C:\ArgosPrint',
        'C:\Argos',
        "$env:APPDATA\Microsoft\Windows\Start Menu\Programs\Startup"
    )
    foreach ($c in $candidatos) {
        $achado = Get-ChildItem -LiteralPath $c -Filter 'ArgosPrint.exe' -Recurse -Depth 2 -File -EA SilentlyContinue |
                    Select-Object -First 1
        if ($achado) { $pasta = $achado.DirectoryName; Escrever "  encontrado em: $($achado.FullName)"; break }
    }
}
if (-not $pasta) { Falta 'ArgosPrint.exe nao encontrado nos lugares conhecidos' }

if ($pasta) {
    Escrever ''
    Escrever "  Pasta do agente: $pasta"
    # "externo vence embutido": os dois arquivos ao lado do .exe mandam
    $txt = Join-Path $pasta 'impressora_argos.txt'
    if (Test-Path -LiteralPath $txt) {
        $destino = (Get-Content -LiteralPath $txt -Raw -Encoding UTF8).TrimStart([char]0xFEFF).Trim()
        OK "impressora_argos.txt existe -> [$destino]"
        if ($destino -notmatch 'ARGOS - Codigo Estoque') {
            Aviso "nesta maquina o destino deveria ser \\localhost\ARGOS - Codigo Estoque"
        }
    } else {
        Falta "impressora_argos.txt NAO existe - o agente cai no padrao \\localhost\BXS (errado aqui)"
    }
    $cat = Join-Path $pasta 'catalogo_argos.json'
    if (Test-Path -LiteralPath $cat) {
        $kb = [int]((Get-Item -LiteralPath $cat).Length / 1KB)
        OK "catalogo_argos.json externo presente ($kb KB)"
    } else {
        Aviso 'catalogo_argos.json externo ausente - vale o catalogo embutido no .exe'
    }
}

Escrever ''
$escuta = Get-NetTCPConnection -LocalPort $Porta -State Listen -EA SilentlyContinue
if ($escuta) {
    foreach ($e in $escuta) { Escrever "  escutando: $($e.LocalAddress):$($e.LocalPort)" }
    $so127 = @($escuta | Where-Object { $_.LocalAddress -ne '127.0.0.1' })
    if ($so127.Count -eq 0) { OK "porta $Porta escutando SO em 127.0.0.1 (correto - nunca 0.0.0.0)" }
    else { Aviso "porta $Porta escutando fora de 127.0.0.1 - conferir, o agente nao deve sair na rede" }
} else {
    Falta "ninguem escutando na porta $Porta"
}

$resp = $null
try {
    $resp = Invoke-WebRequest -Uri "http://127.0.0.1:$Porta/status" -UseBasicParsing -TimeoutSec 4
} catch { $resp = $null }
if ($resp -and $resp.StatusCode -eq 200) {
    Escrever "  /status -> HTTP 200"
    Escrever "  $($resp.Content)"
    OK '/status respondeu'
    $pna = $resp.Headers['Access-Control-Allow-Private-Network']
    if ($pna) { OK "header Access-Control-Allow-Private-Network: $pna" }
    else { Falta 'SEM o header Access-Control-Allow-Private-Network - o Chrome vai bloquear o site' }
} else {
    Falta "/status nao respondeu em 127.0.0.1:$Porta"
}

# --------------------------------------------------------------- 6. navegador
Titulo '6. NAVEGADOR  (este script NAO prova este elo)'
Escrever '  PowerShell nao aplica Private Network Access. Ele prova que o agente'
Escrever '  responde - nao prova que o Chrome deixa o site chamar o agente.'
Escrever ''
Escrever '  O teste de verdade, no CHROME logado no Argos Estoque (F12 -> Console):'
Escrever '      await ArgosPrint.disponivel()      // tem que dar true'
Escrever '  e o selo verde "Etiquetadora conectada" tem que aparecer na tela.'

# ------------------------------------------------------------------ resumo
Titulo 'RESUMO'
if ($script:Faltas.Count -eq 0) {
    Escrever '  Nada faltando: os cinco elos responderam. Falta so a prova no Chrome.'
} else {
    Escrever "  $($script:Faltas.Count) ponto(s) faltando, na ordem em que foram achados:"
    Escrever ''
    $n = 1
    foreach ($f in $script:Faltas) { Escrever ("  {0}. {1}" -f $n, $f); $n++ }
}
Escrever ''
Escrever "  Relatorio salvo em: $Saida"
Escrever '  MANDE ESTE ARQUIVO INTEIRO antes de instalar qualquer coisa.'

$script:Linhas | Set-Content -LiteralPath $Saida -Encoding UTF8
