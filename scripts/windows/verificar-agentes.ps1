#Requires -Version 5.1
<#
    verificar-agentes.ps1 - Confere as rotinas do servidor (tarefas do
    Agendador de Tarefas) e, se mandar, religa as ESSENCIAIS que estiverem
    desligadas.

    O problema real: uma rotina desligada nao avisa ninguem. O Windows desliga
    tarefa em atualizacao, alguem desliga "so para testar", e a automacao para
    em silencio - descobre-se dias depois, pelo efeito.

    O que e "essencial" vem de uma LISTA FECHADA, o rotinas-essenciais.txt ao
    lado deste script (um nome por linha, aceita curinga *). Nada e religado
    por heuristica: tarefa desligada que nao esta na lista so aparece no
    relatorio.

    Sem -Ativar: SOMENTE LEITURA.
    Com -Ativar: religa (Enable-ScheduledTask) as essenciais desligadas. Antes,
    exporta o XML de cada uma para C:\Argos-Backups\_checkpoints\<carimbo>\.
    Depois, le o estado de volta e so diz [OK] se o Windows confirmar.
    Nunca cria, apaga, roda ou altera gatilho/acao de tarefa.

    Uso:
      # so verificar e gerar o relatorio
      powershell -ExecutionPolicy Bypass -File .\verificar-agentes.ps1

      # verificar e religar as essenciais desligadas
      powershell -ExecutionPolicy Bypass -File .\verificar-agentes.ps1 -Ativar

      # rodar fora do KHAOSOMNI
      .\verificar-agentes.ps1 -Forcar

    Saida: 0 = tudo certo, 1 = achou problema (ou algo nao religou).
#>
[CmdletBinding()]
param(
    [switch]$Ativar,
    [switch]$Forcar,
    [string]$Servidor    = 'KHAOSOMNI',
    [string]$Lista       = (Join-Path $PSScriptRoot 'rotinas-essenciais.txt'),
    [string]$Checkpoints = 'C:\Argos-Backups\_checkpoints',
    [string]$Log
)

$ErrorActionPreference = 'Stop'
$script:Linhas    = New-Object System.Collections.ArrayList
$script:Problemas = 0
$script:Carimbo   = Get-Date -Format 'yyyy-MM-dd_HHmm'

# A Area de Trabalho nem sempre e "$env:USERPROFILE\Desktop": com OneDrive ela
# vira "...\OneDrive\Area de Trabalho" e aquele caminho NAO existe.
if (-not $Log) {
    $desk = [Environment]::GetFolderPath('Desktop')
    if (-not $desk -or -not (Test-Path -LiteralPath $desk)) { $desk = $env:USERPROFILE }
    $Log = Join-Path $desk "verificar-agentes-$(Get-Date -Format 'yyyyMMdd-HHmm').txt"
}

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
function Problema([string]$Texto) {
    $script:Problemas++
    Escrever $Texto
}
function Salvar {
    $script:Linhas | Set-Content -LiteralPath $Log -Encoding UTF8
}
function EhAdmin {
    $id = [Security.Principal.WindowsIdentity]::GetCurrent()
    (New-Object Security.Principal.WindowsPrincipal $id).IsInRole(
        [Security.Principal.WindowsBuiltInRole]::Administrator)
}
function Quando($Data) {
    if (-not $Data -or $Data.Year -lt 2000) { return 'nunca' }
    $Data.ToString('dd/MM/yyyy HH:mm')
}

# Codigos de LastTaskResult que NAO sao falha:
#   0x0      terminou bem
#   0x41300  pronta para rodar
#   0x41301  rodando agora
#   0x41303  ainda nao rodou
#   0x41306  encerrada pelo usuario
$script:ResultadosBons = @(0, 0x41300, 0x41301, 0x41303, 0x41306)

# Tira da acao da tarefa todo caminho de arquivo que da para conferir.
# "powershell -File C:\Scripts\x.ps1" e o formato mais comum, e ali o
# caminho esta no meio dos argumentos, nao no Execute.
function CaminhosDaAcao($Acao) {
    $achados = @()
    $texto = "$($Acao.Execute) $($Acao.Arguments)"
    $texto = [Environment]::ExpandEnvironmentVariables($texto)
    $padrao = '(?:[A-Za-z]:\\|\\\\)[^"'']+?\.(?:ps1|cmd|bat|exe|py|vbs|js)\b'
    foreach ($m in [regex]::Matches($texto, $padrao)) { $achados += $m.Value }
    return $achados
}

function EhEssencial($Tarefa) {
    $completo = "$($Tarefa.TaskPath)$($Tarefa.TaskName)"
    foreach ($p in $script:Padroes) {
        if ($Tarefa.TaskName -like $p -or $completo -like $p) { return $true }
    }
    return $false
}

# ------------------------------------------------------------ trava de dono
# As automacoes tem DONO UNICO. Religar no notebook uma rotina que e do
# servidor faz as duas maquinas rodarem a mesma coisa, em silencio.
if ($env:COMPUTERNAME -ne $Servidor -and -not $Forcar) {
    Write-Host ''
    Write-Host "  PARE: esta maquina e $env:COMPUTERNAME, nao o servidor $Servidor." -ForegroundColor Red
    Write-Host '  As rotinas verificadas aqui sao as do servidor. Se e mesmo nesta'  -ForegroundColor Red
    Write-Host '  maquina que voce quer rodar, repita com -Forcar.'                  -ForegroundColor Red
    Write-Host ''
    exit 1
}

Escrever "Verificacao dos agentes (rotinas agendadas)"
Escrever "$(Get-Date -Format 'dd/MM/yyyy HH:mm')   Maquina: $env:COMPUTERNAME   Usuario: $env:USERNAME"
if ($Ativar) {
    Escrever 'MODO ATIVAR - rotinas essenciais desligadas serao religadas'
} else {
    Escrever 'MODO VERIFICAR - somente leitura (use -Ativar para religar)'
}
if (-not (EhAdmin)) {
    Escrever '[!] Rodando SEM administrador: tarefas de outros usuarios ou do'
    Escrever '    SYSTEM podem nao aparecer, e religar essas pode ser recusado.'
}

# ------------------------------------------------------------ lista fechada
if (-not (Test-Path -LiteralPath $Lista)) {
    Escrever ''
    Escrever "[ERRO] Nao achei a lista de rotinas essenciais: $Lista"
    Escrever '       Sem ela nao ha como saber o que religar. Crie o arquivo com'
    Escrever '       um nome de tarefa por linha (aceita curinga *).'
    Salvar
    exit 1
}
$script:Padroes = @(
    Get-Content -LiteralPath $Lista -Encoding UTF8 |
        ForEach-Object { $_.Trim() } |
        Where-Object { $_ -and -not $_.StartsWith('#') }
)
if ($script:Padroes.Count -eq 0) {
    Escrever ''
    Escrever "[ERRO] A lista $Lista esta vazia."
    Salvar
    exit 1
}
Escrever "Lista de essenciais: $Lista ($($script:Padroes.Count) nome(s))"

# ---------------------------------------------------------------- inventario
# As tarefas do proprio Windows (\Microsoft\...) sao centenas e nao sao nossas.
$todas = @(
    Get-ScheduledTask | Where-Object { $_.TaskPath -notlike '\Microsoft\*' } |
        Sort-Object TaskPath, TaskName
)
$essenciais = @($todas | Where-Object { EhEssencial $_ })
$outras     = @($todas | Where-Object { -not (EhEssencial $_) })

Titulo 'ROTINAS ESSENCIAIS'
if ($essenciais.Count -eq 0) {
    Problema '[ERRO] Nenhuma tarefa casou com a lista. Confira os nomes em "OUTRAS ROTINAS".'
}
foreach ($p in $script:Padroes) {
    $casou = @($essenciais | Where-Object {
        $_.TaskName -like $p -or "$($_.TaskPath)$($_.TaskName)" -like $p })
    # Curinga que nao casa nada e normal (a lista cobre variacoes de nome).
    # Nome EXATO que sumiu e rotina essencial apagada ou renomeada.
    if ($casou.Count -eq 0 -and -not [WildcardPattern]::ContainsWildcardCharacters($p)) {
        Problema "[ERRO] '$p' - nenhuma tarefa com esse nome. Foi apagada ou renomeada?"
    }
}

$desligadas = @()
foreach ($t in $essenciais) {
    $info = Get-ScheduledTaskInfo -TaskName $t.TaskName -TaskPath $t.TaskPath
    $nome = "$($t.TaskPath)$($t.TaskName)"
    Escrever ''
    Escrever $nome
    Escrever ("    Estado ........: {0}" -f $t.State)
    Escrever ("    Ultima vez ....: {0}   resultado 0x{1:X}" -f (Quando $info.LastRunTime), $info.LastTaskResult)
    Escrever ("    Proxima vez ...: {0}" -f (Quando $info.NextRunTime))

    $arquivosFaltando = @()
    foreach ($a in $t.Actions) {
        foreach ($c in (CaminhosDaAcao $a)) {
            if (-not (Test-Path -LiteralPath $c)) { $arquivosFaltando += $c }
        }
    }

    if ($t.State -eq 'Disabled') {
        Problema '    [ERRO] DESLIGADA - a rotina nao vai rodar.'
        $desligadas += [pscustomobject]@{ Tarefa = $t; Nome = $nome; Faltando = $arquivosFaltando }
    } else {
        if (-not $info.NextRunTime -or $info.NextRunTime.Year -lt 2000) {
            Problema '    [!] Ligada, mas SEM proxima execucao - gatilho vencido ou ausente.'
        }
        if ($info.NumberOfMissedRuns -gt 0) {
            Problema "    [!] Perdeu $($info.NumberOfMissedRuns) execucao(oes) - maquina desligada ou dormindo no horario?"
        }
    }
    if ($script:ResultadosBons -notcontains [int64]$info.LastTaskResult) {
        Problema ("    [!] A ultima execucao FALHOU (0x{0:X})." -f $info.LastTaskResult)
    }
    foreach ($f in $arquivosFaltando) {
        Problema "    [ERRO] A acao chama um arquivo que NAO existe: $f"
    }
    if ($t.State -ne 'Disabled' -and $arquivosFaltando.Count -eq 0 -and
        $script:ResultadosBons -contains [int64]$info.LastTaskResult) {
        Escrever '    [OK]'
    }
}

# -------------------------------------------------------------------- outras
Titulo 'OUTRAS ROTINAS (fora da lista - so informativo, nada e religado)'
if ($outras.Count -eq 0) {
    Escrever '  (nenhuma)'
}
foreach ($t in $outras) {
    $marca = ''
    if ($t.State -eq 'Disabled') { $marca = '   <- desligada; se for essencial, ponha na lista' }
    Escrever ("  {0,-10} {1}{2}{3}" -f $t.State, $t.TaskPath, $t.TaskName, $marca)
}

# --------------------------------------------------------------------- ativar
if ($Ativar) {
    Titulo 'RELIGANDO'
    if ($desligadas.Count -eq 0) {
        Escrever '  Nenhuma rotina essencial desligada. Nada a fazer.'
    }
    foreach ($d in $desligadas) {
        # Religar uma rotina que chama arquivo inexistente so troca "desligada"
        # por "falhando todo dia". Conserta o arquivo primeiro.
        if ($d.Faltando.Count -gt 0) {
            Escrever "  [!] $($d.Nome): NAO religada - a acao chama arquivo que nao existe."
            continue
        }
        try {
            # Toda alteracao tem volta: guarda a definicao como estava.
            $pasta = Join-Path $Checkpoints $script:Carimbo
            New-Item -ItemType Directory -Path $pasta -Force | Out-Null
            $arquivo = Join-Path $pasta (($d.Nome.Trim('\') -replace '[\\/:*?"<>|]', '_') + '.xml')
            Export-ScheduledTask -TaskName $d.Tarefa.TaskName -TaskPath $d.Tarefa.TaskPath |
                Set-Content -LiteralPath $arquivo -Encoding Unicode

            Enable-ScheduledTask -TaskName $d.Tarefa.TaskName -TaskPath $d.Tarefa.TaskPath | Out-Null

            # "Mandei fazer" nao e "fez": le de volta.
            $agora = Get-ScheduledTask -TaskName $d.Tarefa.TaskName -TaskPath $d.Tarefa.TaskPath
            if ($agora.State -ne 'Disabled') {
                $prox = (Get-ScheduledTaskInfo -TaskName $d.Tarefa.TaskName -TaskPath $d.Tarefa.TaskPath).NextRunTime
                Escrever "  [OK] $($d.Nome) religada (estado: $($agora.State), proxima: $(Quando $prox))."
                Escrever "       Checkpoint: $arquivo"
                $script:Problemas--
            } else {
                Escrever "  [ERRO] $($d.Nome): o Windows aceitou o comando, mas continua desligada."
            }
        } catch {
            Escrever "  [ERRO] $($d.Nome): nao religou - $($_.Exception.Message)"
            if (-not (EhAdmin)) {
                Escrever '         Provavelmente falta administrador. Abra o PowerShell como admin.'
            }
        }
    }
}

# -------------------------------------------------------------------- resumo
Titulo 'RESUMO'
Escrever ("  Essenciais encontradas ..: {0}" -f $essenciais.Count)
Escrever ("  Desligadas ...............: {0}" -f $desligadas.Count)
Escrever ("  Outras rotinas ...........: {0}" -f $outras.Count)
if ($script:Problemas -le 0) {
    Escrever '  [OK] Nenhum problema pendente.'
} else {
    Escrever "  [!] $($script:Problemas) problema(s) pendente(s) - veja acima."
}
Escrever ''
Escrever "Relatorio salvo em: $Log"
Salvar

if ($script:Problemas -le 0) { exit 0 } else { exit 1 }
