#Requires -Version 5.1
<#
    vigias-loja.ps1 - Manutencao dos vigias do Argos na maquina da loja
    (HUDSONINTEGRAR): Vigia UpSeller, Acoes UpSeller e Coletor TikTok.

    O sintoma de 15/10: os tres pararam JUNTOS as 08:54 e o guardiao passou o
    dia avisando "ATRASADO", "o Agendador nao respondeu em 90 s" e "o
    PowerShell nao respondeu em 60 s lendo as impressoras". Tres vigias
    parados no mesmo minuto nao sao tres defeitos: e uma causa so. As
    suspeitas, nesta ordem:

      1. Uma rodada TRAVOU e ficou "rodando". A tarefa e "se ja estiver
         rodando, nao inicie outra" (IgnoreNew), entao o Agendador pula todas
         as rodadas seguintes - sem erro nenhum - ate o limite de tempo, que
         por padrao e de 72 HORAS.
      2. O spooler de impressao travou (USB/driver). Tudo que pergunta pelas
         impressoras fica esperando para sempre - inclusive o Chrome.
      3. O WMI travou. Get-ScheduledTask e Get-Printer passam os dois pelo
         WMI (CIM): se ele para, "Agendador" e "impressoras" param juntos, que
         e exatamente o par de avisos do guardiao.

    Este script testa cada suspeita SEM depender delas: le o Agendador pelo
    COM (Schedule.Service), as impressoras pelo winspool, e roda cada teste
    num processo separado com limite de tempo - se travar, ele e morto e o
    relatorio diz "TRAVADO", em vez de travar junto.

    Sem -Reparar: SOMENTE LEITURA. Mostra o diagnostico e o plano.
    Com -Reparar, e so no que o diagnostico apontou:
      - salva o XML das tarefas em C:\Argos-Backups\_checkpoints\<carimbo>\;
      - encerra a rodada travada (e os processos filhos dela);
      - fecha Chrome de AUTOMACAO que ficou orfao no perfil do vigia. Janela
        do Chrome aberta A MAO no perfil do vigia nunca e fechada: o
        relatorio pede para a pessoa fechar (o login fica salvo);
      - reinicia o spooler se ele nao responde (precisa de administrador).
        Nao apaga nenhum trabalho de impressao;
      - poe limite de tempo nas tarefas (intervalo - 5 min), para uma rodada
        travada nunca mais segurar o vigia por 72 h, e liga "rodar assim que
        possivel se perder o horario";
      - religa vigia desligado e dispara uma rodada agora;
      - le tudo de volta: so diz [OK] se a tarefa rodou de fato.
    Nunca mexe no UpSeller, no TikTok, em pedido, nota ou configuracao, nem
    cria ou apaga tarefa.

    Uso:
      # diagnostico (nao muda nada)
      powershell -ExecutionPolicy Bypass -File .\vigias-loja.ps1

      # diagnostico + reparo (PowerShell como administrador, se o spooler
      # precisar ser reiniciado)
      powershell -ExecutionPolicy Bypass -File .\vigias-loja.ps1 -Reparar

      # rodar fora da HUDSONINTEGRAR
      .\vigias-loja.ps1 -Forcar

    Saida: 0 = tudo certo, 1 = achou problema (ou algo nao voltou).
#>
[CmdletBinding()]
param(
    [switch]$Reparar,
    [switch]$Forcar,
    [string]$Maquina     = 'HUDSONINTEGRAR',
    [string[]]$Vigias    = @('ARGOS - Vigia UpSeller', 'ARGOS - Acoes UpSeller', 'ARGOS - Vigia TikTok coletor'),
    [string]$PastaLogs   = (Join-Path $env:LOCALAPPDATA 'Argos'),
    [string]$Checkpoints = 'C:\Argos-Backups\_checkpoints',
    [int]$FolgaMinutos   = 5,
    [int]$HorasEventos   = 16,
    [string]$Log
)

$ErrorActionPreference = 'Stop'
$script:Linhas    = New-Object System.Collections.ArrayList
$script:Problemas = 0
$script:Carimbo   = Get-Date -Format 'yyyy-MM-dd_HHmm'
$agora            = Get-Date

# A Area de Trabalho nem sempre e "$env:USERPROFILE\Desktop": com OneDrive ela
# vira "...\OneDrive\Area de Trabalho" e aquele caminho NAO existe.
if (-not $Log) {
    $desk = [Environment]::GetFolderPath('Desktop')
    if (-not $desk -or -not (Test-Path -LiteralPath $desk)) { $desk = $env:USERPROFILE }
    $Log = Join-Path $desk "vigias-loja-$(Get-Date -Format 'yyyyMMdd-HHmm').txt"
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
    try {
        $script:Linhas | Set-Content -LiteralPath $Log -Encoding UTF8
        Write-Host ''
        Write-Host "Relatorio salvo em: $Log"
    } catch {
        Write-Host "[!] Nao consegui salvar o relatorio em $Log : $($_.Exception.Message)" -ForegroundColor Yellow
    }
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
function Minutos($De) { [int][Math]::Round(((Get-Date) - $De).TotalMinutes) }
# Datas viajam entre os processos como texto 'yyyy-MM-ddTHH:mm:ss'.
function LerData($Texto) {
    if (-not $Texto) { return $null }
    $d = $null
    if ($Texto -is [datetime]) { $d = $Texto }
    else {
        try { $d = [datetime]::ParseExact(([string]$Texto).Trim(), 's', [Globalization.CultureInfo]::InvariantCulture) }
        catch { return $null }
    }
    if ($d.Year -lt 2000) { return $null }
    $d
}
# "PT30M", "PT1H", "PT72H" -> TimeSpan. Vazio ou invalido -> $null.
function Duracao([string]$Iso) {
    if (-not $Iso) { return $null }
    try { return [System.Xml.XmlConvert]::ToTimeSpan($Iso) } catch { return $null }
}
# Texto entre aspas simples para colar dentro do codigo do processo filho.
function Lit([string]$Texto) { "'" + $Texto.Replace("'", "''") + "'" }
function PrimeiraLinha([string]$Texto) {
    if (-not $Texto) { return '' }
    $l = ($Texto -split "`r?`n" | Where-Object { $_.Trim() } | Select-Object -First 1)
    if ($l.Length -gt 160) { $l = $l.Substring(0, 160) + '...' }
    $l
}

# Roda $Codigo num powershell.exe SEPARADO e mata o processo se passar de
# $Segundos. E isso que impede o script de travar junto com o WMI, o
# Agendador ou o spooler: Start-Job nao serve, porque Stop-Job tambem fica
# esperando a chamada travada terminar.
function ComLimite([string]$Codigo, [int]$Segundos) {
    $envelope = "`$ProgressPreference = 'SilentlyContinue'; `$ErrorActionPreference = 'Stop'`n" +
                "[Console]::OutputEncoding = [Text.Encoding]::UTF8`n" +
                "try {`n$Codigo`n} catch { Write-Output ('ERRO: ' + `$_.Exception.Message); exit 1 }"
    $psi = New-Object Diagnostics.ProcessStartInfo
    $psi.FileName  = 'powershell.exe'
    $psi.Arguments = '-NoProfile -NonInteractive -ExecutionPolicy Bypass -EncodedCommand ' +
                     [Convert]::ToBase64String([Text.Encoding]::Unicode.GetBytes($envelope))
    $psi.UseShellExecute        = $false
    $psi.CreateNoWindow         = $true
    $psi.RedirectStandardOutput = $true
    $psi.RedirectStandardError  = $true
    $psi.StandardOutputEncoding = [Text.Encoding]::UTF8
    $relogio = [Diagnostics.Stopwatch]::StartNew()
    $p   = [Diagnostics.Process]::Start($psi)
    $out = $p.StandardOutput.ReadToEndAsync()
    $err = $p.StandardError.ReadToEndAsync()
    if (-not $p.WaitForExit($Segundos * 1000)) {
        try { $p.Kill() } catch { }
        return [pscustomobject]@{ Respondeu = $false; Ok = $false; Saida = ''; Segundos = $Segundos }
    }
    $p.WaitForExit()
    $saida = $out.Result
    [pscustomobject]@{
        Respondeu = $true
        Ok        = ($p.ExitCode -eq 0)
        Saida     = $saida
        Erro      = (PrimeiraLinha (($saida -split "`r?`n" | Where-Object { $_ -like 'ERRO:*' }) -join "`n"))
        Segundos  = [int][Math]::Ceiling($relogio.Elapsed.TotalSeconds)
    }
}
# Ultima linha JSON da saida do filho, ja como lista de objetos.
function LerJson($Resultado) {
    if (-not $Resultado.Ok) { return @() }
    $json = $Resultado.Saida -split "`r?`n" | Where-Object { $_.Trim().StartsWith('[') } | Select-Object -Last 1
    if (-not $json) { return @() }
    # PowerShell 5.1: ConvertFrom-Json devolve o array como UM objeto; o
    # foreach desembrulha.
    @(foreach ($x in ($json | ConvertFrom-Json)) { $x })
}
function Testar([string]$Rotulo, [string]$Codigo, [int]$Segundos) {
    $r = ComLimite $Codigo $Segundos
    if (-not $r.Respondeu) {
        Problema ("[TRAVADO] {0}: nao respondeu em {1} s" -f $Rotulo, $Segundos)
    } elseif (-not $r.Ok) {
        Problema ("[ERRO] {0}: {1}" -f $Rotulo, $r.Erro)
    } else {
        Escrever ("[OK] {0} ({1} s)" -f $Rotulo, $r.Segundos)
    }
    $r
}

# --------------------------------------------------- codigo dos processos filhos
# Le TODAS as tarefas "Argos*" pelo COM do Agendador - nao passa pelo WMI.
$codInventario = @'
$s = New-Object -ComObject Schedule.Service
$s.Connect()
$lista = New-Object System.Collections.ArrayList
# Pasta sem permissao (tarefa de outro usuario) nao derruba o inventario.
function Varre($pasta) {
    try { foreach ($t in $pasta.GetTasks(1)) { if ($t.Name -like 'argos*') { [void]$lista.Add($t) } } } catch { }
    try { foreach ($sub in $pasta.GetFolders(0)) { if ($sub.Path -notlike '\Microsoft*') { Varre $sub } } } catch { }
}
Varre ($s.GetFolder('\'))
$saida = foreach ($t in $lista) {
    $d = $t.Definition
    $intervalo = ''
    foreach ($g in $d.Triggers) {
        if (-not $intervalo -and $g.Repetition -and $g.Repetition.Interval) { $intervalo = $g.Repetition.Interval }
    }
    $acoes = @(foreach ($a in $d.Actions) { if ($a.Type -eq 0) { "$($a.Path) $($a.Arguments)".Trim() } })
    $instancias = @()
    try { $instancias = @($t.GetInstances(0)) } catch { }
    $rodando = @(foreach ($i in $instancias) {
        $inicio = ''; $nomeProc = ''
        $p = Get-Process -Id $i.EnginePID -ErrorAction SilentlyContinue
        if ($p) { $nomeProc = $p.ProcessName; try { $inicio = $p.StartTime.ToString('s') } catch { } }
        '{0}|{1}|{2}' -f $i.EnginePID, $inicio, $nomeProc
    })
    [pscustomobject]@{
        Nome      = $t.Name
        Caminho   = $t.Path
        Ativa     = [bool]$t.Enabled
        Estado    = [int]$t.State
        Ultima    = $t.LastRunTime.ToString('s')
        Resultado = ('0x{0:X8}' -f $t.LastTaskResult)
        Proxima   = $t.NextRunTime.ToString('s')
        Limite    = [string]$d.Settings.ExecutionTimeLimit
        Multiplas = [int]$d.Settings.MultipleInstances
        AssimQuePossivel = [bool]$d.Settings.StartWhenAvailable
        Intervalo = [string]$intervalo
        Logon     = [int]$d.Principal.LogonType
        Acoes     = $acoes
        Rodando   = $rodando
    }
}
ConvertTo-Json -InputObject @($saida) -Depth 4 -Compress
'@

# Processos ligados aos vigias, com a linha de comando (essa parte precisa
# do WMI - se ele travou, cai no plano B sem linha de comando).
$codProcessos = @'
$nomes = 'powershell.exe', 'pwsh.exe', 'node.exe', 'python.exe', 'pythonw.exe', 'chrome.exe', 'msedge.exe'
$r = foreach ($p in (Get-CimInstance Win32_Process -OperationTimeoutSec 40)) {
    if ($nomes -notcontains $p.Name.ToLower()) { continue }
    $cl = [string]$p.CommandLine
    if ($cl -match '--type=') { continue }
    if ($cl -notmatch '(?i)vigia|upseller|tiktok|acoes|\\Argos\\') { continue }
    $ini = ''
    if ($p.CreationDate) { $ini = $p.CreationDate.ToString('s') }
    [pscustomobject]@{ Pid = [int]$p.ProcessId; Pai = [int]$p.ParentProcessId; Nome = $p.Name; Inicio = $ini; Linha = $cl }
}
ConvertTo-Json -InputObject @($r) -Depth 3 -Compress
'@

$codWmi        = "(Get-CimInstance Win32_OperatingSystem -OperationTimeoutSec 25).LastBootUpTime.ToString('s')"
$codGetTask    = "Get-ScheduledTask -TaskName $(Lit $Vigias[0]) -ErrorAction SilentlyContinue | Out-Null; 'ok'"
$codWinspool   = "Add-Type -AssemblyName System.Drawing; [System.Drawing.Printing.PrinterSettings]::InstalledPrinters.Count"
$codGetPrinter = "@(Get-Printer).Count"

$estados   = @{ 0 = 'desconhecido'; 1 = 'DESLIGADA'; 2 = 'na fila'; 3 = 'pronta'; 4 = 'RODANDO' }
$multiplas = @{ 0 = 'roda outra em paralelo'; 1 = 'enfileira'; 2 = 'ignora a nova (IgnoreNew)'; 3 = 'para a anterior' }
# Codigos de LastTaskResult que NAO sao falha.
$resultadosBons = @('0x00000000', '0x00041300', '0x00041301', '0x00041303')
$explica = @{
    '0x00041306' = 'encerrada (por alguem ou pelo limite de tempo)'
    '0x8004131F' = 'ja havia uma rodada em andamento'
    '0x800710E0' = 'o Windows recusou: usuario nao logado ou condicao da tarefa'
    '0x00000001' = 'o script terminou com erro (veja o log dele)'
    '0xC000013A' = 'processo encerrado (desligamento ou Ctrl+C)'
    '0x80070002' = 'arquivo da acao nao encontrado'
}

# ------------------------------------------------------------ trava de dono
if ($env:COMPUTERNAME -ne $Maquina -and -not $Forcar) {
    Write-Host ''
    Write-Host "  PARE: esta maquina e $env:COMPUTERNAME, nao a $Maquina." -ForegroundColor Red
    Write-Host '  Os vigias da loja rodam la. Se e mesmo nesta maquina que voce quer'  -ForegroundColor Red
    Write-Host '  rodar, repita com -Forcar.'                                          -ForegroundColor Red
    Write-Host ''
    exit 1
}

Escrever 'Manutencao dos vigias da loja (Argos)'
Escrever "$(Get-Date -Format 'dd/MM/yyyy HH:mm')   Maquina: $env:COMPUTERNAME   Usuario: $env:USERNAME"
if ($Reparar) {
    Escrever 'MODO REPARAR - aplica o plano no fim do diagnostico'
} else {
    Escrever 'MODO DIAGNOSTICO - somente leitura (use -Reparar para aplicar o plano)'
}
$admin = EhAdmin
if (-not $admin) {
    Escrever '[!] Rodando SEM administrador: o diagnostico funciona, mas reiniciar o'
    Escrever '    spooler, se for preciso, vai ser recusado.'
}

# ------------------------------------------------------------ saude do Windows
Titulo 'O WINDOWS ESTA RESPONDENDO?'
Escrever 'Cada teste roda em processo separado; se travar, e encerrado no limite.'
Escrever ''
$rWmi       = Testar 'WMI (Win32_OperatingSystem)'                     $codWmi        40
$rGetTask   = Testar 'Get-ScheduledTask (Agendador pelo WMI)'          $codGetTask    60
$rInv       = Testar 'Agendador pelo COM (Schedule.Service)'           $codInventario 90
$spooler    = Get-Service -Name Spooler
Escrever ("[{0}] Servico Spooler: {1}" -f $(if ($spooler.Status -eq 'Running') { 'OK' } else { '!!' }), $spooler.Status)
if ($spooler.Status -ne 'Running') { $script:Problemas++ }
$rWinspool  = Testar 'Impressoras pelo winspool (sem WMI)'             $codWinspool   45
$rGetPrint  = Testar 'Get-Printer (impressoras pelo WMI)'              $codGetPrinter 60
try {
    $pastaSpool = Join-Path $env:windir 'System32\spool\PRINTERS'
    $naFila = @(Get-ChildItem -LiteralPath $pastaSpool -File -ErrorAction Stop).Count
    Escrever ("     Arquivos na pasta do spooler: {0} (trabalhos de impressao parados)" -f $naFila)
} catch {
    Escrever '     Pasta do spooler: sem permissao para olhar (normal sem administrador).'
}

$wmiTravado     = -not $rWmi.Respondeu -or -not $rGetTask.Respondeu -or -not $rGetPrint.Respondeu
$spoolerTravado = ($spooler.Status -ne 'Running') -or -not $rWinspool.Respondeu
Escrever ''
if ($rWmi.Ok) {
    $boot = LerData ($rWmi.Saida -split "`r?`n" | Where-Object { $_.Trim() } | Select-Object -Last 1)
    if ($boot) { Escrever ("Ligada desde: {0} ({1:N1} h)" -f (Quando $boot), ((Get-Date) - $boot).TotalHours) }
}
if ($spoolerTravado) {
    Escrever 'LEITURA: o SPOOLER nao responde. Quem perguntar pelas impressoras fica'
    Escrever '         esperando - o Chrome do vigia inclusive. O -Reparar reinicia o spooler.'
} elseif ($wmiTravado) {
    Escrever 'LEITURA: o spooler responde pelo winspool, mas o WMI nao. E por isso que o'
    Escrever '         guardiao acusa "Agendador" e "impressoras" juntos: os dois perguntam'
    Escrever '         pelo WMI. O -Reparar nao reinicia o WMI; reinicie a maquina fora do'
    Escrever '         horario de expedicao se isso continuar depois do reparo.'
}

# ------------------------------------------------------------ tarefas
$tarefas = LerJson $rInv
$reparos = New-Object System.Collections.ArrayList
Titulo 'VIGIAS (Agendador de Tarefas)'
if (-not $rInv.Ok) {
    Problema '[ERRO] Nao consegui ler o Agendador nem pelo COM. Sem isso nao ha diagnostico'
    Problema '       das tarefas: reinicie a maquina e rode de novo.'
}
foreach ($nome in $Vigias) {
    if (-not $rInv.Ok) { break }
    $t = $tarefas | Where-Object { $_.Nome -eq $nome } | Select-Object -First 1
    Escrever ''
    if (-not $t) {
        Problema "[ERRO] '$nome' - nenhuma tarefa com esse nome. Foi apagada ou renomeada?"
        continue
    }
    $intervalo = Duracao $t.Intervalo
    $limite    = Duracao $t.Limite
    $ultima    = LerData $t.Ultima
    $proxima   = LerData $t.Proxima
    $ref       = 30
    if ($intervalo) { $ref = [int]$intervalo.TotalMinutes }

    $txtIntervalo = 'sem repeticao (gatilho unico ou por evento)'
    if ($intervalo) { $txtIntervalo = "a cada $ref min" }
    $txtLimite = 'SEM LIMITE'
    if ($limite -and $limite.Ticks -gt 0) { $txtLimite = "$([int]$limite.TotalMinutes) min" }
    $txtResultado = $t.Resultado
    if ($explica.ContainsKey($t.Resultado)) { $txtResultado += " ($($explica[$t.Resultado]))" }

    Escrever $t.Caminho
    Escrever ("    Estado ........: {0}" -f $estados[[int]$t.Estado])
    Escrever ("    Ultima vez ....: {0}   resultado {1}" -f (Quando $ultima), $txtResultado)
    Escrever ("    Proxima vez ...: {0}" -f (Quando $proxima))
    Escrever ("    Repeticao .....: {0}" -f $txtIntervalo)
    Escrever ("    Limite de tempo: {0}   se ja estiver rodando: {1}" -f $txtLimite, $multiplas[[int]$t.Multiplas])
    foreach ($a in $t.Acoes) { Escrever "    Acao ..........: $a" }

    $travada = $false
    $pids    = @()
    foreach ($r in @($t.Rodando)) {
        if (-not $r) { continue }
        $partes = $r -split '\|'
        $pids  += [int]$partes[0]
        $ini    = LerData $partes[1]
        if ($ini) {
            $min = Minutos $ini
            Escrever ("    Rodando .......: PID {0} ({1}) desde {2} - ha {3} min" -f $partes[0], $partes[2], $ini.ToString('dd/MM HH:mm'), $min)
            if ($min -gt (2 * $ref)) { $travada = $true }
        } else {
            Escrever ("    Rodando .......: PID {0} (inicio desconhecido)" -f $partes[0])
            if ($ultima -and (Minutos $ultima) -gt (2 * $ref)) { $travada = $true }
        }
    }
    if ([int]$t.Estado -eq 4 -and $pids.Count -eq 0 -and $ultima -and (Minutos $ultima) -gt (2 * $ref)) {
        $travada = $true
    }

    $precisaRodar = $false
    if (-not $t.Ativa) {
        Problema '    [ERRO] Tarefa DESLIGADA: o vigia nao roda ate alguem religar.'
        $precisaRodar = $true
    }
    if ($travada) {
        Problema ("    [TRAVADO] A rodada esta presa. Com '{0}', o Agendador pula todas" -f $multiplas[[int]$t.Multiplas])
        Problema  '              as rodadas seguintes sem registrar erro nenhum.'
        [void]$reparos.Add([pscustomobject]@{ Tipo = 'Parar'; Caminho = $t.Caminho; Pids = $pids
            Texto = "Encerrar a rodada presa de '$nome' (PID $($pids -join ', ')) e os filhos dela" })
        $precisaRodar = $true
    } elseif ($ultima -and (Minutos $ultima) -gt (2 * $ref) -and [int]$t.Estado -ne 4) {
        Problema ("    [!] Atrasada: ultima rodada ha {0} min, e devia rodar a cada {1} min." -f (Minutos $ultima), $ref)
        if (-not $proxima -or $proxima -lt $agora) {
            Problema '        E nao ha proxima execucao marcada: o gatilho venceu.'
        }
        $precisaRodar = $true
    }
    if ($resultadosBons -notcontains $t.Resultado -and $t.Resultado -ne '0x00041306') {
        Problema ("    [!] A ultima rodada terminou com erro {0}." -f $txtResultado)
    }

    # Limite de tempo: maior que o intervalo (ou "sem limite") faz uma rodada
    # presa segurar o vigia por horas, ja que as proximas sao ignoradas.
    $limiteRuim = $intervalo -and (-not $limite -or $limite.Ticks -eq 0 -or $limite -gt $intervalo)
    if ($limiteRuim -or ($intervalo -and -not $t.AssimQuePossivel) -or -not $t.Ativa) {
        $novo = $null
        $partesTexto = @()
        if ($limiteRuim) {
            $minNovo = [Math]::Max(10, $ref - $FolgaMinutos)
            $novo    = [System.Xml.XmlConvert]::ToString([TimeSpan]::FromMinutes($minNovo))
            Problema ("    [!] Limite de tempo ({0}) maior que o intervalo ({1} min): uma rodada" -f $txtLimite, $ref)
            Problema  '        presa segura o vigia ate esse limite.'
            $partesTexto += "limite de $minNovo min"
        }
        if ($intervalo -and -not $t.AssimQuePossivel) { $partesTexto += "rodar assim que possivel se perder o horario" }
        if (-not $t.Ativa) { $partesTexto += 'religar' }
        if (@(1, 6) -contains [int]$t.Logon) {
            Problema '        A tarefa guarda SENHA: o script nao a regrava. Ajuste a mao no Agendador:'
            Problema '        Propriedades > Configuracoes > "Parar a tarefa se ela executar por mais de".'
        } else {
            [void]$reparos.Add([pscustomobject]@{ Tipo = 'Ajustar'; Caminho = $t.Caminho; Limite = $novo
                Religar = (-not $t.Ativa); Texto = "Ajustar '$nome': $($partesTexto -join ', ')" })
        }
    }
    if ($precisaRodar) {
        [void]$reparos.Add([pscustomobject]@{ Tipo = 'Rodar'; Caminho = $t.Caminho
            Texto = "Disparar uma rodada de '$nome' agora e conferir" })
    }
}

$outras = @($tarefas | Where-Object { $Vigias -notcontains $_.Nome })
if ($outras.Count -gt 0) {
    Escrever ''
    Escrever 'Outras tarefas Argos nesta maquina (so leitura):'
    foreach ($o in ($outras | Sort-Object Caminho)) {
        Escrever ("    {0,-12} ultima {1}  {2}  {3}" -f $estados[[int]$o.Estado], (Quando (LerData $o.Ultima)), $o.Resultado, $o.Caminho)
    }
}

# ------------------------------------------------------------ processos
Titulo 'PROCESSOS DOS VIGIAS'
$rProc = ComLimite $codProcessos 60
$procs = @(LerJson $rProc | Where-Object { $_.Pid -ne $PID })
if ($rProc.Ok) {
    if ($procs.Count -eq 0) { Escrever 'Nenhum processo de vigia rodando agora.' }
    foreach ($p in $procs) {
        $ini   = LerData $p.Inicio
        $idade = ''
        if ($ini) { $idade = "ha $(Minutos $ini) min" }
        $linha = $p.Linha
        if ($linha.Length -gt 150) { $linha = $linha.Substring(0, 150) + '...' }
        Escrever ("PID {0,-6} {1,-12} {2,-12} {3}" -f $p.Pid, $p.Nome, $idade, $linha)

        if ($p.Nome -ne 'chrome.exe' -and $p.Nome -ne 'msedge.exe') { continue }
        if ($p.Linha -notmatch '(?i)--user-data-dir=\S*\\Argos\\|--user-data-dir="[^"]*\\Argos\\') { continue }
        $automacao = $p.Linha -match '--enable-automation|--remote-debugging-pipe|--remote-debugging-port'
        if (-not $automacao) {
            Problema '    [!] Chrome aberto A MAO no perfil do vigia. Enquanto essa janela estiver'
            Problema '        aberta, o vigia nao consegue abrir o perfil e a rodada falha ou trava.'
            Problema '        Feche essa janela (o login fica salvo no perfil). O script nao fecha.'
        } elseif (-not (Get-Process -Id $p.Pai -ErrorAction SilentlyContinue)) {
            Problema '    [!] Chrome de automacao ORFAO no perfil do vigia (o processo que o abriu morreu).'
            [void]$reparos.Add([pscustomobject]@{ Tipo = 'Matar'; Pids = @([int]$p.Pid)
                Texto = "Fechar o Chrome de automacao orfao (PID $($p.Pid)) que segura o perfil do vigia" })
        }
    }
} else {
    if (-not $rProc.Respondeu) { Escrever '[!] O WMI nao respondeu: sem linha de comando. Plano B (Get-Process):' }
    else { Escrever "[!] Nao consegui listar pelo WMI ($($rProc.Erro)). Plano B (Get-Process):" }
    foreach ($n in 'node', 'python', 'pythonw', 'chrome', 'powershell') {
        $lista = @(Get-Process -Name $n -ErrorAction SilentlyContinue)
        if ($lista.Count -eq 0) { continue }
        $velho = $lista | Sort-Object StartTime | Select-Object -First 1
        Escrever ("    {0,-11} {1,3} processo(s), o mais antigo desde {2}" -f $n, $lista.Count, (Quando $velho.StartTime))
    }
}

# ------------------------------------------------------------ logs
Titulo "LOGS ($PastaLogs)"
$logsVigias = @()
if (Test-Path -LiteralPath $PastaLogs) {
    $logsVigias = @(Get-ChildItem -LiteralPath $PastaLogs -File -Filter '*.log' |
        Where-Object { $_.Name -match '(?i)vigia|acoes|tiktok|guardi' } | Sort-Object Name)
}
if ($logsVigias.Count -eq 0) { Escrever 'Nenhum log de vigia encontrado.' }
foreach ($a in $logsVigias) {
    Escrever ''
    Escrever ("{0}   ultima escrita {1} (ha {2} min)" -f $a.Name, (Quando $a.LastWriteTime), (Minutos $a.LastWriteTime))
    try {
        Get-Content -LiteralPath $a.FullName -Tail 8 -Encoding UTF8 | ForEach-Object { Escrever "    $_" }
    } catch {
        Escrever "    (nao consegui ler: $($_.Exception.Message))"
    }
}

# ------------------------------------------------------------ eventos
Titulo "EVENTOS DAS ULTIMAS $HorasEventos H"
$desde = $agora.AddHours(-$HorasEventos)
# 41 desligou sem aviso, 42/107 dormiu/acordou, 1074 reinicio pedido,
# 6005/6006/6008 ligou/desligou/desligou mal, 7011 servico nao respondeu,
# 7031/7034 servico caiu (o spooler aparece aqui quando o driver derruba).
try {
    $ev = @(Get-WinEvent -FilterHashtable @{ LogName = 'System'; StartTime = $desde
            Id = @(41, 42, 107, 1074, 6005, 6006, 6008, 7011, 7031, 7034) } -MaxEvents 40 -ErrorAction Stop)
    foreach ($e in ($ev | Sort-Object TimeCreated)) {
        Escrever ("{0}  {1,5}  {2}" -f $e.TimeCreated.ToString('dd/MM HH:mm'), $e.Id, (PrimeiraLinha $e.Message))
    }
} catch {
    Escrever 'Sistema: nenhum desligamento, sono ou servico caido no periodo.'
}
Escrever ''
# 322 = o Agendador IGNOROU a rodada porque a anterior ainda rodava - e a
# prova direta da suspeita 1. 329 = encerrada pelo limite de tempo.
try {
    $evt = @(Get-WinEvent -FilterHashtable @{ LogName = 'Microsoft-Windows-TaskScheduler/Operational'
            StartTime = $desde; Id = @(101, 103, 111, 202, 203, 322, 329, 332) } -MaxEvents 500 -ErrorAction Stop |
        Where-Object { $_.Message -match '(?i)argos' })
    $ignoradas = @($evt | Where-Object { $_.Id -eq 322 })
    if ($ignoradas.Count -gt 0) {
        Problema ("[!] O Agendador IGNOROU {0} rodada(s) porque a anterior ainda estava rodando." -f $ignoradas.Count)
    }
    foreach ($e in ($evt | Sort-Object TimeCreated | Select-Object -Last 15)) {
        Escrever ("{0}  {1,5}  {2}" -f $e.TimeCreated.ToString('dd/MM HH:mm'), $e.Id, (PrimeiraLinha $e.Message))
    }
    if ($evt.Count -eq 0) { Escrever 'Agendador: nenhuma falha, encerramento ou rodada ignorada de tarefa Argos.' }
} catch {
    Escrever 'Agendador: historico desligado ou vazio (Agendador > "Habilitar historico de'
    Escrever '           todas as tarefas" liga; ajuda no proximo diagnostico).'
}

# ------------------------------------------------------------ e-mail
Titulo 'E-MAIL DOS AVISOS (SMTP)'
$faltam = @()
foreach ($v in 'SMTP_HOST', 'SMTP_USER', 'SMTP_PASS') {
    $onde = @()
    foreach ($escopo in 'Process', 'User', 'Machine') {
        if ([Environment]::GetEnvironmentVariable($v, $escopo)) { $onde += $escopo }
    }
    if ($onde.Count -eq 0) { $faltam += $v; Escrever "    $v ... nao esta em variavel de ambiente" }
    else { Escrever "    $v ... definida ($($onde -join ', '))" }
}
$credSmtp = @(& cmdkey /list 2>$null | Where-Object { $_ -match '(?i)smtp' })
if ($credSmtp.Count -gt 0) { Escrever "    Gerenciador de Credenciais: $($credSmtp.Count) entrada(s) com 'smtp' no nome" }
if ($faltam.Count -gt 0 -and $credSmtp.Count -eq 0) {
    Escrever '[PENDENTE] Sem SMTP o guardiao so avisa na tela desta maquina. Falta decidir'
    Escrever '           qual conta envia e guardar SMTP_HOST/USER/PASS no cofre do Argos.'
    Escrever '           Isto e configuracao, nao defeito: o -Reparar nao mexe aqui, e senha'
    Escrever '           nunca vai para o Git.'
}

# ------------------------------------------------------------ plano
if ($spoolerTravado) {
    [void]$reparos.Insert(0, [pscustomobject]@{ Tipo = 'Spooler'
        Texto = 'Reiniciar o spooler de impressao (sem apagar trabalhos da fila)' })
}
# Ordem: primeiro destravar (matar, spooler), depois ajustar, por ultimo rodar.
$ordem   = @{ 'Spooler' = 0; 'Parar' = 1; 'Matar' = 2; 'Ajustar' = 3; 'Rodar' = 4 }
$reparos = @($reparos | Sort-Object { $ordem[$_.Tipo] })

Titulo 'PLANO'
if ($reparos.Count -eq 0) {
    Escrever 'Nada a reparar nos vigias.'
} else {
    $n = 0
    foreach ($r in $reparos) { $n++; Escrever ("{0}. {1}" -f $n, $r.Texto) }
}
if ($wmiTravado) {
    Escrever ''
    Escrever 'Fora do plano: o WMI nao respondeu. Se continuar depois do reparo,'
    Escrever 'reinicie a maquina fora do horario de expedicao.'
}

if (-not $Reparar -or $reparos.Count -eq 0) {
    if ($reparos.Count -gt 0) {
        Escrever ''
        Escrever 'Nada foi alterado. Para aplicar o plano, rode de novo com -Reparar.'
    }
    Escrever ''
    if ($script:Problemas -eq 0) { Escrever 'VEREDITO: vigias em dia.' }
    else { Escrever "VEREDITO: $($script:Problemas) apontamento(s). Veja acima." }
    Salvar
    if ($script:Problemas -eq 0) { exit 0 } else { exit 1 }
}

# ------------------------------------------------------------ reparo
Titulo 'REPARO'
$script:Problemas = 0
$falhas = 0

# Checkpoint: XML de cada vigia antes de qualquer mudanca.
$pastaCk = Join-Path $Checkpoints "$($script:Carimbo)_vigias"
$comCheckpoint = @{}
try {
    New-Item -ItemType Directory -Path $pastaCk -Force | Out-Null
    foreach ($t in @($tarefas | Where-Object { $Vigias -contains $_.Nome })) {
        $destino = Join-Path $pastaCk (($t.Nome -replace '[\\/:*?"<>|]', '_') + '.xml')
        $cod = "`$s = New-Object -ComObject Schedule.Service; `$s.Connect()`n" +
               "`$t = `$s.GetFolder('\').GetTask($(Lit $t.Caminho))`n" +
               "[IO.File]::WriteAllText($(Lit $destino), `$t.Xml, [Text.Encoding]::Unicode); 'ok'"
        $r = ComLimite $cod 60
        if ($r.Ok -and (Test-Path -LiteralPath $destino)) { $comCheckpoint[$t.Caminho] = $true }
    }
    Escrever "[OK] Checkpoint das tarefas em $pastaCk"
} catch {
    Escrever "[!] Nao consegui criar o checkpoint em $pastaCk : $($_.Exception.Message)"
    Escrever '    Sem checkpoint, nenhuma tarefa sera regravada (so destravar e rodar).'
}

$inicioReparo = Get-Date
foreach ($r in $reparos) {
    Escrever ''
    Escrever "-> $($r.Texto)"
    switch ($r.Tipo) {
        'Spooler' {
            if (-not $admin) {
                $falhas++
                Escrever '   [!] Precisa de administrador. Abra o PowerShell como administrador e'
                Escrever '       rode de novo com -Reparar.'
                break
            }
            & sc.exe stop Spooler | Out-Null
            $sv = Get-Service -Name Spooler
            try { $sv.WaitForStatus('Stopped', [TimeSpan]::FromSeconds(20)) } catch { }
            $sv.Refresh()
            if ($sv.Status -ne 'Stopped') {
                Escrever '   O spooler nao parou em 20 s; encerrando o spoolsv.exe.'
                & taskkill.exe /IM spoolsv.exe /F | Out-Null
                Start-Sleep -Seconds 3
            }
            try { Start-Service -Name Spooler } catch { Escrever "   $($_.Exception.Message)" }
            $sv.Refresh()
            $teste = ComLimite $codWinspool 45
            if ($sv.Status -eq 'Running' -and $teste.Ok) {
                Escrever '   [OK] Spooler de volta e respondendo.'
            } else {
                $falhas++
                Escrever "   [!] Spooler: $($sv.Status), respondeu: $($teste.Respondeu). Reinicie a maquina."
            }
        }
        'Parar' {
            # Primeiro a arvore (o Chrome e filho do vigia), depois o estado no Agendador.
            foreach ($id in $r.Pids) {
                if (Get-Process -Id $id -ErrorAction SilentlyContinue) {
                    & taskkill.exe /PID $id /T /F 2>&1 | Out-Null
                }
            }
            $cod = "`$s = New-Object -ComObject Schedule.Service; `$s.Connect()`n" +
                   "`$s.GetFolder('\').GetTask($(Lit $r.Caminho)).Stop(0); 'ok'"
            [void](ComLimite $cod 60)
            Start-Sleep -Seconds 3
            $vivos = @($r.Pids | Where-Object { Get-Process -Id $_ -ErrorAction SilentlyContinue })
            if ($vivos.Count -eq 0) { Escrever '   [OK] Rodada presa encerrada.' }
            else { $falhas++; Escrever "   [!] Continua vivo: PID $($vivos -join ', ')." }
        }
        'Matar' {
            foreach ($id in $r.Pids) { & taskkill.exe /PID $id /T /F 2>&1 | Out-Null }
            Start-Sleep -Seconds 2
            $vivos = @($r.Pids | Where-Object { Get-Process -Id $_ -ErrorAction SilentlyContinue })
            if ($vivos.Count -eq 0) { Escrever '   [OK] Fechado.' }
            else { $falhas++; Escrever "   [!] Continua vivo: PID $($vivos -join ', ')." }
        }
        'Ajustar' {
            if (-not $comCheckpoint.ContainsKey($r.Caminho)) {
                $falhas++
                Escrever '   [!] Sem checkpoint desta tarefa: nao regravo.'
                break
            }
            $idx   = $r.Caminho.LastIndexOf('\')
            $pasta = '\'
            if ($idx -gt 0) { $pasta = $r.Caminho.Substring(0, $idx) }
            $nomeT = $r.Caminho.Substring($idx + 1)
            $linhas = @(
                "`$s = New-Object -ComObject Schedule.Service; `$s.Connect()",
                "`$f = `$s.GetFolder($(Lit $pasta))",
                "`$d = `$f.GetTask($(Lit $nomeT)).Definition",
                "`$d.Settings.StartWhenAvailable = `$true"
            )
            if ($r.Limite)  { $linhas += "`$d.Settings.ExecutionTimeLimit = $(Lit $r.Limite)" }
            if ($r.Religar) { $linhas += "`$d.Settings.Enabled = `$true" }
            # 4 = TASK_UPDATE. Mesmo usuario e mesmo tipo de logon; sem senha.
            $linhas += "[void]`$f.RegisterTaskDefinition($(Lit $nomeT), `$d, 4, `$d.Principal.UserId, `$null, `$d.Principal.LogonType)"
            $linhas += "`$n = `$f.GetTask($(Lit $nomeT))"
            $linhas += "'LIDO|' + `$n.Definition.Settings.ExecutionTimeLimit + '|' + `$n.Enabled + '|' + `$n.Definition.Settings.StartWhenAvailable"
            $res = ComLimite ($linhas -join "`n") 60
            $lido = $res.Saida -split "`r?`n" | Where-Object { $_ -like 'LIDO|*' } | Select-Object -Last 1
            if (-not $res.Ok -or -not $lido) {
                $falhas++
                $motivo = $res.Erro
                if (-not $res.Respondeu) { $motivo = 'o Agendador nao respondeu' }
                Escrever "   [!] Nao consegui regravar: $motivo"
                Escrever "       O XML original esta em $pastaCk"
                break
            }
            $c = $lido -split '\|'
            $ok = ($c[3] -eq 'True') -and ((-not $r.Limite) -or ($c[1] -eq $r.Limite)) -and ((-not $r.Religar) -or ($c[2] -eq 'True'))
            if ($ok) { Escrever ("   [OK] Lido de volta: limite {0}, ligada {1}, rodar se perder o horario {2}." -f $c[1], $c[2], $c[3]) }
            else { $falhas++; Escrever "   [!] O Windows nao confirmou: $lido" }
        }
        'Rodar' {
            $cod = "`$s = New-Object -ComObject Schedule.Service; `$s.Connect()`n" +
                   "[void]`$s.GetFolder('\').GetTask($(Lit $r.Caminho)).Run(`$null); 'ok'"
            $res = ComLimite $cod 60
            if ($res.Ok) { Escrever '   Disparada. Conferindo no fim.' }
            else { $falhas++; Escrever "   [!] Nao disparou: $($res.Erro)" }
        }
    }
}

# Leitura de volta: a tarefa disparada precisa aparecer rodando ou com
# "ultima vez" depois do inicio do reparo.
$paraConferir = @($reparos | Where-Object { $_.Tipo -eq 'Rodar' } | ForEach-Object { $_.Caminho })
if ($paraConferir.Count -gt 0) {
    Escrever ''
    Escrever 'Conferindo se os vigias rodaram (ate 2 min)...'
    $confirmadas = @{}
    $limiteEspera = (Get-Date).AddMinutes(2)
    do {
        Start-Sleep -Seconds 15
        foreach ($t in (LerJson (ComLimite $codInventario 90))) {
            if ($paraConferir -notcontains $t.Caminho) { continue }
            $u = LerData $t.Ultima
            if ([int]$t.Estado -eq 4 -or ($u -and $u -ge $inicioReparo.AddSeconds(-5))) {
                $confirmadas[$t.Caminho] = "$($estados[[int]$t.Estado]), ultima vez $(Quando $u), resultado $($t.Resultado)"
            }
        }
    } while ($confirmadas.Count -lt $paraConferir.Count -and (Get-Date) -lt $limiteEspera)
    foreach ($c in $paraConferir) {
        if ($confirmadas.ContainsKey($c)) { Escrever "[OK] $c - $($confirmadas[$c])" }
        else { $falhas++; Escrever "[!] $c - nao apareceu rodando. Veja o log dele e o Agendador." }
    }
    foreach ($a in $logsVigias) {
        $a.Refresh()
        if ($a.LastWriteTime -ge $inicioReparo) { Escrever "     log andou: $($a.Name) ($(Quando $a.LastWriteTime))" }
    }
}

Escrever ''
if ($falhas -eq 0) {
    Escrever 'VEREDITO: reparo aplicado e conferido. O guardiao deve parar de acusar'
    Escrever '          "ATRASADO" na proxima rodada dele.'
} else {
    Escrever "VEREDITO: $falhas item(ns) nao voltaram. Veja acima."
}
Salvar
if ($falhas -eq 0) { exit 0 } else { exit 1 }
