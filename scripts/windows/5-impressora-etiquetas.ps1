#Requires -Version 5.1
<#
    5-impressora-etiquetas.ps1 - Diagnostico e reparo da impressora de codigo
    de barras / etiquetas (Zebra, Elgin, Argox, TSC, Honeywell, Datamax...).

    Sem parametros apenas LE e mostra: driver e versao, porta (USB ou rede),
    fila de impressao, se esta "offline", copias duplicadas da impressora.

    Uso:
      powershell -ExecutionPolicy Bypass -File .\5-impressora-etiquetas.ps1                 # diagnostico
      ... -Corrigir                       # destrava a fila e coloca a impressora online
      ... -ImprimirTeste                  # imprime UMA etiqueta de teste com codigo de barras
      ... -ImprimirTeste -Impressora "ZDesigner GC420t" -Linguagem ZPL
      ... -Impressora "Nome"              # forca qual impressora examinar

    Linguagens do teste: ZPL (Zebra), EPL (Zebra antigas LP/TLP 2844, PPLB),
    PPLA (Elgin L42, Argox), TSPL (TSC, Gainscha). Se nao reconhecer a marca,
    informe com -Linguagem. O teste nao altera configuracoes da impressora.
#>
[CmdletBinding()]
param(
    [string]$Impressora,
    [switch]$Corrigir,
    [switch]$ImprimirTeste,
    [ValidateSet('Auto', 'ZPL', 'EPL', 'PPLA', 'TSPL')]
    [string]$Linguagem = 'Auto',
    [string]$Log = "$env:USERPROFILE\Desktop\impressora-$(Get-Date -Format 'yyyyMMdd-HHmm').txt"
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
function EhAdmin {
    $id = [Security.Principal.WindowsIdentity]::GetCurrent()
    (New-Object Security.Principal.WindowsPrincipal $id).IsInRole(
        [Security.Principal.WindowsBuiltInRole]::Administrator)
}

# Nomes de modelos e drivers de impressoras de etiqueta mais comuns.
$padraoEtiqueta = 'Zebra|ZDesigner|\bG[CKX]4\d\d|\bZD\d{3}|\bZT\d{3}|\bGT8\d\d|2844|Elgin|\bL42|Argox|\bOS-2\d\d|' +
                  'Honeywell|Intermec|Datamax|\bTSC\b|\bTTP-|\bTE2\d\d|\bTDP-|Gainscha|Gprinter|Godex|' +
                  'Bematech LB|Brother QL|DYMO|Etiqueta|Label'

function LinguagemProvavel($Nome, $Driver) {
    $t = "$Nome $Driver"
    if ($t -match 'EPL|PPLB|2844')                       { return 'EPL' }
    if ($t -match 'Zebra|ZDesigner')                     { return 'ZPL' }
    if ($t -match 'Elgin|Argox|PPLA|\bL42|\bOS-2\d\d')   { return 'PPLA' }
    if ($t -match '\bTSC\b|\bTTP-|\bTE2\d\d|\bTDP-|Gainscha|Gprinter') { return 'TSPL' }
    return $null
}

function SiteDoFabricante($Texto) {
    switch -Regex ($Texto) {
        'Zebra|ZDesigner'   { return 'https://www.zebra.com/br/pt/support-downloads.html' }
        'Elgin|\bL42'       { return 'https://www.elgin.com.br (Suporte -> Downloads)' }
        'Argox'             { return 'https://www.argox.com (Support -> Download)' }
        'TSC|TTP-|TE2|TDP-' { return 'https://www.tscprinters.com (Support -> Downloads)' }
        'Honeywell|Intermec|Datamax' { return 'https://sps.honeywell.com (Support -> Software/Drivers)' }
    }
    return 'site do fabricante (area de suporte / downloads)'
}

function VersaoDriver($Valor) {
    if (-not $Valor) { return '-' }
    $v = [uint64]$Valor
    '{0}.{1}.{2}.{3}' -f (($v -shr 48) -band 0xFFFF), (($v -shr 32) -band 0xFFFF),
                         (($v -shr 16) -band 0xFFFF), ($v -band 0xFFFF)
}

# Envia bytes direto para a fila (modo RAW), sem passar pelo desenho do driver.
$codigoRaw = @'
using System;
using System.Runtime.InteropServices;
public static class ImpressaoRaw {
    [StructLayout(LayoutKind.Sequential, CharSet = CharSet.Unicode)]
    public class DOCINFO {
        [MarshalAs(UnmanagedType.LPWStr)] public string pDocName;
        [MarshalAs(UnmanagedType.LPWStr)] public string pOutputFile;
        [MarshalAs(UnmanagedType.LPWStr)] public string pDataType;
    }
    [DllImport("winspool.drv", CharSet = CharSet.Unicode, SetLastError = true)]
    static extern bool OpenPrinter(string nome, out IntPtr h, IntPtr padrao);
    [DllImport("winspool.drv", SetLastError = true)]
    static extern bool ClosePrinter(IntPtr h);
    [DllImport("winspool.drv", CharSet = CharSet.Unicode, SetLastError = true)]
    static extern int StartDocPrinter(IntPtr h, int nivel, [In] DOCINFO di);
    [DllImport("winspool.drv", SetLastError = true)]
    static extern bool EndDocPrinter(IntPtr h);
    [DllImport("winspool.drv", SetLastError = true)]
    static extern bool StartPagePrinter(IntPtr h);
    [DllImport("winspool.drv", SetLastError = true)]
    static extern bool EndPagePrinter(IntPtr h);
    [DllImport("winspool.drv", SetLastError = true)]
    static extern bool WritePrinter(IntPtr h, byte[] dados, int tamanho, out int escritos);

    public static string Enviar(string impressora, byte[] dados) {
        IntPtr h;
        if (!OpenPrinter(impressora, out h, IntPtr.Zero))
            return "nao abriu a impressora (erro " + Marshal.GetLastWin32Error() + ")";
        try {
            DOCINFO di = new DOCINFO();
            di.pDocName = "Teste de etiqueta";
            di.pDataType = "RAW";
            if (StartDocPrinter(h, 1, di) == 0)
                return "nao iniciou o documento (erro " + Marshal.GetLastWin32Error() + ")";
            int escritos = 0;
            bool ok = StartPagePrinter(h) && WritePrinter(h, dados, dados.Length, out escritos);
            EndPagePrinter(h);
            EndDocPrinter(h);
            if (!ok || escritos != dados.Length)
                return "falha ao enviar (erro " + Marshal.GetLastWin32Error() + ")";
            return null;
        } finally {
            ClosePrinter(h);
        }
    }
}
'@

function EtiquetaTeste([string]$Ling) {
    $linha2 = "$env:COMPUTERNAME $(Get-Date -Format 'dd/MM/yyyy HH:mm')"
    $cr = "`r`n"
    switch ($Ling) {
        'ZPL'  { return "^XA^FO30,30^A0N,35,35^FDTESTE DE IMPRESSAO^FS" +
                        "^FO30,75^A0N,25,25^FD$linha2^FS" +
                        "^FO30,115^BCN,70,Y,N,N^FD123456789^FS^XZ$cr" }
        'EPL'  { return $cr + "N$cr" +
                        "A30,20,0,3,1,1,N,`"TESTE DE IMPRESSAO`"$cr" +
                        "A30,55,0,2,1,1,N,`"$linha2`"$cr" +
                        "B30,90,0,1,2,4,70,B,`"123456789`"$cr" +
                        "P1$cr" }
        'TSPL' { return "CLS$cr" +
                        "TEXT 30,20,`"3`",0,1,1,`"TESTE DE IMPRESSAO`"$cr" +
                        "TEXT 30,60,`"2`",0,1,1,`"$linha2`"$cr" +
                        "BARCODE 30,100,`"128`",70,1,0,2,2,`"123456789`"$cr" +
                        "PRINT 1,1$cr" }
        # PPLA: so texto (rotacao, fonte, mult. H/V, 000, linha, coluna, dado)
        'PPLA' { return [char]2 + "L$cr" + "D11$cr" +
                        "121100000600020TESTE DE IMPRESSAO$cr" +
                        "121100000300020$linha2$cr" +
                        "E$cr" }
    }
}

Escrever "Impressora de etiquetas - $(Get-Date -Format 'dd/MM/yyyy HH:mm')"
Escrever "Computador: $env:COMPUTERNAME"
if (($Corrigir) -and -not (EhAdmin)) {
    Escrever ''
    Escrever '*** -Corrigir precisa de administrador.'
    Escrever '*** Feche e reabra o PowerShell com "Executar como administrador".'
    exit 1
}

# ------------------------------------------------------------------ spooler
Titulo 'SERVICO DE IMPRESSAO (Spooler)'
$spooler = Get-Service Spooler
Escrever ("Estado: {0}   Inicio: {1}" -f $spooler.Status, $spooler.StartType)
if ($spooler.Status -ne 'Running') {
    Escrever '^^ O spooler esta parado: nenhuma impressora funciona assim. Use -Corrigir.'
}

# ---------------------------------------------------------------- impressoras
Titulo 'IMPRESSORAS INSTALADAS'
$todas = @(Get-Printer)
foreach ($p in $todas) {
    $marca = if ("$($p.Name) $($p.DriverName)" -match $padraoEtiqueta) { '*' } else { ' ' }
    Escrever ("{0} {1,-40} {2,-12} {3}" -f $marca, $p.Name, $p.PortName, $p.DriverName)
}
Escrever ''
Escrever '* = parece impressora de etiquetas'

if ($Impressora) {
    $alvos = @($todas | Where-Object { $_.Name -eq $Impressora })
    if ($alvos.Count -eq 0) {
        Escrever ''
        Escrever "*** Nao existe impressora chamada `"$Impressora`". Copie o nome exato da lista acima."
        $script:Linhas | Out-File -FilePath $Log -Encoding UTF8
        exit 1
    }
} else {
    $alvos = @($todas | Where-Object { "$($_.Name) $($_.DriverName)" -match $padraoEtiqueta })
}

if ($alvos.Count -eq 0) {
    Escrever ''
    Escrever 'Nenhuma impressora de etiquetas encontrada.'
    Escrever '  - Confira se esta ligada e com o cabo USB/rede conectado.'
    Escrever '  - Se ela aparece na lista com outro nome, rode de novo com -Impressora "Nome".'
    Escrever '  - Se nao aparece em lugar nenhum, o driver precisa ser instalado (veja o RESUMO).'
}

# ----------------------------------------------------------------- detalhes
foreach ($p in $alvos) {
    Titulo "DETALHES: $($p.Name)"
    $drv   = Get-PrinterDriver -Name $p.DriverName
    $porta = Get-PrinterPort -Name $p.PortName
    $wmi   = Get-CimInstance Win32_Printer -Filter ("Name='{0}'" -f ($p.Name -replace "'", "''"))

    Escrever ("Driver ........: {0}" -f $p.DriverName)
    Escrever ("Versao driver .: {0}" -f (VersaoDriver $drv.DriverVersion))
    if ($drv.Manufacturer) { Escrever ("Fabricante ....: {0}" -f $drv.Manufacturer) }
    Escrever ("Porta .........: {0}" -f $p.PortName)
    Escrever ("Estado ........: {0}" -f $p.PrinterStatus)
    if ($wmi.WorkOffline) {
        Escrever '^^ Marcada como "Usar impressora offline": nada sai assim. Use -Corrigir.'
    }
    if ($p.DriverName -match 'Generic|Text Only|Somente texto') {
        Escrever '^^ Driver generico: funciona so para quem envia comandos prontos.'
        Escrever '   Para imprimir de programas comuns (Word, Bartender), instale o driver do fabricante.'
    }

    if ($porta.PrinterHostAddress) {
        $ip = $porta.PrinterHostAddress
        $responde = Test-Connection -ComputerName $ip -Count 2 -Quiet
        Escrever ("Rede ..........: {0} -> {1}" -f $ip, $(if ($responde) { 'responde' } else { 'NAO RESPONDE (cabo, IP ou impressora desligada)' }))
    } elseif ($p.PortName -match '^USB') {
        $usb = @(Get-PnpDevice -PresentOnly | Where-Object {
            $_.Class -in @('Printer', 'USB') -and $_.FriendlyName -match $padraoEtiqueta })
        if ($usb.Count -eq 0) {
            Escrever 'USB ...........: nenhum dispositivo de etiqueta conectado agora.'
            Escrever '                  Confira cabo, tomada e se a impressora esta ligada.'
        }
        foreach ($d in $usb) {
            Escrever ("USB ...........: {0} [{1}]" -f $d.FriendlyName, $d.Status)
        }
    }

    $jobs = @(Get-PrintJob -PrinterName $p.Name)
    if ($jobs.Count -gt 0) {
        Escrever ("Fila ..........: {0} trabalho(s) parado(s)" -f $jobs.Count)
        foreach ($j in $jobs) {
            Escrever ("    #{0} {1:dd/MM HH:mm} {2} - {3}" -f $j.Id, $j.SubmittedTime, $j.JobStatus, $j.DocumentName)
        }
        Escrever '^^ Fila travada costuma ser a causa de "mandei imprimir e nao saiu". Use -Corrigir.'
    } else {
        Escrever 'Fila ..........: vazia'
    }

    $ling = LinguagemProvavel $p.Name $p.DriverName
    Escrever ("Linguagem .....: {0}" -f $(if ($ling) { "$ling (provavel)" } else { 'nao identificada - informe -Linguagem no teste' }))
    Escrever ("Driver novo em : {0}" -f (SiteDoFabricante "$($p.Name) $($p.DriverName)"))
}

# Windows cria "Nome (Copia 1)" quando a impressora USB muda de porta.
$copias = @($todas | Where-Object { $_.Name -match '\((C[oó]pia|Copy) \d+\)' })
if ($copias.Count -gt 0) {
    Titulo 'COPIAS DUPLICADAS'
    foreach ($c in $copias) { Escrever ("{0}  (porta {1})" -f $c.Name, $c.PortName) }
    Escrever ''
    Escrever 'Isso acontece quando o cabo USB troca de porta. Os programas continuam'
    Escrever 'mandando para a impressora antiga (que fica offline). Solucao: deixe o cabo'
    Escrever 'sempre na mesma porta, ou aponte o programa de etiquetas para a copia que'
    Escrever 'esta "Normal" acima e remova as outras em Configuracoes -> Impressoras.'
}

# ------------------------------------------------------------------ corrigir
if ($Corrigir) {
    Titulo 'CORRECAO'
    $parados = @(Get-ChildItem "$env:SystemRoot\System32\spool\PRINTERS" -File -Force)
    Escrever ("Parando o spooler e removendo {0} arquivo(s) presos na fila..." -f $parados.Count)
    Escrever '(isso descarta trabalhos pendentes de TODAS as impressoras; mande imprimir de novo depois)'
    Stop-Service Spooler -Force
    Start-Sleep -Seconds 2
    $parados | Remove-Item -Force
    if ($spooler.StartType -eq 'Disabled') { Set-Service Spooler -StartupType Automatic }
    Start-Service Spooler
    Escrever ("Spooler: {0}" -f (Get-Service Spooler).Status)

    foreach ($p in $alvos) {
        $wmi = Get-CimInstance Win32_Printer -Filter ("Name='{0}'" -f ($p.Name -replace "'", "''"))
        if ($wmi.WorkOffline) {
            $wmi | Set-CimInstance -Property @{ WorkOffline = $false }
            Escrever ("{0}: retirada do modo offline." -f $p.Name)
        }
    }
}

# --------------------------------------------------------------------- teste
if ($ImprimirTeste) {
    Titulo 'ETIQUETA DE TESTE'
    if ($alvos.Count -ne 1) {
        Escrever ("Encontrei {0} impressoras de etiqueta. Diga qual com -Impressora `"Nome`"." -f $alvos.Count)
    } else {
        $p = $alvos[0]
        $ling = if ($Linguagem -ne 'Auto') { $Linguagem } else { LinguagemProvavel $p.Name $p.DriverName }
        if (-not $ling) {
            Escrever 'Nao sei a linguagem desta impressora. Rode de novo com -Linguagem ZPL, EPL, PPLA ou TSPL.'
            Escrever '(veja no manual ou na etiqueta de configuracao; na duvida, comece por ZPL)'
            Escrever 'Brother QL e DYMO nao usam essas linguagens: teste pelo driver, em'
            Escrever 'Configuracoes -> Impressoras -> (impressora) -> Imprimir pagina de teste.'
        } else {
            Add-Type -TypeDefinition $codigoRaw -ErrorAction Stop
            $bytes = [Text.Encoding]::ASCII.GetBytes((EtiquetaTeste $ling))
            Escrever ("Enviando teste em {0} para {1}..." -f $ling, $p.Name)
            $erro = [ImpressaoRaw]::Enviar($p.Name, $bytes)
            if ($erro) {
                Escrever "Falhou: $erro"
            } else {
                Escrever 'Enviado. Deve sair uma etiqueta com "TESTE DE IMPRESSAO" e um codigo de barras'
                Escrever '(na linguagem PPLA sai so o texto).'
                Escrever ''
                Escrever 'Saiu em branco ou com texto estranho? A linguagem esta errada: tente outra.'
                Escrever 'Saiu cortado ou pulando etiquetas? Calibre a impressora (botao FEED segurado'
                Escrever 'ou opcao "Calibrar" no driver) e confira o tamanho da etiqueta no driver.'
                Escrever 'Nao saiu nada? Rode com -Corrigir e confira se a fila esvaziou.'
            }
        }
    }
}

# -------------------------------------------------------------------- resumo
Titulo 'RESUMO'
Escrever 'Para atualizar o driver:'
Escrever '  1. .\4-atualizar-sistema.ps1 -Executar   (o Windows Update traz drivers de varias marcas)'
Escrever '  2. Se nao vier por la, baixe do site indicado em "Driver novo em" e instale.'
Escrever '     Antes de instalar, anote as configuracoes da impressora (tamanho da etiqueta,'
Escrever '     velocidade, temperatura/escurecimento) - um driver novo pode voltar ao padrao.'
Escrever '  3. Depois, rode este script com -ImprimirTeste.'

$script:Linhas | Out-File -FilePath $Log -Encoding UTF8
Write-Host ''
Write-Host "Relatorio salvo em: $Log" -ForegroundColor Green
