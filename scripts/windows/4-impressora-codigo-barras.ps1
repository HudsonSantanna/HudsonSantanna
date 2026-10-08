#Requires -Version 5.1
<#
    4-impressora-codigo-barras.ps1 - Diagnostico e teste da impressora de
    etiquetas "Codigo de Barra" (Bixolon verde, porta USB003).

    Sem parametros: SOMENTE LEITURA. Mostra status, porta, driver, fila,
    propriedades do driver e o estado do spooler. Nao imprime nada.

    -Imprimir     envia UMA etiqueta de teste (ZPL) direto para a impressora,
                  sem passar pelo driver: tarja preta, texto e codigo de barras.
                  Escuridao e modo valem so para essa etiqueta (nada e gravado
                  na memoria da impressora; desligar e ligar volta ao normal).
    -LimparFila   cancela os trabalhos parados na fila DESTA impressora.

    TRAVA: recusa qualquer impressora na porta USB006 ou com "Fiscal" no nome.
    Etiqueta de envio so sai pela "Etiqueta Fiscal" - este script nunca a usa.

    Uso:
      powershell -ExecutionPolicy Bypass -File .\4-impressora-codigo-barras.ps1
      .\4-impressora-codigo-barras.ps1 -Imprimir -Escuro 25
      .\4-impressora-codigo-barras.ps1 -Imprimir -Escuro 25 -Modo Transferencia
      .\4-impressora-codigo-barras.ps1 -LimparFila
#>
[CmdletBinding()]
param(
    [string]$Impressora    = 'Codigo de Barra',
    [string]$PortaEsperada = 'USB003',
    [ValidateRange(0, 30)]
    [int]   $Escuro        = 25,
    [ValidateSet('Direta', 'Transferencia')]
    [string]$Modo          = 'Direta',
    [switch]$Imprimir,
    [switch]$LimparFila,
    [string]$Saida         = "$([Environment]::GetFolderPath('Desktop'))\impressora-$(Get-Date -Format 'yyyyMMdd-HHmm').txt"
)

$ErrorActionPreference = 'SilentlyContinue'
$script:Linhas = New-Object System.Collections.ArrayList
$PortaProibida = 'USB006'

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
function Salvar {
    $script:Linhas | Out-File -FilePath $Saida -Encoding UTF8
    Write-Host ''
    Write-Host "Relatorio salvo em: $Saida"
}
function Parar([string]$Motivo) {
    Escrever ''
    Escrever "*** PARADO: $Motivo"
    Salvar
    exit 1
}

Escrever "Impressora de codigo de barras - $(Get-Date -Format 'dd/MM/yyyy HH:mm')"
Escrever "Computador: $env:COMPUTERNAME   Usuario: $env:USERNAME"

# ------------------------------------------------------------------ mapa
Titulo 'IMPRESSORAS INSTALADAS (nome -> porta)'
$todas = Get-Printer
foreach ($p in ($todas | Sort-Object PortName, Name)) {
    Escrever ("{0,-10} {1,-40} {2}" -f $p.PortName, $p.Name, $p.PrinterStatus)
}

# ------------------------------------------------------------------ trava
$alvo = $todas | Where-Object { $_.Name -eq $Impressora }
if (-not $alvo) {
    Parar "nao achei a impressora '$Impressora'. Confira o nome na lista acima."
}
if ($alvo.PortName -eq $PortaProibida -or $alvo.Name -match 'Fiscal') {
    Parar "'$($alvo.Name)' esta na $($alvo.PortName) / e a fiscal. Este script nao toca nela."
}
if ($alvo.PortName -ne $PortaEsperada) {
    Parar "'$($alvo.Name)' esta na porta $($alvo.PortName), esperado $PortaEsperada. Confira o cabo antes de seguir."
}

# ------------------------------------------------------------------ detalhes
Titulo "IMPRESSORA '$($alvo.Name)'"
Escrever ("Porta ..........: {0}" -f $alvo.PortName)
Escrever ("Driver .........: {0}" -f $alvo.DriverName)
Escrever ("Status .........: {0}" -f $alvo.PrinterStatus)
Escrever ("Offline ........: {0}" -f $alvo.WorkOffline)
$cfg = Get-PrintConfiguration -PrinterName $alvo.Name
if ($cfg) { Escrever ("Papel ..........: {0}" -f $cfg.PaperSize) }

$outras = $todas | Where-Object { $_.PortName -eq $alvo.PortName -and $_.Name -ne $alvo.Name }
foreach ($o in $outras) {
    Escrever ("Mesma porta ....: {0} ({1})" -f $o.Name, $o.DriverName)
}

Titulo 'PROPRIEDADES DO DRIVER (modo de impressao, escuridao, midia)'
$props = Get-PrinterProperty -PrinterName $alvo.Name
if (-not $props) {
    Escrever 'O driver nao expoe propriedades. Confira em Preferencias de impressao.'
}
foreach ($pr in $props) {
    $marca = ''
    if ($pr.PropertyName -match 'Media|Method|Ribbon|Dark|Dens|Heat|Type|Speed') { $marca = '  <<<' }
    Escrever ("{0,-45} {1}{2}" -f $pr.PropertyName, $pr.Value, $marca)
}

Titulo 'SPOOLER E USB'
$sp = Get-Service -Name Spooler
Escrever ("Spooler ........: {0}" -f $sp.Status)
$usb = Get-PnpDevice -PresentOnly | Where-Object { $_.FriendlyName -match 'BIXOLON|SLP|XD[0-9]' }
if (-not $usb) { Escrever 'Nenhum dispositivo Bixolon presente no USB agora.' }
foreach ($u in $usb) {
    Escrever ("{0,-8} {1}" -f $u.Status, $u.FriendlyName)
}

# ------------------------------------------------------------------ fila
Titulo 'FILA'
$jobs = Get-PrintJob -PrinterName $alvo.Name
if (-not $jobs) {
    Escrever 'Fila vazia.'
} else {
    foreach ($j in $jobs) {
        Escrever ("#{0,-5} {1,-30} {2}" -f $j.Id, $j.DocumentName, $j.JobStatus)
    }
    if ($LimparFila) {
        foreach ($j in $jobs) { Remove-PrintJob -InputObject $j }
        Escrever "Fila de '$($alvo.Name)' limpa ($(@($jobs).Count) trabalho(s) cancelado(s))."
    } else {
        Escrever 'Trabalhos parados prendem a impressora. Para cancelar: -LimparFila'
    }
}

# ------------------------------------------------------------------ teste
if (-not $Imprimir) {
    Titulo 'PROXIMO PASSO'
    Escrever 'Nada foi impresso. Para a etiqueta de teste:'
    Escrever "  .\4-impressora-codigo-barras.ps1 -Imprimir -Escuro $Escuro"
    Salvar
    exit 0
}

Titulo "ETIQUETA DE TESTE (ZPL, escuro $Escuro, modo $Modo)"

Add-Type -TypeDefinition @'
using System;
using System.Runtime.InteropServices;
public static class ArgosRaw {
    [StructLayout(LayoutKind.Sequential, CharSet = CharSet.Unicode)]
    public class DOCINFO {
        public string pDocName;
        public string pOutputFile;
        public string pDataType;
    }
    [DllImport("winspool.drv", CharSet = CharSet.Unicode, SetLastError = true)]
    static extern bool OpenPrinter(string name, out IntPtr h, IntPtr def);
    [DllImport("winspool.drv", SetLastError = true)]
    static extern bool ClosePrinter(IntPtr h);
    [DllImport("winspool.drv", CharSet = CharSet.Unicode, SetLastError = true)]
    static extern int StartDocPrinter(IntPtr h, int level, [In] DOCINFO di);
    [DllImport("winspool.drv", SetLastError = true)]
    static extern bool EndDocPrinter(IntPtr h);
    [DllImport("winspool.drv", SetLastError = true)]
    static extern bool StartPagePrinter(IntPtr h);
    [DllImport("winspool.drv", SetLastError = true)]
    static extern bool EndPagePrinter(IntPtr h);
    [DllImport("winspool.drv", SetLastError = true)]
    static extern bool WritePrinter(IntPtr h, byte[] buf, int len, out int written);

    public static string Send(string printer, byte[] data) {
        IntPtr h;
        if (!OpenPrinter(printer, out h, IntPtr.Zero))
            return "OpenPrinter falhou, erro " + Marshal.GetLastWin32Error();
        try {
            DOCINFO di = new DOCINFO();
            di.pDocName = "ARGOS teste de etiqueta";
            di.pDataType = "RAW";
            if (StartDocPrinter(h, 1, di) == 0)
                return "StartDocPrinter falhou, erro " + Marshal.GetLastWin32Error();
            StartPagePrinter(h);
            int written;
            bool ok = WritePrinter(h, data, data.Length, out written);
            EndPagePrinter(h);
            EndDocPrinter(h);
            if (!ok || written != data.Length)
                return "WritePrinter falhou, enviados " + written + " de " + data.Length + " bytes";
            return "";
        } finally {
            ClosePrinter(h);
        }
    }
}
'@

# ^MTD = termica direta (etiqueta sem ribbon); ^MTT = transferencia (com ribbon).
# ~SD = escuridao 00-30. Sem ^JUS: nada fica gravado na impressora.
$mt  = if ($Modo -eq 'Direta') { 'D' } else { 'T' }
$zpl = @(
    ('~SD{0:D2}' -f $Escuro)
    '^XA'
    "^MT$mt"
    '^FO16,16^GB280,40,40^FS'
    '^FO16,66^A0N,28,28^FDTESTE ARGOS^FS'
    '^FO16,100^BY2^BCN,50,Y,N,N^FD123456^FS'
    '^PQ1'
    '^XZ'
) -join "`r`n"

$erro = [ArgosRaw]::Send($alvo.Name, [Text.Encoding]::ASCII.GetBytes($zpl + "`r`n"))
if ($erro) { Parar $erro }

Escrever 'Enviada 1 etiqueta. O que observar:'
Escrever '  - tarja preta cheia, "TESTE ARGOS" e codigo 123456 -> impressora OK;'
Escrever '    se estiver clara, repita com -Escuro 30.'
Escrever '  - letras/simbolos estranhos impressos -> a impressora nao esta em ZPL;'
Escrever '    use o autoteste (docs/07) para ver a linguagem configurada.'
Escrever '  - avancou e saiu EM BRANCO -> nao e software. Faca o autoteste e o'
Escrever '    teste da unha no papel (docs/07-impressora-codigo-barras.md).'
Salvar
