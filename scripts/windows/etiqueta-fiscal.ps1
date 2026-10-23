#Requires -Version 5.1
<#
    etiqueta-fiscal.ps1 - Diagnostico e reparo da BIXOLON 'Etiqueta Fiscal'
    na HUDSONINTEGRAR, sem depender do WMI.

    O aviso que motivou (22/10, 17:34): o guardiao "nao conseguiu ler as
    impressoras do Windows: o PowerShell nao respondeu em 60 s". O guardiao le
    as impressoras com Get-Printer, que passa pelo WMI E pelo spooler: se
    qualquer um dos dois trava, ele so sabe dizer "nao respondeu". Este script
    separa as causas, da mais grave para a menos:

      1. SPOOLER TRAVADO: a fila nao responde nem pelo winspool. Nada imprime,
         e o agente de notas fiscais fica parado esperando o SumatraPDF.
      2. FILA EM PORTA MORTA: a 'Etiqueta Fiscal' aponta para uma porta USB sem
         impressora ligada (doc 15, caso de 14/09). A fila ACEITA o trabalho e
         nao imprime nada, sem erro nenhum.
      3. JOB PRESO ou FILA PAUSADA: um trabalho parado segura os seguintes.
      4. AGENTE PARADO: a tarefa 'ARGOS - Notas Fiscais' nao esta rodando, ou
         ha PDF esperando na Entrada ha minutos.
      5. WMI TRAVADO: o winspool responde e o Get-Printer nao. A impressora
         pode estar imprimindo normalmente; quem trava e a leitura do guardiao.

    Cada teste roda num powershell.exe SEPARADO e e encerrado no limite de
    tempo: o script nao trava junto com o que ele esta testando.

    Sem -Reparar: SOMENTE LEITURA. Mostra o diagnostico e o plano.
    Com -Reparar, e so no que o diagnostico apontou:
      - reinicia o spooler se ele nao responde (precisa de administrador).
        NAO apaga trabalho de impressao: pode ser etiqueta de pedido faturado;
      - fecha SumatraPDF de impressao que continua travado depois disso (sem
        janela, aberto ha mais de 10 min). Visualizador aberto a mao fica;
      - retoma a fila fiscal se ela estiver pausada;
      - religa a fila fiscal na porta viva SO quando nao ha duvida: ela e a
        unica fila em porta morta e existe uma unica porta USB viva sem fila.
        Com qualquer duvida, para e manda rodar 7-nomear-impressoras.ps1
        -Identificar, que tira a duvida imprimindo um papel por fila;
      - dispara a tarefa 'ARGOS - Notas Fiscais' se ela nao estiver rodando;
      - le tudo de volta: so diz [OK] se o Windows confirmar.
    Nunca: apaga trabalho, remove ou renomeia fila, muda a impressora padrao,
    reinicia a maquina ou o WMI, abre o UpSeller.

    Uso:
      # diagnostico (nao muda nada)
      powershell -ExecutionPolicy Bypass -File .\etiqueta-fiscal.ps1

      # diagnostico + reparo (PowerShell como ADMINISTRADOR)
      powershell -ExecutionPolicy Bypass -File .\etiqueta-fiscal.ps1 -Reparar

    Saida: 0 = imprimindo, 1 = achou problema (ou algo nao voltou).
#>
[CmdletBinding()]
param(
    [switch]$Reparar,
    [switch]$Forcar,
    [string]$Maquina      = 'HUDSONINTEGRAR',
    [string]$Fila         = 'Etiqueta Fiscal',
    [string]$PastaNotas   = 'C:\Argos\NotasFiscais',
    [string]$Tarefa       = 'ARGOS - Notas Fiscais',
    [int]   $MinutosPreso = 15,
    [string]$Log
)

$ErrorActionPreference = 'Stop'
$script:Linhas    = New-Object System.Collections.ArrayList
$script:Problemas = 0

# Com OneDrive a Area de Trabalho vira "...\OneDrive\Area de Trabalho" e
# "$env:USERPROFILE\Desktop" nao existe.
if (-not $Log) {
    $desk = [Environment]::GetFolderPath('Desktop')
    if (-not $desk -or -not (Test-Path -LiteralPath $desk)) { $desk = $env:USERPROFILE }
    $Log = Join-Path $desk "etiqueta-fiscal-$(Get-Date -Format 'yyyyMMdd-HHmm').txt"
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
# Texto entre aspas simples para colar dentro do codigo do processo filho.
function Lit([string]$Texto) { "'" + $Texto.Replace("'", "''") + "'" }
function PrimeiraLinha([string]$Texto) {
    if (-not $Texto) { return '' }
    $l = ($Texto -split "`r?`n" | Where-Object { $_.Trim() } | Select-Object -First 1)
    if ($l.Length -gt 160) { $l = $l.Substring(0, 160) + '...' }
    $l
}

# Roda $Codigo num powershell.exe SEPARADO e mata o processo se passar de
# $Segundos. Start-Job nao serve: Stop-Job tambem fica esperando a chamada
# travada terminar.
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
        return [pscustomobject]@{ Respondeu = $false; Ok = $false; Saida = ''; Erro = ''; Segundos = $Segundos }
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
# Filas e trabalhos pelo System.Printing: fala com o spooler pelo winspool, sem
# passar pelo WMI. Se ESTE trava, o problema e o spooler.
$codFilas = @'
Add-Type -AssemblyName System.Printing
$srv   = New-Object System.Printing.LocalPrintServer
$tipos = [System.Printing.EnumeratedPrintQueueTypes[]]@('Local')
$saida = foreach ($q in $srv.GetPrintQueues($tipos)) {
    $porta = ''; $driver = ''
    try { $porta = $q.QueuePort.Name } catch { }
    try { $driver = $q.QueueDriver.Name } catch { }
    $trabalhos = @()
    try {
        $trabalhos = @(foreach ($j in $q.GetPrintJobInfoCollection()) {
            # TimeJobSubmitted vem em UTC (JOB_INFO.Submitted) sem marcar o Kind.
            $quando = [datetime]::SpecifyKind($j.TimeJobSubmitted, 'Utc').ToLocalTime().ToString('s')
            [pscustomobject]@{ Id = [int]$j.JobIdentifier; Nome = [string]$j.Name; Estado = [string]$j.JobStatus
                Enviado = $quando; Paginas = [int]$j.NumberOfPages; Dono = [string]$j.Submitter }
        })
    } catch { }
    [pscustomobject]@{
        Nome = [string]$q.Name; Porta = [string]$porta; Driver = [string]$driver
        Estado = [string]$q.QueueStatus; Pausada = [bool]$q.IsPaused; Offline = [bool]$q.IsOffline
        ComErro = [bool]$q.IsInError; Trabalhos = $trabalhos
    }
}
ConvertTo-Json -InputObject @($saida) -Depth 4 -Compress
'@

# Portas USB que tem impressora LIGADA agora. O instance id de cada USBPRINT
# termina no nome da porta: USBPRINT\BIXOLON_XD3-40T\6&36A51FC3&2&USB002.
# pnputil nao passa pelo WMI; o Get-PnpDevice (WMI) e so o plano B.
$codPortas = @'
$texto = ''
try { $texto = (& pnputil.exe /enum-devices /connected 2>$null) -join "`n" } catch { }
if ($texto -match 'USB\\') {
    'FONTE|pnputil'
    $ids = @([regex]::Matches($texto, 'USBPRINT\\\S+') | ForEach-Object { $_.Value })
    $bix = @([regex]::Matches($texto, 'USB\\VID_1504\S*') | ForEach-Object { $_.Value } | Select-Object -Unique)
} else {
    'FONTE|Get-PnpDevice'
    $todos = @(Get-PnpDevice -PresentOnly | ForEach-Object { $_.InstanceId })
    $ids = @($todos | Where-Object { $_ -like 'USBPRINT\*' })
    $bix = @($todos | Where-Object { $_ -like 'USB\VID_1504*' })
}
'BIXOLON|' + $bix.Count
$saida = foreach ($id in ($ids | Select-Object -Unique)) {
    if ($id -match '(USB\d+)$') { [pscustomobject]@{ Porta = $Matches[1]; Id = $id } }
}
ConvertTo-Json -InputObject @($saida) -Compress
'@

$codWmi        = "(Get-CimInstance Win32_OperatingSystem -OperationTimeoutSec 25).LastBootUpTime.ToString('s')"
$codGetPrinter = "@(Get-Printer).Count"

# A tarefa do agente de notas fiscais, pelo COM do Agendador (sem WMI).
$codAgente = @"
`$nome = $(Lit $Tarefa)
`$s = New-Object -ComObject Schedule.Service
`$s.Connect()
`$t = `$null
try { `$t = `$s.GetFolder('\').GetTask(`$nome) } catch { }
function Acha(`$pasta) {
    try { foreach (`$x in `$pasta.GetTasks(1)) { if (`$x.Name -eq `$nome) { return `$x } } } catch { }
    try { foreach (`$sub in `$pasta.GetFolders(0)) { if (`$sub.Path -notlike '\Microsoft*') { `$r = Acha `$sub; if (`$r) { return `$r } } } } catch { }
    `$null
}
if (-not `$t) { `$t = Acha (`$s.GetFolder('\')) }
`$lista = @()
if (`$t) {
    `$lista = @([pscustomobject]@{ Caminho = `$t.Path; Ativa = [bool]`$t.Enabled; Estado = [int]`$t.State
        Ultima = `$t.LastRunTime.ToString('s'); Resultado = ('0x{0:X8}' -f `$t.LastTaskResult) })
}
ConvertTo-Json -InputObject @(`$lista) -Compress
"@

$estadosTarefa = @{ 0 = 'desconhecido'; 1 = 'DESLIGADA'; 2 = 'na fila'; 3 = 'pronta (PARADA)'; 4 = 'rodando' }

# ------------------------------------------------------------ trava de dono
if ($env:COMPUTERNAME -ne $Maquina -and -not $Forcar) {
    Write-Host ''
    Write-Host "  PARE: esta maquina e $env:COMPUTERNAME, nao a $Maquina." -ForegroundColor Red
    Write-Host "  A '$Fila' fica la. Se e mesmo nesta maquina que voce quer rodar,"  -ForegroundColor Red
    Write-Host '  repita com -Forcar.'                                                -ForegroundColor Red
    Write-Host ''
    exit 1
}

Escrever "Etiqueta Fiscal: diagnostico da impressao das notas"
Escrever "$(Get-Date -Format 'dd/MM/yyyy HH:mm')   Maquina: $env:COMPUTERNAME   Usuario: $env:USERNAME   Fila: $Fila"
if ($Reparar) {
    Escrever 'MODO REPARAR - aplica o plano no fim do diagnostico'
} else {
    Escrever 'MODO DIAGNOSTICO - somente leitura (use -Reparar para aplicar o plano)'
}
$admin = EhAdmin
if (-not $admin) {
    Escrever '[!] Rodando SEM administrador: o diagnostico funciona, mas reiniciar o'
    Escrever '    spooler e mudar a porta da fila vao ser recusados.'
}

# ------------------------------------------------------------ spooler e WMI
Titulo 'O WINDOWS ESTA RESPONDENDO?'
Escrever 'Cada teste roda em processo separado; se travar, e encerrado no limite.'
Escrever ''
$spooler = Get-Service -Name Spooler
Escrever ("[{0}] Servico Spooler: {1}" -f $(if ($spooler.Status -eq 'Running') { 'OK' } else { '!!' }), $spooler.Status)
if ($spooler.Status -ne 'Running') { $script:Problemas++ }
$rFilas     = Testar 'Spooler pelo winspool (filas e trabalhos, sem WMI)'   $codFilas      45
$rGetPrint  = Testar 'Get-Printer (o mesmo teste do guardiao, pelo WMI)'    $codGetPrinter 60
$rWmi       = Testar 'WMI (Win32_OperatingSystem)'                          $codWmi        40
$rPortas    = Testar 'Portas USB com impressora ligada'                     $codPortas     60

$spoolerTravado = ($spooler.Status -ne 'Running') -or -not $rFilas.Respondeu
$wmiTravado     = -not $rWmi.Respondeu -or (-not $rGetPrint.Respondeu -and $rFilas.Respondeu)
Escrever ''
if ($spoolerTravado) {
    Escrever 'LEITURA: o SPOOLER nao responde. Nenhuma impressora imprime, e o agente de'
    Escrever '         notas fiscais fica parado esperando. O -Reparar reinicia o spooler'
    Escrever '         sem apagar os trabalhos da fila.'
} elseif ($wmiTravado) {
    Escrever 'LEITURA: o spooler responde, o WMI nao. E por isso que o guardiao "nao'
    Escrever '         consegue ler as impressoras": ele pergunta pelo WMI. A impressao'
    Escrever '         em si pode estar normal - veja a fila e a Entrada abaixo. O WMI so'
    Escrever '         volta reiniciando a maquina, fora do horario de expedicao.'
}

# ------------------------------------------------------------ a fila fiscal
$filas  = @(LerJson $rFilas)
$fiscal = $filas | Where-Object { $_.Nome -eq $Fila } | Select-Object -First 1

$fontePortas = (($rPortas.Saida -split "`r?`n" | Where-Object { $_ -like 'FONTE|*' } | Select-Object -First 1) -replace '^FONTE\|', '')
$qtdBixolon  = (($rPortas.Saida -split "`r?`n" | Where-Object { $_ -like 'BIXOLON|*' } | Select-Object -First 1) -replace '^BIXOLON\|', '')
$vivas       = @(LerJson $rPortas | ForEach-Object { $_.Porta } | Select-Object -Unique)

# Fila que o Windows cria sozinho quando a impressora volta numa porta nova
# (doc 15): nao conta como "dona" da porta.
function EhDuplicada([string]$Nome) {
    ($Nome -ne $Fila) -and ($Nome -match '(?i)^BIXOLON XD3-40t|#\d+$|\((Copiar|Copia|Copy) \d+\)')
}

Titulo "FILA '$Fila'"
$reparos  = New-Object System.Collections.ArrayList
$jobsPresos = @()
if (-not $rFilas.Ok) {
    Escrever 'Sem resposta do spooler: nao da para ler a fila nem os trabalhos.'
} elseif (-not $fiscal) {
    Problema "[ERRO] Nao existe fila '$Fila' nesta maquina. Filas parecidas:"
    foreach ($q in ($filas | Where-Object { $_.Nome -match '(?i)BIXOLON|Etiqueta|Codigo|Fiscal' -or $_.Driver -match '(?i)BIXOLON|BPL' })) {
        Escrever ("    {0,-38} porta={1,-8} driver={2}" -f $q.Nome, $q.Porta, $q.Driver)
    }
    Escrever '    Foi renomeada ou o Windows recriou com outro nome? Rode 7-nomear-impressoras.ps1.'
} else {
    $estadoFila = $fiscal.Estado
    if (-not $estadoFila -or $estadoFila -eq 'None') { $estadoFila = 'normal' }
    Escrever ("Porta ........: {0}" -f $fiscal.Porta)
    Escrever ("Driver .......: {0}" -f $fiscal.Driver)
    Escrever ("Estado .......: {0}" -f $estadoFila)
    if ($fiscal.Pausada) {
        Problema '[!] A fila esta PAUSADA: aceita trabalho e nao imprime.'
        [void]$reparos.Add([pscustomobject]@{ Tipo = 'Retomar'; Texto = "Retomar a fila '$Fila' (estava pausada)" })
    }
    if ($fiscal.Offline) { Problema '[!] A fila esta OFFLINE: impressora desligada, sem papel/ribbon ou cabo solto.' }
    if ($fiscal.ComErro) { Problema '[!] A fila esta EM ERRO: confira papel, ribbon e a tampa da impressora.' }

    $trabalhos = @($fiscal.Trabalhos | Where-Object { $_ })
    Escrever ("Trabalhos ....: {0}" -f $trabalhos.Count)
    foreach ($j in $trabalhos) {
        $enviado = LerData $j.Enviado
        $idade   = ''
        if ($enviado) { $idade = "ha $(Minutos $enviado) min" }
        Escrever ("    #{0,-5} {1,-14} {2,-12} {3}" -f $j.Id, $j.Estado, $idade, $j.Nome)
        if (($enviado -and (Minutos $enviado) -ge $MinutosPreso) -or $j.Estado -match '(?i)Error|Blocked|Offline|Paused|UserIntervention') {
            $jobsPresos += $j
        }
    }
    if ($jobsPresos.Count -gt 0) {
        Problema ("[!] {0} trabalho(s) parado(s) na fila (mais de {1} min ou em erro)." -f $jobsPresos.Count, $MinutosPreso)
        Problema  '    Eles seguram os seguintes. O script NAO apaga trabalho: pode ser etiqueta'
        Problema  '    de pedido faturado. Se depois do reparo continuarem parados, quem decide'
        Problema  "    e a pessoa: Configuracoes > Impressoras > '$Fila' > Abrir fila."
    }
}

# ------------------------------------------------------------ portas USB
Titulo 'IMPRESSORAS USB LIGADAS AGORA'
$portaMorta = $false
if (-not $rPortas.Ok) {
    Escrever 'Nao consegui listar os dispositivos USB: sem isso nao da para saber se a'
    Escrever 'porta da fila esta viva. Nada sobre portas sera reparado.'
} else {
    Escrever ("Fonte: {0}   Dispositivos BIXOLON (VID_1504) no USB: {1}" -f $fontePortas, $qtdBixolon)
    if ($vivas.Count -eq 0) {
        Problema '[ERRO] NENHUMA impressora USB ligada. Confira se a BIXOLON fiscal esta ligada'
        Problema '       na tomada e com o cabo USB no computador. Sem isso nada mais adianta.'
    }
    foreach ($porta in $vivas) {
        $donas = @($filas | Where-Object { $_.Porta -eq $porta } | ForEach-Object { $_.Nome })
        $txt = 'SEM FILA'
        if (-not $rFilas.Ok) { $txt = '(filas nao lidas: spooler sem resposta)' }
        elseif ($donas.Count) { $txt = $donas -join ', ' }
        Escrever ("    {0}  ->  {1}" -f $porta, $txt)
    }
    if ($fiscal -and $rFilas.Ok -and $vivas.Count -gt 0) {
        if ($vivas -contains $fiscal.Porta) {
            Escrever ''
            Escrever "[OK] A '$Fila' esta numa porta com impressora ligada ($($fiscal.Porta))."
        } elseif ($fiscal.Porta -match '^USB\d+$') {
            $portaMorta = $true
            Escrever ''
            Problema "[ERRO] A '$Fila' aponta para $($fiscal.Porta), que NAO tem impressora ligada."
            Problema '       A fila aceita o trabalho e nao imprime nada (doc 15).'

            # So religa sem duvida: a fiscal e a UNICA fila em porta morta e ha UMA
            # unica porta viva sem dona (ou so com a duplicada que o Windows criou).
            $mortas = @($filas | Where-Object {
                $_.Porta -match '^USB\d+$' -and $vivas -notcontains $_.Porta -and -not (EhDuplicada $_.Nome) })
            $orfas  = @($vivas | Where-Object {
                $p = $_
                @($filas | Where-Object { $_.Porta -eq $p -and -not (EhDuplicada $_.Nome) }).Count -eq 0 })
            if ($mortas.Count -eq 1 -and $orfas.Count -eq 1) {
                [void]$reparos.Add([pscustomobject]@{ Tipo = 'Porta'; Porta = $orfas[0]
                    Texto = "Religar a '$Fila' de $($fiscal.Porta) (morta) para $($orfas[0]) (viva e sem fila)" })
                $dup = @($filas | Where-Object { $_.Porta -eq $orfas[0] -and (EhDuplicada $_.Nome) })
                foreach ($d in $dup) {
                    Escrever "       O Windows criou a fila '$($d.Nome)' nessa porta. Ela fica (o script nao"
                    Escrever "       remove fila); depois de conferir, apague: Remove-Printer -Name '$($d.Nome)'"
                }
            } else {
                Problema ("       Nao da para saber sozinho qual porta e a fiscal ({0} fila(s) em porta" -f $mortas.Count)
                Problema ("       morta, {0} porta(s) viva(s) sem fila). Rode, como administrador:" -f $orfas.Count)
                Problema '         .\7-nomear-impressoras.ps1 -Identificar'
                Problema '       Ele imprime um papel por fila e tira a duvida.'
            }
        } else {
            Escrever ''
            Escrever "[!] A '$Fila' esta na porta $($fiscal.Porta), que nao e USB: confira se e isso mesmo."
        }
    }
}

# ------------------------------------------------------------ agente e pasta
Titulo "AGENTE DE NOTAS FISCAIS ('$Tarefa')"
$rAgente = ComLimite $codAgente 60
$agente  = LerJson $rAgente | Select-Object -First 1
if (-not $rAgente.Respondeu) {
    Problema '[TRAVADO] O Agendador nao respondeu em 60 s: rode tambem o vigias-loja.ps1.'
} elseif (-not $rAgente.Ok) {
    Problema "[ERRO] Nao consegui ler o Agendador: $($rAgente.Erro)"
} elseif (-not $agente) {
    Problema "[ERRO] Nao existe a tarefa '$Tarefa'. O agente nao esta instalado:"
    Problema '       .\argos-notas-fiscais.ps1 -Instalar   (doc 18)'
} else {
    Escrever ("Tarefa .......: {0}" -f $agente.Caminho)
    Escrever ("Estado .......: {0}" -f $estadosTarefa[[int]$agente.Estado])
    Escrever ("Ultima vez ...: {0}   resultado {1}" -f (Quando (LerData $agente.Ultima)), $agente.Resultado)
    if (-not $agente.Ativa) {
        Problema '[ERRO] A tarefa esta DESLIGADA. Religue no Agendador (o script nao regrava tarefa).'
    } elseif ([int]$agente.Estado -ne 4) {
        Problema '[!] O agente NAO esta rodando: os PDFs da Entrada nao vao ser impressos.'
        [void]$reparos.Add([pscustomobject]@{ Tipo = 'Agente'; Caminho = $agente.Caminho
            Texto = "Disparar a tarefa '$Tarefa' (o agente estava parado)" })
    }
}

$entrada  = Join-Path $PastaNotas 'Entrada'
$pastaErr = Join-Path $PastaNotas 'Erro'
$parciais = @('.crdownload', '.tmp', '.part', '.partial', '.download')
function Esperando {
    @(Get-ChildItem -LiteralPath $entrada -File -ErrorAction SilentlyContinue |
        Where-Object { $parciais -notcontains $_.Extension.ToLower() -and $_.Name -notlike '~$*' })
}
Escrever ''
if (-not (Test-Path -LiteralPath $entrada)) {
    Escrever "[!] A pasta $entrada nao existe."
} else {
    $esperando = Esperando
    $atrasados = @($esperando | Where-Object { ((Get-Date) - $_.LastWriteTime).TotalMinutes -ge 2 })
    Escrever ("Entrada ......: {0} arquivo(s) esperando" -f $esperando.Count)
    foreach ($a in ($esperando | Sort-Object LastWriteTime | Select-Object -First 10)) {
        Escrever ("    {0}  (ha {1} min)" -f $a.Name, (Minutos $a.LastWriteTime))
    }
    if ($atrasados.Count -gt 0) {
        Problema ("[!] {0} arquivo(s) na Entrada ha mais de 2 min: o agente nao esta imprimindo." -f $atrasados.Count)
    }
}
$comErro = @(Get-ChildItem -LiteralPath $pastaErr -File -ErrorAction SilentlyContinue |
    Where-Object { $_.LastWriteTime -ge (Get-Date).AddHours(-24) })
if ($comErro.Count -gt 0) {
    Escrever ("Erro (24 h) ..: {0} arquivo(s) - o motivo de cada um esta no log abaixo" -f $comErro.Count)
    foreach ($a in ($comErro | Sort-Object LastWriteTime | Select-Object -Last 10)) { Escrever "    $($a.Name)" }
    Escrever '    Para reimprimir: confira no papel que NAO saiu e mova o arquivo de volta'
    Escrever "    para $entrada."
}

$sumatras = @(Get-Process -Name SumatraPDF -ErrorAction SilentlyContinue)
foreach ($s in $sumatras) {
    $idade = $null
    try { $idade = Minutos $s.StartTime } catch { }
    $tipo = 'janela aberta a mao'
    if ($s.MainWindowHandle -eq 0) { $tipo = 'impressao (sem janela)' }
    Escrever ("SumatraPDF ...: PID {0}, {1}, ha {2} min" -f $s.Id, $tipo, $idade)
    if ($s.MainWindowHandle -eq 0 -and $idade -ge 10) {
        Problema '[!] Impressao do SumatraPDF presa: o agente espera por ela e nao imprime mais nada.'
        if (-not ($reparos | Where-Object { $_.Tipo -eq 'Sumatra' })) {
            [void]$reparos.Add([pscustomobject]@{ Tipo = 'Sumatra'
                Texto = 'Fechar a impressao do SumatraPDF que continuar presa depois do spooler' })
        }
    }
}

$arqLog = Join-Path $env:LOCALAPPDATA 'Argos\notas-fiscais.log'
if (Test-Path -LiteralPath $arqLog) {
    $infoLog = Get-Item -LiteralPath $arqLog
    Escrever ''
    Escrever ("Log do agente ({0}, ultima escrita ha {1} min):" -f $arqLog, (Minutos $infoLog.LastWriteTime))
    try {
        Get-Content -LiteralPath $arqLog -Tail 10 -Encoding UTF8 | ForEach-Object { Escrever "    $_" }
    } catch {
        Escrever "    (nao consegui ler: $($_.Exception.Message))"
    }
}

# ------------------------------------------------------------ eventos
Titulo 'EVENTOS DAS ULTIMAS 24 H'
$desde = (Get-Date).AddHours(-24)
try {
    $ev = @(Get-WinEvent -FilterHashtable @{ LogName = 'System'; StartTime = $desde
            Id = @(7011, 7031, 7034) } -MaxEvents 200 -ErrorAction Stop |
        Where-Object { $_.Message -match '(?i)spooler' })
    foreach ($e in ($ev | Sort-Object TimeCreated | Select-Object -Last 10)) {
        Escrever ("{0}  {1,5}  {2}" -f $e.TimeCreated.ToString('dd/MM HH:mm'), $e.Id, (PrimeiraLinha $e.Message))
    }
    if ($ev.Count -eq 0) { Escrever 'Spooler: nenhuma queda registrada.' }
    else { Escrever "[!] O spooler caiu ou travou $($ev.Count) vez(es): costuma ser driver ou USB." }
} catch {
    Escrever 'Spooler: nenhuma queda registrada.'
}
try {
    $evp = @(Get-WinEvent -FilterHashtable @{ LogName = 'Microsoft-Windows-PrintService/Admin'
            StartTime = $desde; Level = @(1, 2, 3) } -MaxEvents 50 -ErrorAction Stop)
    foreach ($e in ($evp | Sort-Object TimeCreated | Select-Object -Last 8)) {
        Escrever ("{0}  {1,5}  {2}" -f $e.TimeCreated.ToString('dd/MM HH:mm'), $e.Id, (PrimeiraLinha $e.Message))
    }
} catch {
    Escrever 'Servico de impressao: nenhum erro registrado.'
}

# ------------------------------------------------------------ plano
if ($spoolerTravado) {
    [void]$reparos.Insert(0, [pscustomobject]@{ Tipo = 'Spooler'
        Texto = 'Reiniciar o spooler de impressao (sem apagar trabalhos da fila)' })
}
# Ordem: destravar o spooler, soltar o SumatraPDF, retomar, porta, agente.
$ordem   = @{ 'Spooler' = 0; 'Sumatra' = 1; 'Retomar' = 2; 'Porta' = 3; 'Agente' = 4 }
$reparos = @($reparos | Sort-Object { $ordem[$_.Tipo] })

Titulo 'PLANO'
if ($reparos.Count -eq 0) {
    Escrever 'Nada a reparar pelo script.'
} else {
    $n = 0
    foreach ($r in $reparos) { $n++; Escrever ("{0}. {1}" -f $n, $r.Texto) }
}
if ($wmiTravado) {
    Escrever ''
    Escrever 'Fora do plano: o WMI nao respondeu. O guardiao vai continuar avisando ate'
    Escrever 'reiniciar a maquina, fora do horario de expedicao.'
}

if (-not $Reparar -or $reparos.Count -eq 0) {
    if ($reparos.Count -gt 0) {
        Escrever ''
        Escrever 'Nada foi alterado. Para aplicar o plano, rode de novo com -Reparar'
        Escrever '(PowerShell como administrador).'
    }
    Escrever ''
    if ($script:Problemas -eq 0) { Escrever 'VEREDITO: Etiqueta Fiscal em ordem.' }
    else { Escrever "VEREDITO: $($script:Problemas) apontamento(s). Veja acima." }
    Salvar
    if ($script:Problemas -eq 0) { exit 0 } else { exit 1 }
}

# ------------------------------------------------------------ reparo
Titulo 'REPARO'
$falhas = 0
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
            $teste = ComLimite $codFilas 45
            if ($sv.Status -eq 'Running' -and $teste.Ok) {
                Escrever '   [OK] Spooler de volta e respondendo. Os trabalhos da fila continuam la.'
                Escrever '       Com o spooler travado nao deu para conferir a porta e a fila: rode o'
                Escrever '       diagnostico de novo (sem -Reparar) daqui a 1 minuto.'
                $rFilas = $teste
            } else {
                $falhas++
                Escrever "   [!] Spooler: $($sv.Status), respondeu: $($teste.Respondeu). Reinicie a maquina."
            }
        }
        'Sumatra' {
            # So agora: o spooler de volta costuma soltar o SumatraPDF sozinho.
            Start-Sleep -Seconds 5
            $presos = @(Get-Process -Name SumatraPDF -ErrorAction SilentlyContinue | Where-Object {
                $_.MainWindowHandle -eq 0 -and $_.StartTime -lt (Get-Date).AddMinutes(-10) })
            if ($presos.Count -eq 0) { Escrever '   [OK] Nenhuma impressao do SumatraPDF presa agora.'; break }
            foreach ($s in $presos) { try { Stop-Process -Id $s.Id -Force } catch { } }
            Start-Sleep -Seconds 2
            $vivos = @($presos | Where-Object { Get-Process -Id $_.Id -ErrorAction SilentlyContinue })
            if ($vivos.Count -eq 0) {
                Escrever "   [OK] Fechado(s): PID $(($presos | ForEach-Object { $_.Id }) -join ', ')."
                Escrever '       O agente manda o arquivo dessa impressao para Erro\: confira no papel'
                Escrever '       e, se nao saiu, mova de volta para a Entrada.'
            } else { $falhas++; Escrever "   [!] Continua vivo: PID $(($vivos | ForEach-Object { $_.Id }) -join ', ')." }
        }
        'Retomar' {
            $cod = "Add-Type -AssemblyName System.Printing`n" +
                   "`$q = New-Object System.Printing.PrintQueue((New-Object System.Printing.LocalPrintServer), $(Lit $Fila), [System.Printing.PrintSystemDesiredAccess]::AdministratePrinter)`n" +
                   "`$q.Resume(); `$q.Refresh(); 'PAUSADA|' + `$q.IsPaused"
            $res  = ComLimite $cod 45
            $lido = $res.Saida -split "`r?`n" | Where-Object { $_ -like 'PAUSADA|*' } | Select-Object -Last 1
            if ($res.Ok -and $lido -eq 'PAUSADA|False') { Escrever '   [OK] Fila retomada.' }
            else { $falhas++; Escrever "   [!] Nao consegui retomar: $($res.Erro)" }
        }
        'Porta' {
            if (-not $admin) {
                $falhas++
                Escrever '   [!] Precisa de administrador. Abra o PowerShell como administrador e'
                Escrever '       rode de novo com -Reparar.'
                break
            }
            $res = ComLimite "Set-Printer -Name $(Lit $Fila) -PortName $(Lit $r.Porta); 'ok'" 60
            $releitura = ComLimite $codFilas 45
            $agora = LerJson $releitura | Where-Object { $_.Nome -eq $Fila } | Select-Object -First 1
            if ($agora -and $agora.Porta -eq $r.Porta) {
                Escrever "   [OK] Lido de volta: '$Fila' na porta $($agora.Porta)."
                Escrever '       Reimprima a ultima etiqueta para conferir no papel.'
                $rFilas = $releitura
            } else {
                $falhas++
                $motivo = $res.Erro
                if (-not $res.Respondeu) { $motivo = 'o Set-Printer nao respondeu (WMI travado?)' }
                Escrever "   [!] Nao consegui mudar a porta: $motivo"
                Escrever "       A mao: Configuracoes > Impressoras > '$Fila' > Propriedades da"
                Escrever "       impressora > Portas > marque $($r.Porta)."
            }
        }
        'Agente' {
            $cod = "`$s = New-Object -ComObject Schedule.Service; `$s.Connect()`n" +
                   "[void]`$s.GetFolder('\').GetTask($(Lit $r.Caminho)).Run(`$null); 'ok'"
            $res = ComLimite $cod 60
            if (-not $res.Ok) { $falhas++; Escrever "   [!] Nao disparou: $($res.Erro)"; break }
            Start-Sleep -Seconds 10
            $lida = LerJson (ComLimite $codAgente 60) | Select-Object -First 1
            if ($lida -and [int]$lida.Estado -eq 4) { Escrever '   [OK] Agente rodando.' }
            else { $falhas++; Escrever "   [!] O agente nao aparece rodando. Veja o log: $arqLog" }
        }
    }
}

# Leitura de volta: a Entrada tem de andar.
if ((Test-Path -LiteralPath $entrada) -and (Esperando).Count -gt 0) {
    Escrever ''
    Escrever 'Conferindo se o agente esta imprimindo a Entrada (ate 90 s)...'
    $antes  = (Esperando).Count
    $limite = (Get-Date).AddSeconds(90)
    do { Start-Sleep -Seconds 10 } while ((Esperando).Count -ge $antes -and (Get-Date) -lt $limite)
    $depois = (Esperando).Count
    if ($depois -lt $antes) { Escrever "[OK] A Entrada andou: $antes -> $depois arquivo(s)." }
    else { $falhas++; Escrever "[!] A Entrada nao andou ($antes arquivo(s)). Veja o log: $arqLog" }
}

Escrever ''
if ($falhas -eq 0) {
    Escrever 'VEREDITO: reparo aplicado e conferido. Imprima uma etiqueta para confirmar'
    Escrever '          no papel; o guardiao deve parar de avisar na proxima rodada dele.'
} else {
    Escrever "VEREDITO: $falhas item(ns) nao voltaram. Veja acima."
}
Salvar
if ($falhas -eq 0) { exit 0 } else { exit 1 }
