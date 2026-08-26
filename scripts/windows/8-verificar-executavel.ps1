#Requires -Version 5.1
<#
    8-verificar-executavel.ps1 - Descobre por que o Windows recusa um programa
    com "Este aplicativo nao pode ser executado em seu PC".

    Essa mensagem nao diz o motivo, e os motivos sao bem diferentes entre si:
    arquitetura incompativel, arquivo truncado no download, arquivo que nem e
    executavel, ou bloqueio por politica. O script le o cabecalho PE do arquivo
    e compara com a maquina - e ai a resposta deixa de ser palpite.

    SOMENTE LEITURA. Nao instala, nao apaga, nao desbloqueia nada. Se algo tiver
    de ser mudado, ele diz o comando e voce decide.

    Uso:
      powershell -ExecutionPolicy Bypass -File .\8-verificar-executavel.ps1
      powershell -ExecutionPolicy Bypass -File .\8-verificar-executavel.ps1 -Caminho 'C:\algum\programa.exe'
#>
[CmdletBinding()]
param(
    [string[]]$Caminho
)

$ErrorActionPreference = 'SilentlyContinue'

function Titulo([string]$T) {
    Write-Host ''
    Write-Host ('=' * 72)
    Write-Host "  $T"
    Write-Host ('=' * 72)
}
function OK([string]$T)    { Write-Host "  [OK]     $T" }
function Falta([string]$T) { Write-Host "  [PROBLEMA] $T" }
function Aviso([string]$T) { Write-Host "  [!]      $T" }
function Linha([string]$T) { Write-Host "  $T" }

Write-Host ''
Write-Host "ARGOS - por que o programa nao executa  $(Get-Date -Format 'dd/MM/yyyy HH:mm')"
Write-Host 'SOMENTE LEITURA - nada nesta maquina e alterado por este script.'

# ------------------------------------------------------------- 0. esta maquina
Titulo '0. ESTA MAQUINA'
$os     = Get-CimInstance Win32_OperatingSystem
$cs     = Get-CimInstance Win32_ComputerSystem
$archOS = $env:PROCESSOR_ARCHITECTURE
# PROCESSOR_ARCHITECTURE mente dentro de um PowerShell 32 bits: nele vem x86
# mesmo num Windows 64. O W6432 so existe nesse caso, e ai e ele que vale.
if ($env:PROCESSOR_ARCHITEW6432) { $archOS = $env:PROCESSOR_ARCHITEW6432 }

Linha "Nome .............: $env:COMPUTERNAME"
Linha "Windows ..........: $($os.Caption) $($os.Version)"
Linha "Arquitetura do SO : $archOS  ($($os.OSArchitecture))"
Linha "Modelo ...........: $($cs.Manufacturer) $($cs.Model)"
Linha "PowerShell .......: $($PSVersionTable.PSVersion)  (processo de $(if ([Environment]::Is64BitProcess) {'64'} else {'32'}) bits)"

if (-not [Environment]::Is64BitOperatingSystem) {
    Aviso 'Windows de 32 bits. Programa de 64 bits NAO roda aqui - e a causa mais comum desta mensagem.'
}

# ------------------------------------------------------------- quais arquivos
if (-not $Caminho -or $Caminho.Count -eq 0) {
    # Sem caminho informado, olhar os suspeitos conhecidos deste parque.
    $Caminho = @(
        "$env:USERPROFILE\Scripts\ArgosPrint.exe",
        "$env:USERPROFILE\ArgosPrint\ArgosPrint.exe",
        'C:\ArgosPrint\ArgosPrint.exe',
        'C:\Argos\ArgosPrint.exe'
    ) | Where-Object { Test-Path -LiteralPath $_ }

    if ($Caminho.Count -eq 0) {
        Titulo 'NENHUM ARQUIVO PARA CONFERIR'
        Write-Host '  Nao achei o ArgosPrint.exe nos lugares conhecidos, e voce nao informou'
        Write-Host '  um caminho. Rode apontando para o programa que da a mensagem:'
        Write-Host ''
        Write-Host "     .\8-verificar-executavel.ps1 -Caminho 'C:\caminho\do\programa.exe'"
        Write-Host ''
        Write-Host '  Para descobrir o caminho: clique com o botao direito no atalho que'
        Write-Host '  falha -> Propriedades -> campo "Destino".'
        Write-Host ''
        exit 0
    }
    Aviso "nenhum -Caminho informado; conferindo o(s) $($Caminho.Count) executavel(is) conhecido(s)"
}

# Nomes das arquiteturas no cabecalho PE. Ver IMAGE_FILE_HEADER.Machine.
$maquinas = @{
    0x014C = 'x86 (32 bits)'
    0x8664 = 'x64 (64 bits)'
    0xAA64 = 'ARM64'
    0x01C4 = 'ARM (32 bits)'
    0x0200 = 'Itanium'
}

foreach ($arq in $Caminho) {
    Titulo "ARQUIVO: $arq"

    if (-not (Test-Path -LiteralPath $arq)) {
        Falta 'o arquivo nao existe neste caminho'
        Linha 'Confira a grafia, e se ele nao foi movido ou apagado por antivirus.'
        continue
    }

    $item = Get-Item -LiteralPath $arq -Force
    if ($item.PSIsContainer) {
        Falta 'isto e uma PASTA, nao um arquivo'
        Linha 'Aponte para o .exe dentro dela.'
        continue
    }
    Linha "Tamanho ..........: $([math]::Round($item.Length / 1KB, 1)) KB  ($($item.Length) bytes)"
    Linha "Modificado .......: $($item.LastWriteTime)"

    if ($item.Length -eq 0) {
        Falta 'arquivo com ZERO byte - o download nao trouxe nada'
        Linha 'Baixe de novo. Um .exe vazio da exatamente esta mensagem.'
        continue
    }
    if ($item.Length -lt 4096) {
        Aviso 'arquivo muito pequeno para um programa - pode ser download interrompido'
    }

    # ---------------------------------------------------------- cabecalho PE
    # Todo executavel do Windows comeca com "MZ"; em 0x3C fica o deslocamento do
    # cabecalho "PE\0\0", e logo depois dele vem o campo Machine, que diz para
    # qual arquitetura o programa foi compilado.
    $cab = New-Object byte[] 1024
    $lidos = 0
    try {
        $fs = [IO.File]::Open($arq, 'Open', 'Read', 'ReadWrite')
        try { $lidos = $fs.Read($cab, 0, $cab.Length) } finally { $fs.Dispose() }
    } catch {
        Falta "nao consegui ler o arquivo: $($_.Exception.Message)"
        Linha 'Pode estar em uso, sem permissao, ou em pasta protegida.'
        continue
    }

    if ($lidos -lt 64 -or $cab[0] -ne 0x4D -or $cab[1] -ne 0x5A) {
        Falta 'nao comeca com "MZ" - isto NAO e um executavel do Windows'
        Linha 'Pode ser um instalador baixado pela metade, uma pagina de erro HTML'
        Linha 'salva com nome .exe, ou um arquivo de outro sistema (Linux/Mac).'
        $texto = [Text.Encoding]::ASCII.GetString($cab, 0, [Math]::Min(120, $lidos))
        Linha "Primeiros bytes como texto: $($texto -replace '[^\x20-\x7E]', '.')"
        continue
    }
    OK 'comeca com "MZ" - e um executavel do Windows'

    $peOff = [BitConverter]::ToInt32($cab, 0x3C)
    if ($peOff -le 0 -or ($peOff + 26) -ge $lidos) {
        Falta 'cabecalho PE fora do alcance - arquivo truncado ou corrompido'
        Linha 'Baixe de novo, de preferencia conferindo o tamanho na origem.'
        continue
    }
    if ($cab[$peOff] -ne 0x50 -or $cab[$peOff + 1] -ne 0x45) {
        Falta 'assinatura "PE" ausente - arquivo corrompido'
        continue
    }

    $machine = [BitConverter]::ToUInt16($cab, $peOff + 4)
    $caract  = [BitConverter]::ToUInt16($cab, $peOff + 22)
    $ehDll   = ($caract -band 0x2000) -ne 0
    $nomeArq = if ($maquinas.ContainsKey([int]$machine)) { $maquinas[[int]$machine] }
               else { "desconhecida (0x{0:X4})" -f $machine }

    Linha "Compilado para ...: $nomeArq"
    if ($ehDll) {
        Falta 'este arquivo e uma DLL, nao um programa - DLL nao se executa direto'
        continue
    }

    # ------------------------------------------------- compatibilidade real
    $compativel = $null
    switch ($archOS) {
        'AMD64' { $compativel = ($machine -eq 0x8664 -or $machine -eq 0x014C) }
        'x86'   { $compativel = ($machine -eq 0x014C) }
        'ARM64' { $compativel = ($machine -eq 0xAA64 -or $machine -eq 0x014C -or $machine -eq 0x8664) }
        default { $compativel = $null }
    }

    if ($compativel -eq $true) {
        OK "compativel com este Windows ($archOS)"
    } elseif ($compativel -eq $false) {
        Falta "INCOMPATIVEL: programa $nomeArq num Windows $archOS"
        if ($archOS -eq 'x86' -and $machine -eq 0x8664) {
            Linha 'ESTA E A CAUSA. Windows de 32 bits nao executa programa de 64 bits.'
            Linha 'Peca ao fornecedor a versao 32 bits (x86), ou rode noutra maquina.'
        } else {
            Linha 'Peca ao fornecedor a versao para esta arquitetura.'
        }
    } else {
        Aviso "nao sei julgar compatibilidade para arquitetura de SO '$archOS'"
    }

    # ------------------------------------------------------ marca de download
    # Arquivo vindo da internet carrega a marca de zona. Ela costuma dar outra
    # mensagem, mas aparece junto com esta o bastante para valer o aviso.
    $zona = Get-Item -LiteralPath $arq -Stream 'Zone.Identifier' -ErrorAction SilentlyContinue
    if ($zona) {
        Aviso 'arquivo marcado como vindo da internet (Zone.Identifier presente)'
        Linha "Para liberar:  Unblock-File -LiteralPath '$arq'"
    } else {
        OK 'sem marca de bloqueio de download'
    }

    # ------------------------------------------------------------- assinatura
    $ass = Get-AuthenticodeSignature -LiteralPath $arq -ErrorAction SilentlyContinue
    if ($ass) {
        Linha "Assinatura .......: $($ass.Status)"
        if ($ass.SignerCertificate) { Linha "Assinado por .....: $($ass.SignerCertificate.Subject)" }
        if ($ass.Status -eq 'HashMismatch') {
            Falta 'a assinatura nao bate com o conteudo - arquivo ALTERADO ou corrompido apos assinado'
        }
    }
}

# ----------------------------------------------------------------- politicas
Titulo 'BLOQUEIO POR POLITICA'
# AppLocker e WDAC recusam com mensagem parecida. So a presenca da politica ja
# muda o rumo da investigacao, mesmo sem saber a regra exata.
$temPolitica = $false

$appLocker = Get-ChildItem 'HKLM:\SOFTWARE\Policies\Microsoft\Windows\SrpV2' -ErrorAction SilentlyContinue
if ($appLocker) {
    $temPolitica = $true
    Aviso 'AppLocker configurado nesta maquina - pode estar recusando o programa'
    Linha 'Veja: Get-AppLockerPolicy -Effective -Xml'
}

$srp = Get-ItemProperty 'HKLM:\SOFTWARE\Policies\Microsoft\Windows\Safer\CodeIdentifiers' -ErrorAction SilentlyContinue
if ($srp -and $null -ne $srp.DefaultLevel -and $srp.DefaultLevel -ne 262144) {
    $temPolitica = $true
    Aviso "Politica de Restricao de Software ativa (DefaultLevel=$($srp.DefaultLevel))"
}

$si = Get-CimInstance -ClassName Win32_DeviceGuard -Namespace 'root\Microsoft\Windows\DeviceGuard' -ErrorAction SilentlyContinue
if ($si -and $si.CodeIntegrityPolicyEnforcementStatus -gt 0) {
    $temPolitica = $true
    Aviso "Integridade de Codigo (WDAC) em modo $($si.CodeIntegrityPolicyEnforcementStatus)"
}

if (-not $temPolitica) { OK 'nenhuma politica de bloqueio de aplicativo encontrada' }

# Defender pode ter movido o arquivo para a quarentena - dai o "nao existe".
$def = Get-MpComputerStatus -ErrorAction SilentlyContinue
if ($def) {
    Linha ''
    Linha "Defender tempo real: $($def.RealTimeProtectionEnabled)"
    $ameacas = @(Get-MpThreatDetection -ErrorAction SilentlyContinue | Sort-Object InitialDetectionTime -Descending | Select-Object -First 3)
    if ($ameacas.Count -gt 0) {
        Aviso 'o Defender detectou algo recentemente - confira se nao levou o programa:'
        foreach ($a in $ameacas) { Linha "   $($a.InitialDetectionTime)  $($a.Resources -join ' ')" }
    }
}

# -------------------------------------------------------------------- resumo
Titulo 'COMO LER ISTO'
Write-Host '  "Este aplicativo nao pode ser executado em seu PC" nao diz o motivo.'
Write-Host '  Os motivos, na ordem em que aparecem na pratica:'
Write-Host ''
Write-Host '  1. Programa de 64 bits num Windows de 32 bits (ou ARM x Intel)'
Write-Host '     -> a secao do arquivo acima mostra "INCOMPATIVEL"'
Write-Host '  2. Download interrompido: arquivo vazio, truncado, ou sem "MZ"'
Write-Host '     -> baixar de novo resolve'
Write-Host '  3. Nao e programa: DLL, instalador pela metade, pagina de erro salva como .exe'
Write-Host '  4. Bloqueio por politica (AppLocker / WDAC) ou quarentena do antivirus'
Write-Host ''
Write-Host '  Se tudo acima estiver [OK] e a mensagem persistir, mande este relatorio'
Write-Host '  inteiro junto com o nome do programa e de onde ele foi baixado.'
Write-Host ''
