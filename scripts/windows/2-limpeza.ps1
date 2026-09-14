#Requires -Version 5.1
<#
    2-limpeza.ps1 - Libera espaco removendo caches, temporarios e restos de
    atualizacao. NAO toca em documentos, fotos, videos nem na pasta Downloads.

    Por padrao apenas SIMULA. Para agir de verdade, use -Executar.

    Uso:
      powershell -ExecutionPolicy Bypass -File .\2-limpeza.ps1              # simula
      powershell -ExecutionPolicy Bypass -File .\2-limpeza.ps1 -Executar    # limpa
      ... -Executar -DesativarHibernacao      # libera mais alguns GB
      ... -Executar -LimparComponentes        # DISM no WinSxS (demorado)
#>
[CmdletBinding()]
param(
    [switch]$Executar,
    [switch]$DesativarHibernacao,
    [switch]$LimparComponentes,
    [switch]$EsvaziarLixeira,
    [string]$Log = "$env:USERPROFILE\Desktop\limpeza-$(Get-Date -Format 'yyyyMMdd-HHmm').txt"
)

$ErrorActionPreference = 'SilentlyContinue'
$script:Linhas = New-Object System.Collections.ArrayList
$script:Liberado = [int64]0

function Escrever([string]$Texto = '') {
    Write-Host $Texto
    [void]$script:Linhas.Add($Texto)
}
function ComoGB($Bytes) { '{0,8:N2} GB' -f ($Bytes / 1GB) }
function EhAdmin {
    $id = [Security.Principal.WindowsIdentity]::GetCurrent()
    (New-Object Security.Principal.WindowsPrincipal $id).IsInRole(
        [Security.Principal.WindowsBuiltInRole]::Administrator)
}
function TamanhoPasta([string]$Caminho) {
    if (-not (Test-Path -LiteralPath $Caminho)) { return [int64]0 }
    $s = (Get-ChildItem -LiteralPath $Caminho -Recurse -File -Force |
            Measure-Object -Property Length -Sum).Sum
    if ($null -eq $s) { [int64]0 } else { [int64]$s }
}

function LimparPasta([string]$Nome, [string]$Caminho) {
    if (-not (Test-Path -LiteralPath $Caminho)) { return }
    $antes = TamanhoPasta $Caminho
    if ($antes -le 0) { return }

    if (-not $Executar) {
        Escrever ('[simular] {0,-28} liberaria {1}   {2}' -f $Nome, (ComoGB $antes), $Caminho)
        $script:Liberado += $antes
        return
    }

    Get-ChildItem -LiteralPath $Caminho -Force | ForEach-Object {
        Remove-Item -LiteralPath $_.FullName -Recurse -Force -ErrorAction SilentlyContinue
    }
    $depois = TamanhoPasta $Caminho
    $ganho  = $antes - $depois
    $script:Liberado += $ganho
    Escrever ('[limpo]   {0,-28} liberou   {1}   {2}' -f $Nome, (ComoGB $ganho), $Caminho)
}

Escrever "Limpeza - $(Get-Date -Format 'dd/MM/yyyy HH:mm')"
if (-not $Executar) {
    Escrever ''
    Escrever '>>> MODO SIMULACAO: nada sera apagado. Repita com -Executar para valer. <<<'
}
if (-not (EhAdmin)) {
    Escrever ''
    Escrever '*** Sem privilegio de administrador: os itens do Windows serao pulados.'
    Escrever '*** Feche e reabra o PowerShell com "Executar como administrador".'
}

$unidade = $env:SystemDrive
$livreAntes = (Get-Volume -DriveLetter $unidade.TrimEnd(':')).SizeRemaining
Escrever ("Espaco livre antes: {0}" -f (ComoGB $livreAntes))
Escrever ''

# ------------------------------------------------------------ do usuario
Escrever '-- Caches do usuario --'
LimparPasta 'Temp do usuario'    $env:TEMP
LimparPasta 'Cache do Edge'      "$env:LOCALAPPDATA\Microsoft\Edge\User Data\Default\Cache"
LimparPasta 'Cache do Chrome'    "$env:LOCALAPPDATA\Google\Chrome\User Data\Default\Cache"
LimparPasta 'Cache do Firefox'   "$env:LOCALAPPDATA\Mozilla\Firefox\Profiles"   # so cache; favoritos ficam em Roaming
LimparPasta 'Miniaturas'         "$env:LOCALAPPDATA\Microsoft\Windows\Explorer"
LimparPasta 'Cache de entrega'   "$env:LOCALAPPDATA\Microsoft\Windows\DeliveryOptimization"

# ------------------------------------------------------------ do sistema
if (EhAdmin) {
    Escrever ''
    Escrever '-- Itens do Windows (requer administrador) --'
    LimparPasta 'Temp do Windows'      "$env:SystemRoot\Temp"
    LimparPasta 'Relatorios de erro'   "$env:ProgramData\Microsoft\Windows\WER"
    LimparPasta 'Logs de atualizacao'  "$env:SystemRoot\Logs\CBS"

    $cacheUpdate = "$env:SystemRoot\SoftwareDistribution\Download"
    $tamUpdate = TamanhoPasta $cacheUpdate
    if ($tamUpdate -gt 0) {
        if ($Executar) {
            Escrever '          parando os servicos de atualizacao...'
            Stop-Service wuauserv, bits -Force -ErrorAction SilentlyContinue
            LimparPasta 'Cache do Windows Update' $cacheUpdate
            Start-Service wuauserv, bits -ErrorAction SilentlyContinue
            Escrever '          servicos religados.'
        } else {
            Escrever ('[simular] {0,-28} liberaria {1}   {2}' -f 'Cache do Windows Update', (ComoGB $tamUpdate), $cacheUpdate)
            $script:Liberado += $tamUpdate
        }
    }
}

# ------------------------------------------------------------- lixeira
if ($EsvaziarLixeira) {
    $tamLixeira = TamanhoPasta "$unidade\`$Recycle.Bin"
    if ($Executar) {
        Clear-RecycleBin -Force -ErrorAction SilentlyContinue
        $script:Liberado += $tamLixeira
        Escrever ('[limpo]   {0,-28} liberou   {1}' -f 'Lixeira', (ComoGB $tamLixeira))
    } else {
        Escrever ('[simular] {0,-28} liberaria {1}' -f 'Lixeira', (ComoGB $tamLixeira))
        $script:Liberado += $tamLixeira
    }
} else {
    Escrever ''
    Escrever 'Lixeira NAO incluida. Confira o conteudo dela e use -EsvaziarLixeira se quiser limpar.'
}

# --------------------------------------------------------- hibernacao
if ($DesativarHibernacao) {
    $hiber = Get-Item -LiteralPath "$unidade\hiberfil.sys" -Force
    $tamHiber = if ($hiber) { $hiber.Length } else { 0 }
    if (-not (EhAdmin)) {
        Escrever 'Hibernacao: precisa de administrador. Pulado.'
    } elseif ($Executar) {
        powercfg /hibernate off | Out-Null
        $script:Liberado += $tamHiber
        Escrever ('[limpo]   {0,-28} liberou   {1}' -f 'Hibernacao desativada', (ComoGB $tamHiber))
        Escrever '          (o modo de suspensao continua funcionando)'
    } else {
        Escrever ('[simular] {0,-28} liberaria {1}' -f 'Desativar hibernacao', (ComoGB $tamHiber))
        $script:Liberado += $tamHiber
    }
}

# ---------------------------------------------------- WinSxS / componentes
if ($LimparComponentes) {
    if (-not (EhAdmin)) {
        Escrever 'Limpeza de componentes: precisa de administrador. Pulado.'
    } elseif ($Executar) {
        Escrever ''
        Escrever 'Analisando e limpando o repositorio de componentes (pode levar 20 min)...'
        Dism.exe /Online /Cleanup-Image /StartComponentCleanup /ResetBase | Out-Null
        Escrever '[limpo]   Repositorio de componentes (WinSxS) compactado.'
        Escrever '          Atencao: com /ResetBase nao da mais para desinstalar'
        Escrever '          atualizacoes antigas do Windows.'
    } else {
        Escrever '[simular] Rodaria DISM /StartComponentCleanup /ResetBase no WinSxS.'
    }
}

# --------------------------------------------------------------- resumo
Escrever ''
Escrever ('=' * 60)
if ($Executar) {
    $livreDepois = (Get-Volume -DriveLetter $unidade.TrimEnd(':')).SizeRemaining
    Escrever ("Espaco livre depois: {0}" -f (ComoGB $livreDepois))
    Escrever ("Ganho real .........: {0}" -f (ComoGB ($livreDepois - $livreAntes)))
} else {
    Escrever ("Liberaria aproximadamente: {0}" -f (ComoGB $script:Liberado))
    Escrever ''
    Escrever 'Para executar de verdade:'
    Escrever '  .\2-limpeza.ps1 -Executar'
    Escrever 'Para incluir lixeira e hibernacao:'
    Escrever '  .\2-limpeza.ps1 -Executar -EsvaziarLixeira -DesativarHibernacao'
}

$script:Linhas | Out-File -FilePath $Log -Encoding UTF8
Write-Host ''
Write-Host "Log salvo em: $Log" -ForegroundColor Green
