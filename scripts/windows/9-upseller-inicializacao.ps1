#Requires -Version 5.1
<#
    9-upseller-inicializacao.ps1 - Tira o agente de impressao do UpSeller da
    inicializacao do Windows, com backup e volta.

    O QUE ISTO RESOLVE: na HUDSONINTEGRAR o agente local do UpSeller sobe com o
    Windows e disputa a BIXOLON 'Etiqueta Fiscal' com o agente Argos, que passa
    a imprimir as etiquetas de envio e os DANFEs (veja
    docs/18-argos-imprime-notas-fiscais.md).

    O QUE ISTO NAO FAZ, POR CONSTRUCAO:
      - nao desinstala o UpSeller nem apaga arquivo nenhum;
      - nao encosta em impressora, fila, driver ou impressora padrao;
      - nao mexe no site app.upseller.com: a EMISSAO da NF-e continua la.
    Desligar e o mesmo que o "Desabilitar" do Gerenciador de Tarefas (aba
    Inicializar): a entrada continua existindo, so nao sobe mais sozinha. O
    UpSeller ainda abre se alguem clicar no atalho.

    Onde ele procura (tudo que casar com -Padrao no nome, caminho ou comando):
      - chaves Run (usuario e maquina, 32 e 64 bits)
      - pastas Inicializar (usuario e todos os usuarios)
      - tarefas agendadas
      - servicos do Windows
    E mostra os processos rodando, com as portas que eles escutam.

    Uso:
      # 1. so olhar (padrao - nao muda nada)
      powershell -ExecutionPolicy Bypass -File .\9-upseller-inicializacao.ps1

      # 2. desligar da inicializacao (faz backup antes)
      powershell -ExecutionPolicy Bypass -File .\9-upseller-inicializacao.ps1 -Desligar -Confirmar

      #    ... e tambem fechar o que esta rodando agora
      powershell -ExecutionPolicy Bypass -File .\9-upseller-inicializacao.ps1 -Desligar -Encerrar -Confirmar

      # 3. voltar como estava (usa o backup mais recente)
      powershell -ExecutionPolicy Bypass -File .\9-upseller-inicializacao.ps1 -Religar -Confirmar

    Chaves de maquina (HKLM), pasta de todos os usuarios e servicos exigem o
    PowerShell aberto como administrador; sem isso eles sao listados e pulados.
#>
[CmdletBinding()]
param(
    [string]$Padrao      = 'upseller',
    [switch]$Desligar,
    [switch]$Religar,
    [switch]$Encerrar,
    [switch]$Confirmar,
    [string]$Checkpoint,
    [string]$Checkpoints = 'C:\Argos-Backups\_checkpoints'
)

$ErrorActionPreference = 'Stop'

function Titulo([string]$T) {
    Write-Host ''
    Write-Host ('=' * 72)
    Write-Host "  $T"
    Write-Host ('=' * 72)
}
function OK([string]$T)    { Write-Host "  [OK]    $T" }
function Erro([string]$T)  { Write-Host "  [ERRO]  $T" }
function Aviso([string]$T) { Write-Host "  [!]     $T" }
function Plano([string]$T) { Write-Host "  [PLANO] $T" }

if ($Desligar -and $Religar) { Erro 'Use -Desligar OU -Religar, nao os dois.'; exit 1 }

$ehAdmin = ([Security.Principal.WindowsPrincipal][Security.Principal.WindowsIdentity]::GetCurrent()).IsInRole(
    [Security.Principal.WindowsBuiltInRole]::Administrator)

Write-Host ''
Write-Host "ARGOS - UpSeller na inicializacao  $(Get-Date -Format 'dd/MM/yyyy HH:mm')  maquina=$env:COMPUTERNAME  admin=$ehAdmin"

# StartupApproved e onde o Gerenciador de Tarefas guarda o liga/desliga de cada
# item de inicializacao. 12 bytes: o primeiro par e o estado (02 = ligado,
# 03 = desligado), o resto e o carimbo de quando foi desligado.
$bytesLigado    = [byte[]](2,0,0,0,0,0,0,0,0,0,0,0)
function BytesDesligado {
    $b = [byte[]](3,0,0,0,0,0,0,0,0,0,0,0)
    [BitConverter]::GetBytes([DateTime]::Now.ToFileTime()).CopyTo($b, 4)
    return $b
}

$aprovado = 'Software\Microsoft\Windows\CurrentVersion\Explorer\StartupApproved'
$fontesRun = @(
    @{ Raiz = 'HKCU'; Run = 'Software\Microsoft\Windows\CurrentVersion\Run';             Aprov = "$aprovado\Run" },
    @{ Raiz = 'HKLM'; Run = 'SOFTWARE\Microsoft\Windows\CurrentVersion\Run';             Aprov = "$aprovado\Run" },
    @{ Raiz = 'HKLM'; Run = 'SOFTWARE\WOW6432Node\Microsoft\Windows\CurrentVersion\Run'; Aprov = "$aprovado\Run32" }
)

function Casa([string[]]$Textos) {
    foreach ($t in $Textos) { if ($t -and $t -match [regex]::Escape($Padrao)) { return $true } }
    return $false
}

function EstadoAprovado([string]$Raiz, [string]$Chave, [string]$Nome) {
    $v = (Get-ItemProperty -LiteralPath "${Raiz}:\$Chave" -Name $Nome -ErrorAction SilentlyContinue).$Nome
    if ($null -eq $v -or $v.Length -eq 0) { return 'ligado' }
    if (($v[0] -band 1) -eq 1) { return 'desligado' }
    return 'ligado'
}

function AlvoAtalho([string]$Lnk) {
    try { return (New-Object -ComObject WScript.Shell).CreateShortcut($Lnk).TargetPath } catch { return '' }
}

# ------------------------------------------------------------------- inventario
$itens = New-Object System.Collections.Generic.List[object]

foreach ($f in $fontesRun) {
    $caminho = "$($f.Raiz):\$($f.Run)"
    $props = Get-ItemProperty -LiteralPath $caminho -ErrorAction SilentlyContinue
    if (-not $props) { continue }
    foreach ($p in $props.PSObject.Properties) {
        if ($p.Name -like 'PS*') { continue }
        if (-not (Casa @($p.Name, [string]$p.Value))) { continue }
        $itens.Add([pscustomobject]@{
            Tipo = 'Run'; Raiz = $f.Raiz; Chave = $f.Aprov; Nome = $p.Name; Detalhe = [string]$p.Value
            Estado = EstadoAprovado $f.Raiz $f.Aprov $p.Name; PrecisaAdmin = ($f.Raiz -eq 'HKLM')
        })
    }
}

foreach ($pasta in @(
        @{ Dir = [Environment]::GetFolderPath('Startup');       Raiz = 'HKCU' },
        @{ Dir = [Environment]::GetFolderPath('CommonStartup'); Raiz = 'HKLM' })) {
    if (-not $pasta.Dir -or -not (Test-Path -LiteralPath $pasta.Dir)) { continue }
    foreach ($arq in Get-ChildItem -LiteralPath $pasta.Dir -File -ErrorAction SilentlyContinue) {
        $alvo = if ($arq.Extension -eq '.lnk') { AlvoAtalho $arq.FullName } else { '' }
        if (-not (Casa @($arq.Name, $alvo))) { continue }
        $chave = "$aprovado\StartupFolder"
        $itens.Add([pscustomobject]@{
            Tipo = 'Inicializar'; Raiz = $pasta.Raiz; Chave = $chave; Nome = $arq.Name
            Detalhe = "$($arq.FullName) -> $alvo"
            Estado = EstadoAprovado $pasta.Raiz $chave $arq.Name; PrecisaAdmin = ($pasta.Raiz -eq 'HKLM')
        })
    }
}

if (Get-Command Get-ScheduledTask -ErrorAction SilentlyContinue) {
    foreach ($t in Get-ScheduledTask -ErrorAction SilentlyContinue) {
        $acoes = @($t.Actions | ForEach-Object { "$($_.Execute) $($_.Arguments)" })
        if (-not (Casa (@($t.TaskName, $t.TaskPath) + $acoes))) { continue }
        $itens.Add([pscustomobject]@{
            Tipo = 'Tarefa'; Raiz = ''; Chave = $t.TaskPath; Nome = $t.TaskName; Detalhe = ($acoes -join ' | ')
            Estado = $(if ($t.State -eq 'Disabled') { 'desligado' } else { 'ligado' }); PrecisaAdmin = $false
        })
    }
}

foreach ($s in Get-CimInstance Win32_Service -ErrorAction SilentlyContinue) {
    if (-not (Casa @($s.Name, $s.DisplayName, $s.PathName))) { continue }
    $itens.Add([pscustomobject]@{
        Tipo = 'Servico'; Raiz = ''; Chave = $s.StartMode; Nome = $s.Name; Detalhe = "$($s.DisplayName) [$($s.State)] $($s.PathName)"
        Estado = $(if ($s.StartMode -eq 'Auto') { 'ligado' } else { 'desligado' }); PrecisaAdmin = $true
    })
}

Titulo 'O QUE SOBE COM O WINDOWS'
if ($itens.Count -eq 0) {
    Aviso "nada casou com '$Padrao' - confira o nome com -Padrao (ex.: -Padrao 'UpSeller Print')"
}
foreach ($i in $itens) {
    Write-Host ("  {0,-11} {1,-9} {2}" -f $i.Tipo, $i.Estado, $i.Nome)
    Write-Host ("  {0,-21} {1}" -f '', $i.Detalhe)
}

Titulo 'RODANDO AGORA'
$procs = @(Get-Process -ErrorAction SilentlyContinue | Where-Object {
    $caminho = ''
    try { $caminho = $_.Path } catch { }
    Casa @($_.ProcessName, $caminho)
})
if ($procs.Count -eq 0) { Write-Host '  nenhum processo do UpSeller rodando' }
foreach ($p in $procs) {
    $portas = ''
    if (Get-Command Get-NetTCPConnection -ErrorAction SilentlyContinue) {
        $portas = (@(Get-NetTCPConnection -State Listen -OwningProcess $p.Id -ErrorAction SilentlyContinue |
            ForEach-Object { "$($_.LocalAddress):$($_.LocalPort)" }) | Select-Object -Unique) -join ', '
    }
    $caminho = ''
    try { $caminho = $p.Path } catch { }
    Write-Host ("  pid {0,-6} {1}  escuta: {2}" -f $p.Id, $caminho, $(if ($portas) { $portas } else { '-' }))
}

# ---------------------------------------------------------------- so inventario
if (-not $Desligar -and -not $Religar) {
    Titulo 'O QUE FAZER AGORA'
    Write-Host '  Isto foi so a lista - nada mudou.'
    Write-Host '  ANTES de desligar, prove que o agente Argos imprime as notas:'
    Write-Host '     .\argos-notas-fiscais.ps1 -UmaVez'
    Write-Host '  Depois:'
    Write-Host '     .\9-upseller-inicializacao.ps1 -Desligar -Confirmar'
    exit 0
}

# --------------------------------------------------------------------- desligar
if ($Desligar) {
    Titulo 'DESLIGAR DA INICIALIZACAO'
    $alvos = @($itens | Where-Object { $_.Estado -eq 'ligado' })
    if ($alvos.Count -eq 0) { OK 'nada ligado para desligar' }

    $pastaBackup = Join-Path $Checkpoints ("{0}\upseller" -f (Get-Date -Format 'yyyy-MM-dd_HHmm'))
    if ($Confirmar -and $alvos.Count -gt 0) {
        New-Item -ItemType Directory -Path $pastaBackup -Force | Out-Null
        # O estado de ANTES e o que o -Religar le para desfazer exatamente isto.
        $alvos | ConvertTo-Json -Depth 3 | Set-Content -LiteralPath (Join-Path $pastaBackup 'estado.json') -Encoding UTF8
        foreach ($i in $alvos | Where-Object Tipo -eq 'Tarefa') {
            $arq = Join-Path $pastaBackup ((($i.Chave + $i.Nome) -replace '[\\/:*?"<>|]', '_') + '.xml')
            Export-ScheduledTask -TaskName $i.Nome -TaskPath $i.Chave | Set-Content -LiteralPath $arq -Encoding Unicode
        }
        OK "backup em $pastaBackup"
    }

    foreach ($i in $alvos) {
        $rotulo = "$($i.Tipo) '$($i.Nome)'"
        if ($i.PrecisaAdmin -and -not $ehAdmin) { Aviso "$rotulo pulado - precisa do PowerShell como administrador"; continue }
        if (-not $Confirmar) { Plano "desligar $rotulo"; continue }
        try {
            switch ($i.Tipo) {
                { $_ -in 'Run', 'Inicializar' } {
                    $k = "$($i.Raiz):\$($i.Chave)"
                    if (-not (Test-Path -LiteralPath $k)) { New-Item -Path $k -Force | Out-Null }
                    Set-ItemProperty -LiteralPath $k -Name $i.Nome -Value (BytesDesligado) -Type Binary
                    $ok = (EstadoAprovado $i.Raiz $i.Chave $i.Nome) -eq 'desligado'
                }
                'Tarefa'  {
                    Disable-ScheduledTask -TaskName $i.Nome -TaskPath $i.Chave | Out-Null
                    $ok = (Get-ScheduledTask -TaskName $i.Nome -TaskPath $i.Chave).State -eq 'Disabled'
                }
                'Servico' {
                    # Manual, nao Desativado: se alguem abrir o UpSeller na mao,
                    # ele ainda consegue subir o proprio servico.
                    Set-Service -Name $i.Nome -StartupType Manual
                    $ok = (Get-CimInstance Win32_Service -Filter "Name='$($i.Nome)'").StartMode -eq 'Manual'
                }
            }
            if ($ok) { OK "$rotulo desligado" } else { Erro "$rotulo - o Windows nao confirmou" }
        } catch {
            Erro "$rotulo - $($_.Exception.Message)"
        }
    }

    if ($Encerrar) {
        foreach ($p in $procs) {
            if (-not $Confirmar) { Plano "encerrar pid $($p.Id) ($($p.ProcessName))"; continue }
            try { Stop-Process -Id $p.Id -Force; OK "encerrado pid $($p.Id) ($($p.ProcessName))" }
            catch { Erro "pid $($p.Id): $($_.Exception.Message)" }
        }
    } elseif ($procs.Count -gt 0) {
        Aviso 'o UpSeller continua rodando ate reiniciar (use -Encerrar para fechar agora)'
    }

    if ($Confirmar) {
        Write-Host ''
        Write-Host '  Para desfazer:  .\9-upseller-inicializacao.ps1 -Religar -Confirmar'
    } else {
        Write-Host ''
        Write-Host '  Isto foi so o PLANO. Para aplicar, acrescente -Confirmar.'
    }
    exit 0
}

# ---------------------------------------------------------------------- religar
Titulo 'RELIGAR (DESFAZER)'
if (-not $Checkpoint) {
    $ultimo = Get-ChildItem -LiteralPath $Checkpoints -Directory -ErrorAction SilentlyContinue |
        Sort-Object Name -Descending |
        Where-Object { Test-Path -LiteralPath (Join-Path $_.FullName 'upseller\estado.json') } |
        Select-Object -First 1
    if (-not $ultimo) { Erro "nenhum backup do UpSeller em $Checkpoints"; exit 1 }
    $Checkpoint = Join-Path $ultimo.FullName 'upseller'
}
$arqEstado = Join-Path $Checkpoint 'estado.json'
if (-not (Test-Path -LiteralPath $arqEstado)) { Erro "nao achei $arqEstado"; exit 1 }
Write-Host "  backup: $Checkpoint"
# No PowerShell 5.1 o ConvertFrom-Json devolve a lista inteira como UM objeto;
# guardar numa variavel antes do @() e o que a desembrulha.
$lido  = Get-Content -LiteralPath $arqEstado -Raw -Encoding UTF8 | ConvertFrom-Json
$antes = @($lido)

foreach ($i in $antes) {
    $rotulo = "$($i.Tipo) '$($i.Nome)'"
    if ($i.PrecisaAdmin -and -not $ehAdmin) { Aviso "$rotulo pulado - precisa do PowerShell como administrador"; continue }
    if (-not $Confirmar) { Plano "religar $rotulo"; continue }
    try {
        switch ($i.Tipo) {
            { $_ -in 'Run', 'Inicializar' } {
                Set-ItemProperty -LiteralPath "$($i.Raiz):\$($i.Chave)" -Name $i.Nome -Value $bytesLigado -Type Binary
            }
            'Tarefa'  { Enable-ScheduledTask -TaskName $i.Nome -TaskPath $i.Chave | Out-Null }
            'Servico' { Set-Service -Name $i.Nome -StartupType Automatic }
        }
        OK "$rotulo religado"
    } catch {
        Erro "$rotulo - $($_.Exception.Message)"
    }
}
if (-not $Confirmar) { Write-Host ''; Write-Host '  Isto foi so o PLANO. Para aplicar, acrescente -Confirmar.' }
else { Write-Host ''; Write-Host '  Reinicie o Windows (ou abra o UpSeller) para ele voltar a subir.' }
exit 0
