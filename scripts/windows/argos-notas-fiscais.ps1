#Requires -Version 5.1
<#
    argos-notas-fiscais.ps1 - Agente Argos que imprime as etiquetas de envio e
    os DANFEs que o UpSeller gera, no lugar do agente de impressao do UpSeller.

    QUEM FAZ O QUE:
      - o UpSeller (site app.upseller.com) continua EMITINDO a NF-e e mandando
        para Shopee, Mercado Livre e TikTok. Nada disso muda.
      - este agente so IMPRIME: vigia uma pasta, e cada arquivo que cai nela
        vai para a BIXOLON 'Etiqueta Fiscal' e depois sai da pasta.

    Fluxo do dia a dia:
      UpSeller > Pedidos > imprimir etiqueta/DANFE > "baixar PDF"
          -> o Chrome salva em  C:\Argos\NotasFiscais\Entrada
          -> o agente imprime na 'Etiqueta Fiscal'
          -> o arquivo vai para  C:\Argos\NotasFiscais\Impressos\<data>\
             (ou para  ...\Erro\  com o motivo no log, se nao saiu)

    Tipos de arquivo:
      .pdf               -> SumatraPDF (linha de comando, sem janela) pelo driver
      .zpl .prn .txt     -> RAW direto na fila (WritePrinter), sem driver -
                            o mesmo caminho do 6-configurar-etiquetadora.ps1
    Para PDF o SumatraPDF precisa estar instalado (ou o .exe portatil ao lado
    deste script). Sem ele, PDF vai para Erro\ com o aviso no log.

    Uso:
      # testar uma vez, olhando (processa o que estiver na pasta e sai)
      powershell -ExecutionPolicy Bypass -File .\argos-notas-fiscais.ps1 -UmaVez

      # so dizer o que faria, sem imprimir nem mover nada
      powershell -ExecutionPolicy Bypass -File .\argos-notas-fiscais.ps1 -UmaVez -Simular

      # instalar: sobe sozinho no logon, escondido, vigiando a pasta
      powershell -ExecutionPolicy Bypass -File .\argos-notas-fiscais.ps1 -Instalar

      # remover a tarefa (nao apaga pastas nem arquivos)
      powershell -ExecutionPolicy Bypass -File .\argos-notas-fiscais.ps1 -Desinstalar

    Log: %LOCALAPPDATA%\Argos\notas-fiscais.log
#>
[CmdletBinding()]
param(
    [string]$Pasta     = 'C:\Argos\NotasFiscais',
    [string]$Fila      = 'Etiqueta Fiscal',
    [string]$Sumatra,
    [ValidateSet('noscale', 'fit', 'shrink')]
    [string]$AjustePdf = 'noscale',
    [int]   $Intervalo = 3,
    [switch]$UmaVez,
    [switch]$Simular,
    [switch]$Instalar,
    [switch]$Desinstalar,
    [string]$Tarefa    = 'ARGOS - Notas Fiscais',
    [string]$Log       = "$env:LOCALAPPDATA\Argos\notas-fiscais.log"
)

$ErrorActionPreference = 'Stop'

$entrada   = Join-Path $Pasta 'Entrada'
$impressos = Join-Path $Pasta 'Impressos'
$comErro   = Join-Path $Pasta 'Erro'
$tiposRaw  = @('.zpl', '.prn', '.txt')
# Download pela metade: o Chrome/Edge/Firefox escrevem com estes nomes e so
# renomeiam para o nome final quando o arquivo esta completo.
$ignorar   = @('.crdownload', '.tmp', '.part', '.partial', '.download')

function Registrar([string]$Texto) {
    $linha = "$(Get-Date -Format 'yyyy-MM-dd HH:mm:ss')  $Texto"
    Write-Host $linha
    try {
        $dir = Split-Path $Log -Parent
        if (-not (Test-Path -LiteralPath $dir)) { New-Item -ItemType Directory -Path $dir -Force | Out-Null }
        Add-Content -LiteralPath $Log -Value $linha -Encoding UTF8
    } catch { }
}

# --------------------------------------------------------- instalar/desinstalar
if ($Desinstalar) {
    if (Get-ScheduledTask -TaskName $Tarefa -ErrorAction SilentlyContinue) {
        Unregister-ScheduledTask -TaskName $Tarefa -Confirm:$false
        Registrar "[OK] Tarefa '$Tarefa' removida. Pastas e arquivos ficaram como estavam."
    } else {
        Registrar "[!] Tarefa '$Tarefa' nao existe."
    }
    exit 0
}

if ($Instalar) {
    foreach ($d in @($entrada, $impressos, $comErro)) {
        if (-not (Test-Path -LiteralPath $d)) { New-Item -ItemType Directory -Path $d -Force | Out-Null }
    }
    # whoami, nao USERDOMAIN\USERNAME: numa sessao SSH o Windows diz WORKGROUP
    # e o Register-ScheduledTask morre com 0x80070534.
    $usuario    = (& whoami).Trim()
    $argumentos = "-NoProfile -ExecutionPolicy Bypass -WindowStyle Hidden -File `"$PSCommandPath`" -Pasta `"$Pasta`" -Fila `"$Fila`" -AjustePdf $AjustePdf"
    if ($Sumatra) { $argumentos += " -Sumatra `"$Sumatra`"" }
    $acao    = New-ScheduledTaskAction -Execute 'powershell.exe' -Argument $argumentos
    $gatilho = New-ScheduledTaskTrigger -AtLogOn -User $usuario
    # Interactive: imprimir PDF pelo driver precisa da sessao do usuario logado.
    $dono    = New-ScheduledTaskPrincipal -UserId $usuario -LogonType Interactive
    # Sem limite de tempo (ele vigia o dia todo) e religa sozinho se cair.
    $ajustes = New-ScheduledTaskSettingsSet -StartWhenAvailable -MultipleInstances IgnoreNew `
                   -ExecutionTimeLimit ([TimeSpan]::Zero) `
                   -RestartCount 99 -RestartInterval (New-TimeSpan -Minutes 1) `
                   -AllowStartIfOnBatteries -DontStopIfGoingOnBatteries
    Register-ScheduledTask -TaskName $Tarefa -Action $acao -Trigger $gatilho `
        -Principal $dono -Settings $ajustes -Force | Out-Null
    Start-ScheduledTask -TaskName $Tarefa

    $t = Get-ScheduledTask -TaskName $Tarefa
    Registrar "[OK] Tarefa '$Tarefa' instalada ($($t.State)), no logon de $usuario."
    Registrar "     Vigiando: $entrada  ->  fila '$Fila'"
    Registrar '     Aponte o download do Chrome (ou o "Salvar como" do UpSeller) para essa pasta.'
    exit 0
}

# --------------------------------------------------------------- pre-requisitos
if (-not (Get-Command Get-Printer -ErrorAction SilentlyContinue)) {
    Registrar '[ERRO] Get-Printer indisponivel - este agente depende do modulo PrintManagement.'
    exit 1
}
$impressora = Get-Printer -Name $Fila -ErrorAction SilentlyContinue
if (-not $impressora) {
    Registrar "[ERRO] Nao existe impressora '$Fila'. Filas BIXOLON nesta maquina:"
    Get-Printer | Where-Object { $_.Name -match 'BIXOLON|Etiqueta|Codigo' -or $_.DriverName -match 'BIXOLON|BPL' } |
        ForEach-Object { Registrar "         $($_.Name)  (porta $($_.PortName))" }
    Registrar '       Use -Fila com o nome certo, ou rode 7-nomear-impressoras.ps1.'
    exit 1
}

if (-not $Sumatra) {
    $Sumatra = @(
        (Join-Path $PSScriptRoot 'SumatraPDF.exe'),
        "$env:ProgramFiles\SumatraPDF\SumatraPDF.exe",
        "${env:ProgramFiles(x86)}\SumatraPDF\SumatraPDF.exe",
        "$env:LOCALAPPDATA\SumatraPDF\SumatraPDF.exe"
    ) | Where-Object { $_ -and (Test-Path -LiteralPath $_) } | Select-Object -First 1
}

foreach ($d in @($entrada, $impressos, $comErro)) {
    if (-not (Test-Path -LiteralPath $d)) {
        if ($Simular) { Registrar "[PLANO] criar $d" } else { New-Item -ItemType Directory -Path $d -Force | Out-Null }
    }
}

# ------------------------------------------------------------------- impressao
function ImprimirRaw([string]$Arquivo) {
    if (-not ('Argos.RawNotasFiscais' -as [type])) {
        Add-Type -Namespace Argos -Name RawNotasFiscais -MemberDefinition @'
[DllImport("winspool.drv", CharSet=CharSet.Auto, SetLastError=true)]
public static extern bool OpenPrinter(string src, out IntPtr hPrinter, IntPtr pd);
[DllImport("winspool.drv", SetLastError=true)]
public static extern bool ClosePrinter(IntPtr hPrinter);
[DllImport("winspool.drv", CharSet=CharSet.Auto, SetLastError=true)]
public static extern int StartDocPrinter(IntPtr hPrinter, int level, [In, MarshalAs(UnmanagedType.LPStruct)] DOCINFO di);
[DllImport("winspool.drv", SetLastError=true)]
public static extern bool EndDocPrinter(IntPtr hPrinter);
[DllImport("winspool.drv", SetLastError=true)]
public static extern bool StartPagePrinter(IntPtr hPrinter);
[DllImport("winspool.drv", SetLastError=true)]
public static extern bool EndPagePrinter(IntPtr hPrinter);
[DllImport("winspool.drv", SetLastError=true)]
public static extern bool WritePrinter(IntPtr hPrinter, IntPtr pBytes, int count, out int written);
[StructLayout(LayoutKind.Sequential, CharSet=CharSet.Auto)]
public class DOCINFO {
    [MarshalAs(UnmanagedType.LPTStr)] public string pDocName = "ARGOS nota fiscal";
    [MarshalAs(UnmanagedType.LPTStr)] public string pOutputFile = null;
    [MarshalAs(UnmanagedType.LPTStr)] public string pDataType = "RAW";
}
'@
    }
    $bytes = [IO.File]::ReadAllBytes($Arquivo)
    $h = [IntPtr]::Zero
    if (-not [Argos.RawNotasFiscais]::OpenPrinter($Fila, [ref]$h, [IntPtr]::Zero)) {
        throw "OpenPrinter falhou para '$Fila'"
    }
    try {
        $di = New-Object Argos.RawNotasFiscais+DOCINFO
        $di.pDocName = [IO.Path]::GetFileName($Arquivo)
        if ([Argos.RawNotasFiscais]::StartDocPrinter($h, 1, $di) -eq 0) { throw 'StartDocPrinter falhou' }
        try {
            [void][Argos.RawNotasFiscais]::StartPagePrinter($h)
            $buf = [Runtime.InteropServices.Marshal]::AllocCoTaskMem($bytes.Length)
            try {
                [Runtime.InteropServices.Marshal]::Copy($bytes, 0, $buf, $bytes.Length)
                $escrito = 0
                if (-not [Argos.RawNotasFiscais]::WritePrinter($h, $buf, $bytes.Length, [ref]$escrito) -or
                    $escrito -ne $bytes.Length) {
                    throw "WritePrinter gravou $escrito de $($bytes.Length) bytes"
                }
            } finally {
                [Runtime.InteropServices.Marshal]::FreeCoTaskMem($buf)
            }
            [void][Argos.RawNotasFiscais]::EndPagePrinter($h)
        } finally {
            [void][Argos.RawNotasFiscais]::EndDocPrinter($h)
        }
    } finally {
        [void][Argos.RawNotasFiscais]::ClosePrinter($h)
    }
}

function ImprimirPdf([string]$Arquivo) {
    if (-not $Sumatra) {
        throw 'SumatraPDF nao encontrado - instale ou ponha o SumatraPDF.exe ao lado deste script'
    }
    $argsSumatra = @('-print-to', "`"$Fila`"", '-print-settings', $AjustePdf, '-silent', '-exit-when-done', "`"$Arquivo`"")
    $p = Start-Process -FilePath $Sumatra -ArgumentList $argsSumatra -Wait -PassThru -WindowStyle Hidden
    if ($p.ExitCode -ne 0) { throw "SumatraPDF saiu com codigo $($p.ExitCode)" }
}

# Um arquivo so esta pronto quando ninguem mais escreve nele: sem alteracao ha
# 2 segundos e abrivel com exclusividade.
function Pronto([IO.FileInfo]$Arq) {
    if (((Get-Date) - $Arq.LastWriteTime).TotalSeconds -lt 2) { return $false }
    try { $s = [IO.File]::Open($Arq.FullName, 'Open', 'Read', 'None'); $s.Close(); return $true }
    catch { return $false }
}

function Mover([IO.FileInfo]$Arq, [string]$Destino) {
    if (-not (Test-Path -LiteralPath $Destino)) { New-Item -ItemType Directory -Path $Destino -Force | Out-Null }
    $alvo = Join-Path $Destino $Arq.Name
    if (Test-Path -LiteralPath $alvo) { $alvo = Join-Path $Destino ("{0}_{1}" -f (Get-Date -Format 'HHmmss'), $Arq.Name) }
    Move-Item -LiteralPath $Arq.FullName -Destination $alvo
    return $alvo
}

function Rodada {
    $arquivos = @(Get-ChildItem -LiteralPath $entrada -File -ErrorAction SilentlyContinue |
        Where-Object { $ignorar -notcontains $_.Extension.ToLower() -and $_.Name -notlike '~$*' } |
        Sort-Object LastWriteTime)
    foreach ($a in $arquivos) {
        if (-not (Pronto $a)) { continue }
        $ext = $a.Extension.ToLower()
        if ($ext -ne '.pdf' -and $tiposRaw -notcontains $ext) {
            if ($Simular) { Registrar "[PLANO] $($a.Name): tipo $ext nao suportado -> Erro\"; continue }
            $foi = Mover $a $comErro
            Registrar "[ERRO] $($a.Name): tipo $ext nao suportado (so PDF, ZPL, PRN, TXT) -> $foi"
            continue
        }
        $modo = if ($ext -eq '.pdf') { "PDF via SumatraPDF ($AjustePdf)" } else { 'RAW' }
        if ($Simular) { Registrar "[PLANO] imprimir $($a.Name) em '$Fila' - $modo"; continue }
        try {
            if ($ext -eq '.pdf') { ImprimirPdf $a.FullName } else { ImprimirRaw $a.FullName }
            $null = Mover $a (Join-Path $impressos (Get-Date -Format 'yyyy-MM-dd'))
            Registrar "[OK] $($a.Name) -> '$Fila' ($modo)"
        } catch {
            $motivo = $_.Exception.Message
            try { $foi = Mover $a $comErro } catch { $foi = $a.FullName }
            Registrar "[ERRO] $($a.Name): $motivo -> $foi"
        }
    }
}

# ------------------------------------------------------------------------- laco
# Um de cada vez: a tarefa e um teste manual ao mesmo tempo imprimiriam o mesmo
# arquivo duas vezes.
$mutex = New-Object System.Threading.Mutex($false, 'Global\ArgosNotasFiscais')
if (-not $mutex.WaitOne(0)) {
    Registrar "[!] O agente ja esta rodando nesta maquina. Para testar, pare a tarefa '$Tarefa' antes."
    exit 1
}
try {
    $pdf = if ($Sumatra) { $Sumatra } else { 'NAO ENCONTRADO - PDF vai para Erro\' }
    Registrar "[..] Agente de notas fiscais: $entrada -> '$Fila' (porta $($impressora.PortName)). SumatraPDF: $pdf"
    if ($impressora.PrinterStatus -and "$($impressora.PrinterStatus)" -notin @('Normal', '0')) {
        Registrar "[!] A fila '$Fila' esta com status $($impressora.PrinterStatus)."
    }
    if ($UmaVez) {
        # Da tempo de um download recem-terminado ficar "pronto".
        Start-Sleep -Seconds 2
        Rodada
        exit 0
    }
    while ($true) {
        try { Rodada } catch { Registrar "[ERRO] rodada: $($_.Exception.Message)" }
        Start-Sleep -Seconds $Intervalo
    }
} finally {
    $mutex.ReleaseMutex()
}
