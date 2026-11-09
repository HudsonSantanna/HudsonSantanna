#Requires -Version 5.1
<#
    1-diagnostico.ps1 - Radiografia da maquina: espaco, saude dos discos,
    maiores pastas e arquivos, inicializacao e espaco recuperavel.

    SOMENTE LEITURA. Nao apaga nem move nada.

    Uso:
      powershell -ExecutionPolicy Bypass -File .\1-diagnostico.ps1
#>
[CmdletBinding()]
param(
    [string]$Unidade    = $env:SystemDrive,
    [int]   $TopPastas  = 20,
    [int]   $TopArquivos= 30,
    [int]   $MinimoMB   = 300,
    [string]$Saida      = "$env:USERPROFILE\Desktop\diagnostico-$(Get-Date -Format 'yyyyMMdd-HHmm').txt"
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
function ComoGB($Bytes) {
    if ($null -eq $Bytes) { return '-' }
    '{0,10:N2} GB' -f ($Bytes / 1GB)
}
function EhAdmin {
    $id = [Security.Principal.WindowsIdentity]::GetCurrent()
    (New-Object Security.Principal.WindowsPrincipal $id).IsInRole(
        [Security.Principal.WindowsBuiltInRole]::Administrator)
}

# Varre uma pasta direto pelo .NET, sem o pipeline do Get-ChildItem (que cria
# um objeto PowerShell por arquivo e e varias vezes mais lento). Nao entra em
# junctions/links simbolicos: evita laco infinito e contar a mesma pasta duas
# vezes. Pastas sem permissao sao puladas e contadas em PastasNegadas.
function Medir {
    param(
        [string]$Caminho,
        [int64] $LimiteGrande = -1,   # >= 0: guarda arquivos deste tamanho para cima
        [switch]$PorTopo,             # soma por pasta de primeiro nivel
        [int64] $AvisoACada   = 0     # imprime progresso a cada N arquivos
    )
    $raiz = New-Object System.IO.DirectoryInfo $Caminho
    if (-not $raiz.Exists) { return $null }

    $reparse  = [System.IO.FileAttributes]::ReparsePoint
    $bytes    = [int64]0
    $arquivos = [int64]0
    $negadas  = 0
    $porTopo  = @{}
    $grandes  = New-Object System.Collections.ArrayList
    $proximo  = $AvisoACada
    $pilha    = New-Object System.Collections.Stack
    $pilha.Push(@($raiz, ''))

    while ($pilha.Count -gt 0) {
        $par  = $pilha.Pop()
        $dir  = $par[0]
        $topo = $par[1]
        try { $entradas = $dir.GetFileSystemInfos() } catch { $negadas++; continue }

        $soma = [int64]0
        foreach ($e in $entradas) {
            if ($e -is [System.IO.DirectoryInfo]) {
                if (($e.Attributes -band $reparse) -eq 0) {
                    $t = if ($topo) { $topo } else { $e.Name }
                    $pilha.Push(@($e, $t))
                }
                continue
            }
            $tam = $e.Length
            $soma += $tam
            $arquivos++
            if ($LimiteGrande -ge 0 -and $tam -ge $LimiteGrande) {
                [void]$grandes.Add([pscustomobject]@{
                    Tamanho    = $tam
                    Modificado = $e.LastWriteTime
                    Caminho    = $e.FullName
                })
            }
            # arquivos soltos na raiz (pagefile.sys, hiberfil.sys) entram pelo nome
            if ($PorTopo -and -not $topo) { $porTopo[$e.Name] = $tam }
        }
        $bytes += $soma
        if ($PorTopo -and $topo) { $porTopo[$topo] += $soma }

        if ($AvisoACada -gt 0 -and $arquivos -ge $proximo) {
            Write-Host "  ... $arquivos arquivos lidos"
            $proximo += $AvisoACada
        }
    }

    [pscustomobject]@{
        Bytes         = $bytes
        Arquivos      = $arquivos
        PastasNegadas = $negadas
        PorTopo       = $porTopo
        Grandes       = $grandes
    }
}
function TamanhoPasta([string]$Caminho) {
    $m = Medir $Caminho
    if ($m) { $m.Bytes } else { $null }
}

Escrever "Diagnostico da maquina - $(Get-Date -Format 'dd/MM/yyyy HH:mm')"
Escrever "Computador: $env:COMPUTERNAME   Usuario: $env:USERNAME"
if (-not (EhAdmin)) {
    Escrever ''
    Escrever '*** Rodando SEM privilegio de administrador. Alguns dados (SMART,'
    Escrever '*** pontos de restauracao, WinSxS) podem aparecer incompletos.'
}

# ------------------------------------------------------------------ sistema
Titulo 'SISTEMA'
$so  = Get-CimInstance Win32_OperatingSystem
$cs  = Get-CimInstance Win32_ComputerSystem
$cpu = Get-CimInstance Win32_Processor | Select-Object -First 1
Escrever ("Modelo .........: {0} {1}" -f $cs.Manufacturer, $cs.Model)
Escrever ("Windows ........: {0} (build {1})" -f $so.Caption, $so.BuildNumber)
Escrever ("Processador ....: {0}" -f $cpu.Name)
Escrever ("Memoria RAM ....: {0}" -f (ComoGB $cs.TotalPhysicalMemory))
Escrever ("RAM livre ......: {0}" -f (ComoGB ($so.FreePhysicalMemory * 1KB)))
Escrever ("Ligado desde ...: {0}" -f $so.LastBootUpTime)

# ------------------------------------------------------------------ volumes
Titulo 'VOLUMES'
Escrever ('{0,-6} {1,-16} {2,14} {3,14} {4,8}' -f 'Letra','Rotulo','Tamanho','Livre','Uso')
foreach ($v in (Get-Volume | Where-Object { $_.DriveLetter } | Sort-Object DriveLetter)) {
    $uso = if ($v.Size -gt 0) { '{0,6:N1}%' -f ((1 - $v.SizeRemaining / $v.Size) * 100) } else { '-' }
    Escrever ('{0,-6} {1,-16} {2,14} {3,14} {4,8}' -f `
        "$($v.DriveLetter):", $v.FileSystemLabel, (ComoGB $v.Size), (ComoGB $v.SizeRemaining), $uso)
    if ($v.Size -gt 0 -and ($v.SizeRemaining / $v.Size) -lt 0.10) {
        Escrever "       ^^ ATENCAO: menos de 10% livre neste volume."
    }
}

# ------------------------------------------------------------ saude fisica
Titulo 'SAUDE DOS DISCOS'
$discos = Get-PhysicalDisk
if ($discos) {
    foreach ($d in $discos) {
        Escrever ("{0} | {1} | {2} | Saude: {3} | Estado: {4}" -f `
            $d.FriendlyName, $d.MediaType, (ComoGB $d.Size).Trim(), $d.HealthStatus, $d.OperationalStatus)
        $rc = $d | Get-StorageReliabilityCounter
        if ($rc) {
            Escrever ("    Horas ligado: {0} | Desgaste: {1} | Temp: {2} C | Erros leitura: {3} | Erros escrita: {4}" -f `
                $rc.PowerOnHours, $rc.Wear, $rc.Temperature, $rc.ReadErrorsTotal, $rc.WriteErrorsTotal)
        }
        if ($d.HealthStatus -ne 'Healthy') {
            Escrever '    ^^ DISCO COM PROBLEMA: faca backup antes de qualquer limpeza.'
        }
    }
} else {
    Escrever 'Nao foi possivel ler os discos fisicos (requer administrador).'
}

# --------------------------------------------------- espaco recuperavel
Titulo 'ESPACO RECUPERAVEL (candidatos a limpeza)'
$candidatos = [ordered]@{
    'Lixeira'                  = "$Unidade\`$Recycle.Bin"
    'Temp do usuario'          = $env:TEMP
    'Temp do Windows'          = "$env:SystemRoot\Temp"
    'Cache do Windows Update'  = "$env:SystemRoot\SoftwareDistribution\Download"
    'Relatorios de erro'       = "$env:ProgramData\Microsoft\Windows\WER"
    'Downloads'                = "$env:USERPROFILE\Downloads"
    'Cache do Edge'            = "$env:LOCALAPPDATA\Microsoft\Edge\User Data\Default\Cache"
    'Cache do Chrome'          = "$env:LOCALAPPDATA\Google\Chrome\User Data\Default\Cache"
    'Miniaturas/Explorer'      = "$env:LOCALAPPDATA\Microsoft\Windows\Explorer"
}
$totalRecuperavel = 0
foreach ($nome in $candidatos.Keys) {
    $tam = TamanhoPasta $candidatos[$nome]
    if ($null -ne $tam -and $tam -gt 0) {
        $totalRecuperavel += $tam
        Escrever ('{0,-26} {1}   {2}' -f $nome, (ComoGB $tam), $candidatos[$nome])
    }
}
foreach ($arq in @("$Unidade\hiberfil.sys", "$Unidade\pagefile.sys", "$Unidade\swapfile.sys")) {
    $item = Get-Item -LiteralPath $arq -Force
    if ($item) { Escrever ('{0,-26} {1}   (arquivo de sistema)' -f (Split-Path $arq -Leaf), (ComoGB $item.Length)) }
}
Escrever ''
Escrever ("Soma dos caches e temporarios: {0}" -f (ComoGB $totalRecuperavel))
Escrever 'Obs.: Downloads e Lixeira podem conter coisa que voce quer guardar - confira antes.'

$pontos = Get-ComputerRestorePoint
if ($pontos) {
    Escrever ''
    Escrever "Pontos de restauracao: $($pontos.Count) (o mais antigo pode ser descartado)"
}

# ------------------------------------------------- varredura do disco
Titulo "MAIORES PASTAS E ARQUIVOS EM $Unidade"
Escrever 'Varrendo o disco... aguarde.'
$inicio    = Get-Date
$varredura = Medir "$Unidade\" -LimiteGrande ($MinimoMB * 1MB) -PorTopo -AvisoACada 100000
$porPasta  = $varredura.PorTopo
$grandes   = $varredura.Grandes
Escrever ("Varredura concluida: {0} arquivos em {1:N1} minutos." -f `
    $varredura.Arquivos, ((Get-Date) - $inicio).TotalMinutes)
if ($varredura.PastasNegadas -gt 0) {
    Escrever ("({0} pastas sem permissao de leitura foram puladas.)" -f $varredura.PastasNegadas)
}

Escrever ''
Escrever "-- $TopPastas maiores pastas de primeiro nivel --"
$porPasta.GetEnumerator() | Sort-Object Value -Descending | Select-Object -First $TopPastas | ForEach-Object {
    Escrever ('{0}   {1}' -f (ComoGB $_.Value), $_.Key)
}

Escrever ''
Escrever "-- $TopArquivos maiores arquivos (acima de $MinimoMB MB) --"
$grandes | Sort-Object Tamanho -Descending | Select-Object -First $TopArquivos | ForEach-Object {
    Escrever ('{0}  {1:dd/MM/yyyy}  {2}' -f (ComoGB $_.Tamanho), $_.Modificado, $_.Caminho)
}

Escrever ''
Escrever "-- Candidatos a mover para o HD externo (grandes E sem alteracao ha mais de 1 ano) --"
$corte = (Get-Date).AddYears(-1)
$antigos = $grandes | Where-Object { $_.Modificado -lt $corte } | Sort-Object Tamanho -Descending
if ($antigos) {
    $somaAntigos = ($antigos | Measure-Object -Property Tamanho -Sum).Sum
    $antigos | Select-Object -First $TopArquivos | ForEach-Object {
        Escrever ('{0}  {1:dd/MM/yyyy}  {2}' -f (ComoGB $_.Tamanho), $_.Modificado, $_.Caminho)
    }
    Escrever ''
    Escrever ("Total nesses arquivos antigos: {0}" -f (ComoGB $somaAntigos))
} else {
    Escrever 'Nenhum arquivo grande e antigo encontrado.'
}

# ------------------------------------------------------- pastas do perfil
Titulo 'PASTAS DO SEU PERFIL'
foreach ($p in @('Desktop','Documents','Downloads','Pictures','Videos','Music','OneDrive')) {
    $caminho = Join-Path $env:USERPROFILE $p
    $tam = TamanhoPasta $caminho
    if ($null -ne $tam) { Escrever ('{0,-14} {1}' -f $p, (ComoGB $tam)) }
}

# ------------------------------------------------------------ programas
Titulo 'PROGRAMAS INSTALADOS (por tamanho estimado)'
$chaves = @(
    'HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Uninstall\*',
    'HKLM:\SOFTWARE\WOW6432Node\Microsoft\Windows\CurrentVersion\Uninstall\*'
)
Get-ItemProperty $chaves |
    Where-Object { $_.DisplayName -and $_.EstimatedSize } |
    Sort-Object EstimatedSize -Descending |
    Select-Object -First 25 |
    ForEach-Object {
        Escrever ('{0,10:N2} GB  {1}' -f ($_.EstimatedSize / 1MB), $_.DisplayName)
    }

# --------------------------------------------------------- inicializacao
Titulo 'PROGRAMAS QUE INICIAM COM O WINDOWS'
Get-CimInstance Win32_StartupCommand | ForEach-Object {
    Escrever ('{0,-34} {1}' -f $_.Name, $_.Command)
}
Escrever ''
Escrever 'Para desativar o que nao usa: Ctrl+Shift+Esc -> aba Aplicativos de Inicializacao.'

# -------------------------------------------------------------- resumo
Titulo 'RESUMO'
$vol = Get-Volume -DriveLetter $Unidade.TrimEnd(':')
if ($vol) {
    Escrever ("Volume {0}: {1} livres de {2}" -f $Unidade, (ComoGB $vol.SizeRemaining), (ComoGB $vol.Size))
}
Escrever ("Limpeza automatica pode liberar aproximadamente: {0}" -f (ComoGB $totalRecuperavel))
Escrever ''
Escrever 'Proximos passos:'
Escrever '  1. Leia este relatorio e marque o que quer preservar.'
Escrever '  2. Rode  2-limpeza.ps1  (primeiro sem parametros: ele so simula).'
Escrever '  3. Use   3-mover-para-hd.ps1  para tirar do PC o que for grande e antigo.'

$script:Linhas | Out-File -FilePath $Saida -Encoding UTF8
Write-Host ''
Write-Host "Relatorio salvo em: $Saida" -ForegroundColor Green
