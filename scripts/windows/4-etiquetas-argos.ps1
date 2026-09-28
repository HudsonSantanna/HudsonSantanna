#Requires -Version 5.1
<#
    4-etiquetas-argos.ps1 - Radiografia da estacao de etiquetas: impressora
    Bixolon XD3-40t, agente Argos Print (porta 9110) e pistola de codigo de
    barras. Roda a ORDEM OFICIAL DE DIAGNOSTICO das notas do Cerebro:
    dispositivo USB -> spooler -> compartilhamento -> agente -> navegador.

    SOMENTE LEITURA. Nao instala, nao altera fila de impressao, nao mexe em
    servico nenhum. Serve para dois momentos:

      - na maquina que JA funciona, para levantar a configuracao de origem;
      - na maquina NOVA, para conferir o que ficou faltando depois do setup.

    O relatorio vai para a tela e para um arquivo .txt na area de trabalho,
    pronto para ser passado adiante.

    Uso:
      powershell -ExecutionPolicy Bypass -File .\4-etiquetas-argos.ps1
      powershell -ExecutionPolicy Bypass -File .\4-etiquetas-argos.ps1 -Porta 9110
#>
[CmdletBinding()]
param(
    [int]   $Porta  = 9110,
    [string]$Marca  = 'bixolon|bxs|etiqueta|codigo estoque',
    [string]$VidImpressora = 'VID_1504',   # Bixolon
    [string]$VidPistola    = 'VID_0483',   # C3TECH LB-50BK (STMicroelectronics)
    [string]$Saida  = "$env:USERPROFILE\Desktop\etiquetas-argos-$env:COMPUTERNAME-$(Get-Date -Format 'yyyyMMdd-HHmm').txt"
)

$ErrorActionPreference = 'SilentlyContinue'
$script:Linhas = New-Object System.Collections.ArrayList

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
function Item([string]$Rotulo, $Valor) {
    if ($null -eq $Valor -or "$Valor" -eq '') { $Valor = '-' }
    Escrever ("  {0,-22}: {1}" -f $Rotulo, $Valor)
}
function EhAdmin {
    $id = [Security.Principal.WindowsIdentity]::GetCurrent()
    (New-Object Security.Principal.WindowsPrincipal $id).IsInRole(
        [Security.Principal.WindowsBuiltInRole]::Administrator)
}

Escrever "Estacao de etiquetas - $(Get-Date -Format 'dd/MM/yyyy HH:mm')"
Escrever "Computador: $env:COMPUTERNAME   Usuario: $env:USERNAME"
if (-not (EhAdmin)) {
    Escrever '*** Sem privilegio de administrador: compartilhamentos e servicos'
    Escrever '*** podem aparecer incompletos.'
}

# ------------------------------------------------------------------ sistema
Titulo 'SISTEMA E REDE'
$so = Get-CimInstance Win32_OperatingSystem
$cs = Get-CimInstance Win32_ComputerSystem
Item 'Windows'    ("{0} (build {1})" -f $so.Caption, $so.BuildNumber)
Item 'Modelo'     ("{0} {1}" -f $cs.Manufacturer, $cs.Model)
Item 'Dominio/grupo' $cs.Domain
foreach ($ip in (Get-NetIPAddress -AddressFamily IPv4 |
                 Where-Object { $_.IPAddress -ne '127.0.0.1' })) {
    Item ("IP ({0})" -f $ip.InterfaceAlias) ("{0}/{1}" -f $ip.IPAddress, $ip.PrefixLength)
}

# ------------------------------------------- 1. dispositivo fisico presente
Titulo '1. DISPOSITIVO USB DA IMPRESSORA'
Escrever '  A causa mais comum de "nao imprime" e a impressora nao estar aqui.'
Escrever '  Este teste vem ANTES de driver, buffer e script.'
Escrever ''
$usbImpressora = Get-PnpDevice -PresentOnly |
    Where-Object { $_.InstanceId -match $VidImpressora }
if ($usbImpressora) {
    foreach ($d in $usbImpressora) { Item $d.FriendlyName $d.InstanceId }
    Escrever ''
    Escrever '  OK: a impressora esta fisicamente conectada nesta maquina.'
} else {
    Escrever "  *** NENHUM dispositivo $VidImpressora presente."
    Escrever '  *** A Bixolon nao esta ligada nesta maquina (ou esta em outra).'
    Escrever '  *** Sem isso, nada do resto adianta.'
}

# ------------------------------------------------------------- 2. spooler
Titulo '2. SPOOLER DE IMPRESSAO'
$spooler = Get-Service Spooler
Item 'Servico'  ("{0} [{1}]" -f $spooler.DisplayName, $spooler.Status)
Item 'Inicio'   (Get-CimInstance Win32_Service -Filter "Name='Spooler'").StartMode

# -------------------------------------------------------------- impressoras
Titulo '3. IMPRESSORAS INSTALADAS'
$impressoras = Get-Printer
if (-not $impressoras) {
    Escrever '  Nenhuma impressora encontrada.'
} else {
    foreach ($p in $impressoras) {
        $marcada = if ("$($p.Name) $($p.DriverName)" -match $Marca) { ' <<< mesma marca' } else { '' }
        Escrever ''
        Escrever ("  [{0}]{1}" -f $p.Name, $marcada)
        Item 'Driver'          $p.DriverName
        Item 'Porta'           $p.PortName
        Item 'Compartilhada'   ("{0}{1}" -f $p.Shared, $(if ($p.Shared) { " (\\$env:COMPUTERNAME\$($p.ShareName))" } else { '' }))
        Item 'Padrao do Windows' ((Get-CimInstance Win32_Printer -Filter "Name='$($p.Name -replace "'","''")'").Default)
        Item 'Status'          $p.PrinterStatus
        $cfg = Get-PrintConfiguration -PrinterName $p.Name
        if ($cfg) {
            Item 'Papel'       $cfg.PaperSize
            Item 'Orientacao'  $cfg.PaperOrientation
            Item 'Cor/DPI'     ("{0} / {1}x{2}" -f $cfg.Color, $cfg.DpiX, $cfg.DpiY)
        }
        $fila = Get-PrintJob -PrinterName $p.Name
        if ($fila) { Item 'Trabalhos na fila' $fila.Count }
    }
}

Titulo '3b. PORTAS E DRIVERS'
foreach ($porta in (Get-PrinterPort)) {
    $detalhe = if ($porta.PrinterHostAddress) { "$($porta.PrinterHostAddress):$($porta.PortNumber)" } else { $porta.Description }
    Item $porta.Name $detalhe
}
Escrever ''
foreach ($d in (Get-PrinterDriver)) {
    Item $d.Name ("{0} | {1}" -f $d.PrinterEnvironment, $d.InfPath)
}

# ------------------------------------------------------- compartilhamentos
Titulo '4. COMPARTILHAMENTOS (o agente imprime por \\localhost\<share>)'
$compartilhadas = $impressoras | Where-Object { $_.Shared }
if (-not $compartilhadas) {
    Escrever '  Nenhuma impressora compartilhada.'
    Escrever '  O agente aponta para \\localhost\<NOME>: sem compartilhamento ele nao imprime.'
    Escrever '  Nomes conhecidos: "BXS" (maquina do Hudson) e'
    Escrever '  "ARGOS - Codigo Estoque" (HUDSONINTEGRAR, onde ja existe a fiscal).'
} else {
    foreach ($p in $compartilhadas) {
        Item $p.Name ("\\{0}\{1}   (\\localhost\{1})" -f $env:COMPUTERNAME, $p.ShareName)
    }
}

# ------------------------------------------------------------------ agente
Titulo "5. AGENTE ARGOS PRINT (porta $Porta)"
$conexoes = Get-NetTCPConnection -LocalPort $Porta -State Listen
if (-not $conexoes) {
    Escrever "  Nada escutando em 127.0.0.1:$Porta - o agente NAO esta rodando."
} else {
    foreach ($c in $conexoes) {
        $proc = Get-CimInstance Win32_Process -Filter "ProcessId=$($c.OwningProcess)"
        Escrever ''
        Item 'Escutando em'  ("{0}:{1}" -f $c.LocalAddress, $c.LocalPort)
        Item 'PID'           $c.OwningProcess
        Item 'Processo'      $proc.Name
        Item 'Executavel'    $proc.ExecutablePath
        Item 'Linha completa' $proc.CommandLine
        Item 'Iniciado em'   $proc.CreationDate
        if ($proc.ExecutablePath) {
            Item 'Pasta do agente' (Split-Path $proc.ExecutablePath -Parent)
        }
    }
}

Escrever ''
Escrever "  Testando http://127.0.0.1:$Porta/status ..."
try {
    $r = Invoke-WebRequest -Uri "http://127.0.0.1:$Porta/status" -UseBasicParsing -TimeoutSec 5
    Item 'HTTP'      $r.StatusCode
    Item 'Resposta'  ($r.Content -replace '\s+', ' ')
} catch {
    Item 'HTTP' ("falhou: {0}" -f $_.Exception.Message)
}

Titulo '5a. DESTINO E CATALOGO (externo vence embutido)'
Item 'Env ARGOS_IMPRESSORA' $env:ARGOS_IMPRESSORA
$pastasAgente = @()
if ($conexoes) {
    foreach ($c in $conexoes) {
        $exe = (Get-CimInstance Win32_Process -Filter "ProcessId=$($c.OwningProcess)").ExecutablePath
        if ($exe) { $pastasAgente += (Split-Path $exe -Parent) }
    }
}
$pastasAgente += "$env:USERPROFILE\Scripts"
foreach ($pasta in ($pastasAgente | Select-Object -Unique)) {
    if (-not (Test-Path $pasta)) { continue }
    Escrever ''
    Escrever "  Pasta: $pasta"
    $arqImp = Join-Path $pasta 'impressora_argos.txt'
    if (Test-Path $arqImp) {
        $destino = (Get-Content $arqImp -Encoding UTF8 |
                    Where-Object { $_.Trim() -and -not $_.Trim().StartsWith('#') } |
                    Select-Object -First 1)
        if ($destino) {
            Item 'impressora_argos.txt' $destino.Trim()
        } else {
            Item 'impressora_argos.txt' 'existe, mas so tem comentario -> cai no padrao embutido'
        }
    } else {
        Item 'impressora_argos.txt' 'ausente -> usa o padrao embutido \\localhost\BXS'
    }
    $arqCat = Join-Path $pasta 'catalogo_argos.json'
    if (Test-Path $arqCat) {
        $cat = Get-Item $arqCat
        Item 'catalogo_argos.json' ("{0:N0} KB, alterado {1:dd/MM/yyyy HH:mm}" -f ($cat.Length/1KB), $cat.LastWriteTime)
    } else {
        Item 'catalogo_argos.json' 'ausente -> catalogo embutido no .exe'
    }
    foreach ($exe in (Get-ChildItem $pasta -Filter 'ArgosPrint*.exe' -File)) {
        Item $exe.Name ("{0:N1} MB, {1:dd/MM/yyyy HH:mm}" -f ($exe.Length/1MB), $exe.LastWriteTime)
    }
}

Titulo '5b. COMO O AGENTE SOBE'
$pastasInicializar = @(
    "$env:APPDATA\Microsoft\Windows\Start Menu\Programs\Startup",
    "$env:ProgramData\Microsoft\Windows\Start Menu\Programs\StartUp"
)
foreach ($pasta in $pastasInicializar) {
    foreach ($atalho in (Get-ChildItem -Path $pasta -File)) {
        Item 'Inicializar' ("{0}  ({1})" -f $atalho.Name, $pasta)
    }
}
foreach ($chave in @('HKCU:\Software\Microsoft\Windows\CurrentVersion\Run',
                     'HKLM:\Software\Microsoft\Windows\CurrentVersion\Run')) {
    $valores = Get-ItemProperty -Path $chave
    if ($valores) {
        foreach ($nome in ($valores.PSObject.Properties.Name | Where-Object { $_ -notlike 'PS*' })) {
            if ("$($valores.$nome)" -match 'argos|print|etiqueta|python|pythonw') {
                Item "Run ($nome)" $valores.$nome
            }
        }
    }
}
foreach ($t in (Get-ScheduledTask | Where-Object { $_.TaskName -match 'argos|etiqueta|print' })) {
    Item 'Tarefa agendada' ("{0} [{1}]" -f $t.TaskName, $t.State)
}
foreach ($s in (Get-Service | Where-Object { $_.DisplayName -match 'argos|etiqueta' })) {
    Item 'Servico' ("{0} [{1}]" -f $s.DisplayName, $s.Status)
}

Titulo '5c. REGRAS DE FIREWALL RELACIONADAS'
$regras = Get-NetFirewallRule -Enabled True |
    Where-Object { $_.DisplayName -match 'argos|etiqueta|print' }
if (-not $regras) {
    Escrever "  Nenhuma regra especifica. Em 127.0.0.1 nao e necessaria;"
    Escrever "  so faria falta se o agente fosse atendido por outras maquinas."
} else {
    foreach ($r in $regras) { Item $r.DisplayName ("{0}/{1}" -f $r.Direction, $r.Action) }
}

# ------------------------------------------------------------------ leitor
Titulo '6. PISTOLA / LEITOR DE CODIGO DE BARRAS'
$pistola = Get-PnpDevice -PresentOnly | Where-Object { $_.InstanceId -match $VidPistola }
if ($pistola) {
    Escrever "  Pistola conhecida ($VidPistola - C3TECH LB-50BK):"
    foreach ($d in $pistola) { Item $d.FriendlyName $d.InstanceId }
    Escrever ''
    Escrever '  Ela e um TECLADO: precisa mandar Enter no fim da leitura.'
    Escrever '  Teste no Bloco de Notas antes de culpar o sistema.'
} else {
    Escrever "  Pistola $VidPistola nao encontrada. Outros HID abaixo:"
}
Escrever ''
Escrever '  Teclados e dispositivos HID (o leitor comum aparece como teclado):'
foreach ($d in (Get-PnpDevice -Class 'Keyboard','HIDClass' -Status OK)) {
    if ($d.FriendlyName -match 'HID|Barcode|Scanner|Leitor|Symbol|Honeywell|Zebra|Bixolon|Elgin') {
        Item $d.FriendlyName $d.InstanceId
    }
}
Escrever ''
Escrever '  Dispositivos de imagem (scanner de mesa WIA/TWAIN):'
$imagem = Get-PnpDevice -Class 'Image' -Status OK
if (-not $imagem) {
    Escrever '    Nenhum. Se o "scanner" e um leitor de codigo de barras USB,'
    Escrever '    isso e o esperado: ele se apresenta como teclado.'
} else {
    foreach ($d in $imagem) { Item $d.FriendlyName $d.InstanceId }
}
Escrever ''
Escrever '  Portas seriais (leitores em modo COM/emulacao serial):'
foreach ($p in (Get-CimInstance Win32_SerialPort)) { Item $p.DeviceID $p.Name }
Escrever ''
Escrever '  Dispositivos USB desconhecidos ou com problema:'
foreach ($d in (Get-PnpDevice | Where-Object { $_.Status -ne 'OK' -and $_.InstanceId -like 'USB*' })) {
    Item $d.Status $d.FriendlyName
}

Titulo 'RESUMO'
$daMarca      = $impressoras | Where-Object { "$($_.Name) $($_.DriverName)" -match $Marca }
$compartilhada = $daMarca | Where-Object { $_.Shared }
Item '1. USB presente'       $(if ($usbImpressora) { 'sim' } else { 'NAO' })
Item '2. Spooler'            $spooler.Status
Item '3. Impressoras da marca' ($daMarca.Count)
Item '4. Delas, compartilhadas' ($compartilhada.Count)
Item '5. Agente respondendo'  $(if ($conexoes) { 'sim' } else { 'NAO' })
Item '6. Pistola presente'    $(if ($pistola) { 'sim' } else { 'NAO' })
Escrever ''
Escrever '  O teste 7 nao da para fazer por script: abrir o sistema NO CHROME'
Escrever '  logado e conferir o selo "Etiquetadora conectada". PowerShell nao'
Escrever '  aplica Private Network Access - so o navegador prova esse elo.'
if ($daMarca.Count -gt 1) {
    Escrever ''
    Escrever '  ATENCAO: ha mais de uma impressora da mesma marca nesta maquina.'
    Escrever '  Confira pelo NOME DO COMPARTILHAMENTO para qual o agente aponta,'
    Escrever '  para nao mandar etiqueta para a impressora de nota fiscal.'
}

Escrever ''
$script:Linhas | Out-File -FilePath $Saida -Encoding UTF8
Write-Host ''
Write-Host "Relatorio salvo em: $Saida" -ForegroundColor Green
