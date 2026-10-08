#Requires -Version 5.1
<#
    4-atualizar-sistema.ps1 - Atualiza o Windows (inclusive drivers, como o da
    impressora de etiquetas), os programas instalados (winget) e as assinaturas
    do antivirus.

    Por padrao apenas LISTA o que esta pendente. Para instalar, use -Executar.
    Antes de instalar, cria um ponto de restauracao.

    Uso:
      powershell -ExecutionPolicy Bypass -File .\4-atualizar-sistema.ps1              # lista
      powershell -ExecutionPolicy Bypass -File .\4-atualizar-sistema.ps1 -Executar    # instala
      ... -Executar -SemDrivers       # nao instala drivers pelo Windows Update
      ... -Executar -SemProgramas     # nao atualiza programas pelo winget
#>
[CmdletBinding()]
param(
    [switch]$Executar,
    [switch]$SemDrivers,
    [switch]$SemProgramas,
    [string]$Log = "$env:USERPROFILE\Desktop\atualizacao-$(Get-Date -Format 'yyyyMMdd-HHmm').txt"
)

$ErrorActionPreference = 'SilentlyContinue'
$script:Linhas = New-Object System.Collections.ArrayList
$script:Reiniciar = $false

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
function ReinicioPendente {
    (Test-Path 'HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Component Based Servicing\RebootPending') -or
    (Test-Path 'HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\WindowsUpdate\Auto Update\RebootRequired')
}

Escrever "Atualizacao do sistema - $(Get-Date -Format 'dd/MM/yyyy HH:mm')"
Escrever "Computador: $env:COMPUTERNAME"
if (-not $Executar) {
    Escrever ''
    Escrever '>>> MODO LISTAGEM: nada sera instalado. Repita com -Executar para valer. <<<'
}
if (-not (EhAdmin)) {
    Escrever ''
    Escrever '*** Este script precisa de administrador.'
    Escrever '*** Feche e reabra o PowerShell com "Executar como administrador".'
    exit 1
}

$so = Get-CimInstance Win32_OperatingSystem
Escrever ("Windows: {0} (build {1})" -f $so.Caption, $so.BuildNumber)

if (ReinicioPendente) {
    Escrever ''
    Escrever '*** Ja existe um reinicio pendente de atualizacoes anteriores.'
    Escrever '*** O ideal e reiniciar a maquina e rodar este script de novo.'
}

$wu = Get-Service wuauserv
if ($wu.StartType -eq 'Disabled') {
    Escrever ''
    Escrever '*** O servico Windows Update esta DESATIVADO. Reativando para buscar atualizacoes.'
    if ($Executar) { Set-Service wuauserv -StartupType Manual }
    else { Escrever '    [listar] (com -Executar o servico seria reativado)' }
}

# ------------------------------------------------------- ponto de restauracao
if ($Executar) {
    Titulo 'PONTO DE RESTAURACAO'
    Enable-ComputerRestore -Drive "$env:SystemDrive\"
    Checkpoint-Computer -Description 'Antes de 4-atualizar-sistema' -RestorePointType MODIFY_SETTINGS -ErrorAction SilentlyContinue -ErrorVariable erroPonto
    if ($erroPonto) {
        Escrever 'Nao foi possivel criar agora (o Windows so permite um a cada 24 h).'
        Escrever 'Seguindo assim mesmo: o Windows Update tambem guarda como desinstalar.'
    } else {
        Escrever 'Ponto de restauracao criado.'
    }
}

# ------------------------------------------------------------ Windows Update
Titulo 'WINDOWS UPDATE (sistema e drivers)'
Escrever 'Procurando atualizacoes... pode levar alguns minutos.'
$pendentes = @()
try {
    $sessao = New-Object -ComObject Microsoft.Update.Session
    $sessao.ClientApplicationID = '4-atualizar-sistema'
    $busca = $sessao.CreateUpdateSearcher()
    $resultado = $busca.Search('IsInstalled=0 and IsHidden=0')
    foreach ($u in $resultado.Updates) { $pendentes += $u }
} catch {
    Escrever "Falha ao consultar o Windows Update: $($_.Exception.Message)"
    Escrever 'Tente: Configuracoes -> Windows Update -> Verificar atualizacoes.'
}

# Type 2 = driver. Drivers ficam de fora so se pedido.
$escolhidos = @($pendentes | Where-Object { -not ($SemDrivers -and $_.Type -eq 2) })
if ($pendentes.Count -eq 0) {
    Escrever 'Nenhuma atualizacao pendente. Windows em dia.'
} else {
    foreach ($u in $pendentes) {
        $tipo = if ($u.Type -eq 2) { 'DRIVER ' } else { 'SISTEMA' }
        $mb   = '{0,8:N0} MB' -f ($u.MaxDownloadSize / 1MB)
        $nota = if ($SemDrivers -and $u.Type -eq 2) { '  (pulado: -SemDrivers)' } else { '' }
        Escrever ("[{0}] {1}  {2}{3}" -f $tipo, $mb, $u.Title, $nota)
    }
    Escrever ''
    Escrever ("{0} pendentes, {1} selecionadas." -f $pendentes.Count, $escolhidos.Count)
}

if ($Executar -and $escolhidos.Count -gt 0) {
    $colecao = New-Object -ComObject Microsoft.Update.UpdateColl
    foreach ($u in $escolhidos) {
        if (-not $u.EulaAccepted) { $u.AcceptEula() }
        [void]$colecao.Add($u)
    }

    Escrever ''
    Escrever 'Baixando...'
    $baixador = $sessao.CreateUpdateDownloader()
    $baixador.Updates = $colecao
    [void]$baixador.Download()

    Escrever 'Instalando... nao desligue a maquina.'
    $instalador = $sessao.CreateUpdateInstaller()
    $instalador.Updates = $colecao
    $res = $instalador.Install()

    $codigos = @{ 0 = 'nao iniciada'; 1 = 'em andamento'; 2 = 'OK'; 3 = 'OK com avisos'; 4 = 'FALHOU'; 5 = 'cancelada' }
    for ($i = 0; $i -lt $colecao.Count; $i++) {
        $r = $res.GetUpdateResult($i)
        Escrever ("  {0,-14} {1}" -f $codigos[[int]$r.ResultCode], $colecao.Item($i).Title)
    }
    if ($res.RebootRequired) { $script:Reiniciar = $true }
}

# ---------------------------------------------------------------- programas
Titulo 'PROGRAMAS (winget)'
if ($SemProgramas) {
    Escrever 'Pulado (-SemProgramas).'
} elseif (-not (Get-Command winget -ErrorAction SilentlyContinue)) {
    Escrever 'winget nao encontrado. Instale o "Instalador de Aplicativo" pela Microsoft Store'
    Escrever 'para que os programas tambem sejam atualizados por aqui.'
} else {
    $aceites = @('--accept-source-agreements', '--disable-interactivity')
    if ($Executar) {
        Escrever 'Atualizando todos os programas com versao nova disponivel...'
        Escrever '(alguns podem pedir para fechar o programa antes)'
        & winget upgrade --all --silent --accept-package-agreements @aceites | Out-Host
        Escrever ("winget terminou com codigo {0}." -f $LASTEXITCODE)
    } else {
        $saida = & winget upgrade @aceites 2>$null
        $saida | Where-Object { $_ -match '\S' -and $_ -notmatch '^[\s\-\\|/]+$' } | ForEach-Object { Escrever $_ }
    }
}

# ---------------------------------------------------------------- antivirus
Titulo 'ANTIVIRUS (Microsoft Defender)'
$mp = Get-MpComputerStatus
if (-not $mp) {
    Escrever 'Defender nao esta ativo (outro antivirus instalado?). Atualize-o pelo proprio programa.'
} else {
    Escrever ("Assinaturas de {0:dd/MM/yyyy HH:mm}" -f $mp.AntivirusSignatureLastUpdated)
    if ($Executar) {
        Update-MpSignature -ErrorAction SilentlyContinue -ErrorVariable erroMp
        if ($erroMp) { Escrever 'Nao foi possivel atualizar as assinaturas agora.' }
        else { Escrever ("Atualizado: {0:dd/MM/yyyy HH:mm}" -f (Get-MpComputerStatus).AntivirusSignatureLastUpdated) }
    }
}

# -------------------------------------------------------------------- fim
Titulo 'RESUMO'
if (-not $Executar) {
    Escrever 'Nada foi instalado. Para instalar o que foi listado:'
    Escrever '  .\4-atualizar-sistema.ps1 -Executar'
} elseif ($script:Reiniciar -or (ReinicioPendente)) {
    Escrever '*** REINICIE A MAQUINA para concluir as atualizacoes.'
    Escrever '*** Depois rode este script de novo: as vezes aparecem mais atualizacoes.'
} else {
    Escrever 'Atualizacoes concluidas, sem necessidade de reiniciar.'
}
Escrever 'Impressora de etiquetas: depois de atualizar, rode .\5-impressora-etiquetas.ps1'

$script:Linhas | Out-File -FilePath $Log -Encoding UTF8
Write-Host ''
Write-Host "Registro salvo em: $Log" -ForegroundColor Green
