#Requires -Version 5.1
<#
    5-diagnostico-etiquetadora.ps1 - Radiografia da etiquetadora BIXOLON, do
    agente ArgosPrint e da pistola de codigo de barras.

    SOMENTE LEITURA. Nao instala, nao renomeia, nao compartilha, nao apaga fila,
    nao mexe em impressora nenhuma - inclusive a BIXOLON FISCAL do UpSeller.

    Segue a ordem oficial de diagnostico:
        dispositivo USB -> spooler -> compartilhamento -> fila -> agente 9110 -> navegador
    A causa mais comum e a mais boba: o teste 1 responde em 2 segundos.

    Uso:
      powershell -ExecutionPolicy Bypass -File .\5-diagnostico-etiquetadora.ps1
#>
[CmdletBinding()]
param(
    [int]   $Porta = 9110,
    [string]$Saida
)

$ErrorActionPreference = 'SilentlyContinue'

# A Area de Trabalho nem sempre e "$env:USERPROFILE\Desktop": com OneDrive ela
# vira "...\OneDrive\Area de Trabalho" e aquele caminho NAO existe. Perguntar ao
# Windows onde ela esta de verdade, e cair no perfil do usuario se nem isso der.
if (-not $Saida) {
    $desk = [Environment]::GetFolderPath('Desktop')
    if (-not $desk -or -not (Test-Path -LiteralPath $desk)) { $desk = $env:USERPROFILE }
    $Saida = Join-Path $desk "diagnostico-etiquetadora-$(Get-Date -Format 'yyyyMMdd-HHmm').txt"
}
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

# Cmdlet que nao existe nesta versao do Windows devolve nada - e "nada" aqui
# seria lido como "aparelho ausente". Um teste que nao rodou tem que dizer que
# nao rodou, nunca acusar falta.
function Existe([string]$Cmdlet) {
    [bool](Get-Command -Name $Cmdlet -ErrorAction SilentlyContinue)
}
function SemCmdlet([string]$Cmdlet, [string]$Oque) {
    Aviso "TESTE NAO REALIZADO (isto nao e uma falta): $Oque - $Cmdlet indisponivel nesta maquina"
}

Escrever "ARGOS - diagnostico da etiquetadora  $(Get-Date -Format 'dd/MM/yyyy HH:mm')"
Escrever 'SOMENTE LEITURA - nada nesta maquina e alterado por este script.'

# ------------------------------------------------------------- 0. identidade
Titulo '0. ESTA MAQUINA'
$ativo   = (Get-ItemProperty 'HKLM:\SYSTEM\CurrentControlSet\Control\ComputerName\ActiveComputerName').ComputerName
$proximo = (Get-ItemProperty 'HKLM:\SYSTEM\CurrentControlSet\Control\ComputerName\ComputerName').ComputerName
if (-not $ativo) { $ativo = $env:COMPUTERNAME }
Escrever "  Nome agora .......: $ativo"
Escrever "  Usuario ..........: $env:USERNAME"
if (Existe 'Get-NetIPAddress') {
    $ips = @(Get-NetIPAddress -AddressFamily IPv4 |
             Where-Object { $_.IPAddress -notlike '127.*' -and $_.IPAddress -notlike '169.254.*' })
    foreach ($ip in $ips) { Escrever "  IP ...............: $($ip.IPAddress)  ($($ip.InterfaceAlias))" }
} else {
    SemCmdlet 'Get-NetIPAddress' 'lista de IPs'
}

if ($proximo -and $ativo -and $proximo -ne $ativo) {
    Aviso "RENOMEACAO PENDENTE: depois de reiniciar esta maquina passa a se chamar '$proximo'."
    Aviso "CONFIRA A GRAFIA antes de reiniciar. Se estiver errada, renomeie de novo ANTES do reboot."
    [void]$script:Faltas.Add("renomeacao pendente: $ativo -> $proximo (conferir grafia)")
}

# ------------------------------------------------- 1. o dispositivo USB existe?
# Teste 1: se a impressora nao existe pro Windows AGORA, o resto e perda de
# tempo. VID_1504 = BIXOLON. VID_0483&PID_0011 = pistola C3TECH LB-50BK.
Titulo '1. DISPOSITIVO USB  (o teste que responde em 2 segundos)'
if (-not (Existe 'Get-PnpDevice')) {
    SemCmdlet 'Get-PnpDevice' 'hardware USB'
} else {
    $usb = @(Get-PnpDevice -PresentOnly |
             Where-Object { $_.InstanceId -like 'USBPRINT\*' -or $_.InstanceId -match 'VID_1504' })
    if ($usb.Count -gt 0) {
        foreach ($d in $usb) { Escrever ("  {0,-8} {1}" -f $d.Status, $d.InstanceId) }
        $bixolon = @($usb | Where-Object { $_.InstanceId -match 'VID_1504' -or $_.InstanceId -match 'BIXOLON' })
        if ($bixolon.Count -gt 0) { OK "BIXOLON presente ($($bixolon.Count) dispositivo(s))" }
        else { Falta 'nenhum dispositivo com VID_1504 (BIXOLON) - ver se a XD3-40t esta ligada e no cabo' }
    } else {
        Falta 'NENHUM dispositivo USBPRINT presente - impressora desligada ou cabo USB fora'
    }

    Escrever ''
    $pistola = @(Get-PnpDevice -PresentOnly | Where-Object { $_.InstanceId -match 'VID_0483&PID_0011' })
    if ($pistola.Count -gt 0) {
        foreach ($p in $pistola) { Escrever ("  {0,-8} {1}" -f $p.Status, $p.InstanceId) }
        OK 'pistola C3TECH LB-50BK presente (ela e um teclado HID)'
    } else {
        $hid = @(Get-PnpDevice -PresentOnly -Class 'Keyboard' | Where-Object { $_.InstanceId -like 'HID\*' })
        Escrever "  teclados HID presentes: $($hid.Count)"
        foreach ($h in $hid) { Escrever ("    {0}" -f $h.InstanceId) }
        Falta 'pistola C3TECH (VID_0483&PID_0011) nao encontrada - conferir se esta plugada'
    }
}

# --------------------------------------------------------------- 2. spooler
Titulo '2. SPOOLER'
$sp = Get-Service -Name Spooler -ErrorAction SilentlyContinue
if ($sp) {
    $spCim = Get-CimInstance Win32_Service -Filter 'Name="Spooler"'
    Escrever "  Servico Spooler: $($sp.Status)  (inicio: $($spCim.StartMode))"
    if ($sp.Status -eq 'Running') { OK 'spooler rodando' } else { Falta 'spooler PARADO' }
} else {
    Falta 'servico Spooler nao encontrado'
}

# ---------------------------------------------- 3. impressoras e compartilhamento
Titulo '3. IMPRESSORAS INSTALADAS  (nao mexer na FISCAL do UpSeller)'
$imps = @(Get-CimInstance Win32_Printer | Sort-Object Name)
if ($imps.Count -eq 0) {
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

    # a fila do estoque nesta maquina chama "ARGOS - Codigo Estoque", nao "BXS":
    # aqui ja existe a BIXOLON FISCAL do UpSeller, que fica intocada
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
if (-not (Existe 'Get-PrintJob')) {
    SemCmdlet 'Get-PrintJob' 'conteudo das filas'
} elseif ($imps.Count -eq 0) {
    Escrever '  sem impressoras instaladas - nao ha fila para olhar'
} else {
    foreach ($i in $imps) {
        $jobs = @(Get-PrintJob -PrinterName $i.Name -ErrorAction SilentlyContinue)
        if ($jobs.Count -gt 0) {
            Escrever "  $($i.Name): $($jobs.Count) job(s) PRESO(S)"
            foreach ($j in $jobs) { Escrever ("     id {0}  {1}  enviado {2}" -f $j.Id, $j.JobStatus, $j.SubmittedTime) }
            [void]$script:Faltas.Add("fila com job preso em '$($i.Name)'")
        } else {
            Escrever "  $($i.Name): fila vazia"
        }
    }
}

# ------------------------------------------------------- 5. agente ArgosPrint
Titulo ("5. AGENTE ArgosPrint  (127.0.0.1:$Porta)")
$proc = @(Get-Process -Name 'ArgosPrint' -ErrorAction SilentlyContinue)
$pasta = $null
if ($proc.Count -gt 0) {
    foreach ($p in $proc) { Escrever "  processo rodando: PID $($p.Id)   $($p.Path)" }
    if ($proc[0].Path) { $pasta = Split-Path $proc[0].Path -Parent }
    OK 'ArgosPrint.exe em execucao'
} else {
    Falta 'ArgosPrint.exe NAO esta rodando'
}

if (-not $pasta) {
    # procurar so nos lugares conhecidos - varrer o disco inteiro demora demais
    $candidatos = @(
        [Environment]::GetFolderPath('Desktop'),
        "$env:USERPROFILE\Desktop",
        "$env:USERPROFILE\Scripts",
        "$env:USERPROFILE\ArgosPrint",
        'C:\ArgosPrint',
        'C:\Argos',
        "$env:APPDATA\Microsoft\Windows\Start Menu\Programs\Startup"
    ) | Where-Object { $_ } | Select-Object -Unique
    foreach ($c in $candidatos) {
        $achado = Get-ChildItem -LiteralPath $c -Filter 'ArgosPrint.exe' -Recurse -Depth 2 -File -ErrorAction SilentlyContinue |
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
        $bruto = Get-Content -LiteralPath $txt -Raw -Encoding UTF8
        if (-not $bruto) {
            Falta 'impressora_argos.txt existe mas esta VAZIO - o agente cai no padrao \\localhost\BXS (errado aqui)'
        } else {
            $destino = $bruto.TrimStart([char]0xFEFF).Trim()
            OK "impressora_argos.txt existe -> [$destino]"
            if ($destino -notmatch 'ARGOS - Codigo Estoque') {
                Aviso 'nesta maquina o destino deveria ser \\localhost\ARGOS - Codigo Estoque'
            }
        }
    } else {
        Falta 'impressora_argos.txt NAO existe - o agente cai no padrao \\localhost\BXS (errado aqui)'
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
if (Existe 'Get-NetTCPConnection') {
    $escuta = @(Get-NetTCPConnection -LocalPort $Porta -State Listen -ErrorAction SilentlyContinue)
    if ($escuta.Count -gt 0) {
        foreach ($e in $escuta) { Escrever "  escutando: $($e.LocalAddress):$($e.LocalPort)" }
        $foraDoLocal = @($escuta | Where-Object { $_.LocalAddress -ne '127.0.0.1' })
        if ($foraDoLocal.Count -eq 0) { OK "porta $Porta escutando SO em 127.0.0.1 (correto - nunca 0.0.0.0)" }
        else { Aviso "porta $Porta escutando fora de 127.0.0.1 - conferir, o agente nao deve sair na rede" }
    } else {
        Falta "ninguem escutando na porta $Porta"
    }
} else {
    # Windows sem o modulo NetTCPIP: netstat responde a mesma pergunta
    SemCmdlet 'Get-NetTCPConnection' 'escuta da porta (usando netstat no lugar)'
    $netstat = @(netstat -ano | Select-String -Pattern ":$Porta\s" | Select-String -Pattern 'LISTENING')
    if ($netstat.Count -gt 0) {
        foreach ($l in $netstat) { Escrever "  netstat: $($l.ToString().Trim())" }
        OK "porta $Porta escutando (visto pelo netstat)"
    } else {
        Falta "ninguem escutando na porta $Porta (visto pelo netstat)"
    }
}

$resp = $null
try {
    $resp = Invoke-WebRequest -Uri "http://127.0.0.1:$Porta/status" -UseBasicParsing -TimeoutSec 4
} catch { $resp = $null }
if ($resp -and $resp.StatusCode -eq 200) {
    Escrever "  /status -> HTTP 200"
    Escrever "  $($resp.Content)"
    OK '/status respondeu'
    # cabecalho pode vir com qualquer caixa; procurar sem depender da grafia
    $pna = $null
    foreach ($k in $resp.Headers.Keys) {
        if ($k -and $k.ToString().ToLower() -eq 'access-control-allow-private-network') { $pna = $resp.Headers[$k] }
    }
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
# a politica, quando existe, e o unico pedaco do elo 6 que da pra ler daqui
$politicas = @(
    'HKLM:\SOFTWARE\Policies\Google\Chrome',
    'HKCU:\SOFTWARE\Policies\Google\Chrome',
    'HKLM:\SOFTWARE\Policies\Microsoft\Edge',
    'HKCU:\SOFTWARE\Policies\Microsoft\Edge'
)
$achouPolitica = $false
foreach ($p in $politicas) {
    $lista = Get-ItemProperty -Path "$p\InsecurePrivateNetworkRequestsAllowedForUrls" -ErrorAction SilentlyContinue
    if ($lista) {
        $valores = @($lista.PSObject.Properties |
                     Where-Object { $_.Name -match '^\d+$' } |
                     ForEach-Object { $_.Value })
        if ($valores.Count -gt 0) {
            $achouPolitica = $true
            Escrever "  politica em $p :"
            foreach ($v in $valores) { Escrever "     $v" }
        }
    }
}
if (-not $achouPolitica) {
    Escrever '  Nenhuma politica InsecurePrivateNetworkRequestsAllowedForUrls no registro'
    Escrever '  (normal - so importa se o Chrome estiver bloqueando a chamada ao agente).'
}
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

# relatorio: se a Area de Trabalho nao aceitar escrita, salvar no TEMP e dizer onde
$alvos = New-Object System.Collections.ArrayList
[void]$alvos.Add($Saida)
if ($env:TEMP) { [void]$alvos.Add((Join-Path $env:TEMP (Split-Path $Saida -Leaf))) }
$gravado = $null
foreach ($alvo in $alvos) {
    try {
        $script:Linhas | Set-Content -LiteralPath $alvo -Encoding UTF8 -ErrorAction Stop
        $gravado = $alvo
        break
    } catch { continue }
}
if ($gravado) {
    Write-Host "  Relatorio salvo em: $gravado"
    Write-Host '  MANDE ESTE ARQUIVO INTEIRO antes de instalar qualquer coisa.'
} else {
    Write-Host '  NAO consegui salvar o relatorio em arquivo - copie o texto acima da tela.'
}
