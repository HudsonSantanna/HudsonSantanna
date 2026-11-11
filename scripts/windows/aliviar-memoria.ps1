#Requires -Version 5.1
<#
    aliviar-memoria.ps1 - Mostra o que esta ocupando memoria e disco e desliga
    o que roda em segundo plano sem fazer falta numa maquina de trabalho.

    Por padrao SO MOSTRA. Para agir, use -Executar. Para voltar ao que era,
    use -Desfazer.

    Nunca mexe em: Chrome, Edge, node, python, PowerShell (os vigias usam),
    spooler/impressoras, Windows Update, antivirus, Agendador de Tarefas.
    Age apenas na lista fechada $Servicos e $Aplicativos abaixo.

    Nao usa WMI (que ja travou nesta maquina): le processos pelo Get-Process,
    servicos pelo Gerenciador de Servicos e memoria direto da API do Windows.

    Uso (PowerShell como administrador):
      powershell -ExecutionPolicy Bypass -File .\aliviar-memoria.ps1             # so mostra
      powershell -ExecutionPolicy Bypass -File .\aliviar-memoria.ps1 -Executar   # desliga
      powershell -ExecutionPolicy Bypass -File .\aliviar-memoria.ps1 -Desfazer   # volta ao original
#>
[CmdletBinding()]
param(
    [switch]$Executar,
    [switch]$Desfazer,
    [int]   $SegundosDisco = 5,
    [string]$Log = "$env:USERPROFILE\Desktop\aliviar-memoria-$(Get-Date -Format 'yyyyMMdd-HHmm').txt"
)

$ErrorActionPreference = 'SilentlyContinue'
$script:Linhas = New-Object System.Collections.ArrayList
$Registro = Join-Path $env:ProgramData 'Manutencao\servicos-originais.json'

# Servicos que podem ser desligados sem prejuizo numa maquina de loja/escritorio.
$Servicos = [ordered]@{
    'SysMain'          = 'Pre-carrega programas na RAM. Com pouca memoria e disco a 100%, so atrapalha'
    'WSearch'          = 'Indexador da pesquisa: le o disco o tempo todo. A busca continua, so mais lenta'
    'DiagTrack'        = 'Telemetria da Microsoft'
    'dmwappushservice' = 'Telemetria (roteamento de mensagens WAP)'
    'WerSvc'           = 'Relatorio de erros para a Microsoft'
    'MapsBroker'       = 'Mapas offline'
    'RetailDemo'       = 'Modo demonstracao de loja de eletronicos'
    'Fax'              = 'Fax'
    'XblAuthManager'   = 'Xbox Live'
    'XblGameSave'      = 'Xbox: salvamento de jogos'
    'XboxNetApiSvc'    = 'Xbox: rede'
    'XboxGipSvc'       = 'Xbox: acessorios'
    'WSAIFabricSvc'    = 'Componentes de IA do Windows (Recall/Copilot)'
}
# Aplicativos de segundo plano que podem ser fechados sem perder trabalho.
$Aplicativos = [ordered]@{
    'Widgets'               = 'Widgets do Windows 11'
    'WidgetService'         = 'Widgets do Windows 11'
    'PhoneExperienceHost'   = 'Vincular ao Celular'
    'YourPhone'             = 'Vincular ao Celular'
    'YourPhoneServer'       = 'Vincular ao Celular'
    'GameBar'               = 'Xbox Game Bar'
    'GameBarFTServer'       = 'Xbox Game Bar'
    'GameBarPresenceWriter' = 'Xbox Game Bar'
    'Cortana'               = 'Cortana'
    'SkypeApp'              = 'Skype'
    'SkypeBackgroundHost'   = 'Skype'
}
# Processos que podem ser dos vigias ou do trabalho: so aparecem no relatorio.
$Protegidos = 'chrome','msedge','node','python','pythonw','powershell','pwsh',
              'spoolsv','claude','explorer'

function Escrever([string]$Texto = '', [string]$Cor = '') {
    if ($Cor) { Write-Host $Texto -ForegroundColor $Cor } else { Write-Host $Texto }
    [void]$script:Linhas.Add($Texto)
}
function Titulo([string]$Texto) {
    Escrever ''
    Escrever ('=' * 72)
    Escrever "  $Texto"
    Escrever ('=' * 72)
}
function ComoMB($Bytes) { '{0,9:N0} MB' -f ($Bytes / 1MB) }
function ComoGB($Bytes) { '{0:N1} GB' -f ($Bytes / 1GB) }
function EhAdmin {
    $id = [Security.Principal.WindowsIdentity]::GetCurrent()
    (New-Object Security.Principal.WindowsPrincipal $id).IsInRole(
        [Security.Principal.WindowsBuiltInRole]::Administrator)
}

# Memoria fisica sem WMI (a classe do VB.NET le direto do Windows).
Add-Type -AssemblyName Microsoft.VisualBasic
function Memoria {
    $ci = New-Object Microsoft.VisualBasic.Devices.ComputerInfo
    [pscustomobject]@{ Total = [double]$ci.TotalPhysicalMemory; Livre = [double]$ci.AvailablePhysicalMemory }
}

# Leitura+escrita acumulada de cada processo, para medir quem esta usando o disco.
$temES = $false
try {
    if (-not ('ManutencaoMemV1.ES' -as [type])) {
        Add-Type -ErrorAction Stop -TypeDefinition @'
using System;
using System.Runtime.InteropServices;
namespace ManutencaoMemV1 {
    public static class ES {
        [StructLayout(LayoutKind.Sequential)]
        private struct Contadores {
            public ulong LeiturasQtd, EscritasQtd, OutrasQtd, LeiturasBytes, EscritasBytes, OutrasBytes;
        }
        [DllImport("kernel32.dll", SetLastError = true)]
        private static extern IntPtr OpenProcess(uint acesso, bool herdar, int pid);
        [DllImport("kernel32.dll", SetLastError = true)]
        private static extern bool GetProcessIoCounters(IntPtr processo, out Contadores c);
        [DllImport("kernel32.dll")]
        private static extern bool CloseHandle(IntPtr h);
        public static long Bytes(int pid) {
            IntPtr h = OpenProcess(0x1000, false, pid);   // PROCESS_QUERY_LIMITED_INFORMATION
            if (h == IntPtr.Zero) return -1;
            try {
                Contadores c;
                if (!GetProcessIoCounters(h, out c)) return -1;
                return (long)(c.LeiturasBytes + c.EscritasBytes);
            } finally { CloseHandle(h); }
        }
    }
}
'@
    }
    $temES = $true
} catch { $temES = $false }

# ---------------------------------------------------------------- desfazer
if ($Desfazer) {
    Escrever "Desfazer - $(Get-Date -Format 'dd/MM/yyyy HH:mm')"
    if (-not (EhAdmin)) { Escrever 'Precisa de administrador. Abra o PowerShell como administrador.' 'Red'; return }
    if (-not (Test-Path -LiteralPath $Registro)) { Escrever "Nada a desfazer: $Registro nao existe."; return }
    $orig = Get-Content -LiteralPath $Registro -Raw | ConvertFrom-Json
    foreach ($p in $orig.PSObject.Properties) {
        & sc.exe config $p.Name start= $p.Value | Out-Null
        if ($LASTEXITCODE -eq 0) { Escrever ("[ok]    {0,-18} voltou para '{1}'" -f $p.Name, $p.Value) 'Green' }
        else { Escrever ("[falha] {0,-18} nao voltou (sc.exe codigo {1})" -f $p.Name, $LASTEXITCODE) 'Red' }
    }
    Remove-Item -LiteralPath $Registro -Force
    Escrever ''
    Escrever 'Pronto. Os servicos voltam a iniciar sozinhos no proximo boot (ou inicie pelo services.msc).'
    $script:Linhas | Out-File -FilePath $Log -Encoding UTF8
    return
}

Escrever "Aliviar memoria - $(Get-Date -Format 'dd/MM/yyyy HH:mm')   Computador: $env:COMPUTERNAME"
if (-not $Executar) { Escrever '>>> SO MOSTRANDO: nada sera desligado. Repita com -Executar para valer. <<<' 'Yellow' }
if (-not (EhAdmin)) {
    Escrever '*** Sem administrador: servicos nao serao alterados e alguns processos nao aparecem.' 'Yellow'
}

# ------------------------------------------------------------------ memoria
$memAntes = Memoria
$usoPct = (1 - $memAntes.Livre / $memAntes.Total) * 100
Titulo 'MEMORIA'
Escrever ("RAM total: {0}   Livre: {1}   Em uso: {2:N0}%" -f (ComoGB $memAntes.Total), (ComoGB $memAntes.Livre), $usoPct)
if ($memAntes.Total -le 8.5GB) {
    Escrever ''
    Escrever ("ATENCAO: so {0} de RAM. Com Chrome + vigias isso fica no limite; desligar" -f (ComoGB $memAntes.Total)) 'Yellow'
    Escrever 'servicos ajuda, mas a solucao de verdade e colocar mais um pente de memoria.' 'Yellow'
}

# --------------------------------------------------- maiores em memoria
Titulo 'O QUE MAIS OCUPA MEMORIA (agrupado por programa)'
Escrever ('{0,-38} {1,5} {2,13} {3,13}' -f 'Programa', 'Qtd', 'Na RAM', 'Reservado')
$processos = Get-Process
$grupos = $processos | Group-Object ProcessName | ForEach-Object {
    [pscustomobject]@{
        Nome      = $_.Name
        Qtd       = $_.Count
        NaRam     = ($_.Group | Measure-Object WorkingSet64 -Sum).Sum
        Reservado = ($_.Group | Measure-Object PrivateMemorySize64 -Sum).Sum
    }
} | Sort-Object NaRam -Descending | Select-Object -First 20
foreach ($g in $grupos) {
    $marca = ''
    if ($Protegidos -contains $g.Nome.ToLower()) { $marca = '  (trabalho/vigias - nao fechar)' }
    elseif ($Aplicativos.Contains($g.Nome))      { $marca = '  <- dispensavel' }
    $nomeCurto = if ($g.Nome.Length -gt 38) { $g.Nome.Substring(0, 37) + '~' } else { $g.Nome }
    Escrever ('{0,-38} {1,5} {2} {3}{4}' -f $nomeCurto, $g.Qtd, (ComoMB $g.NaRam), (ComoMB $g.Reservado), $marca)
}
$chrome = $grupos | Where-Object { $_.Nome -eq 'chrome' }
if ($chrome -and $chrome.NaRam -gt 1.5GB) {
    Escrever ''
    Escrever ("Chrome esta com {0} em {1} processos. Feche abas que nao esta usando" -f (ComoGB $chrome.NaRam), $chrome.Qtd)
    Escrever '(o script nao fecha o Chrome: o vigia do UpSeller usa ele).'
}

# ------------------------------------------------------ maiores em disco
Titulo "QUEM ESTA USANDO O DISCO (medido por $SegundosDisco s)"
if ($temES) {
    $antes = @{}
    foreach ($p in $processos) { $b = [ManutencaoMemV1.ES]::Bytes($p.Id); if ($b -ge 0) { $antes[$p.Id] = $b } }
    Start-Sleep -Seconds $SegundosDisco
    $porNome = @{}
    foreach ($p in Get-Process) {
        if (-not $antes.ContainsKey($p.Id)) { continue }
        $b = [ManutencaoMemV1.ES]::Bytes($p.Id)
        if ($b -ge $antes[$p.Id]) { $porNome[$p.ProcessName] += ($b - $antes[$p.Id]) }
    }
    $topo = @($porNome.GetEnumerator() | Sort-Object Value -Descending | Select-Object -First 10)
    foreach ($t in $topo) {
        Escrever ('{0,-28} {1,8:N1} MB/s' -f $t.Key, ($t.Value / 1MB / $SegundosDisco))
    }
    if ($topo -and @('System', 'Memory Compression', 'MemCompression') -contains $topo[0].Key) {
        Escrever ''
        Escrever 'O primeiro da lista e o proprio Windows trocando memoria com o disco:' 'Yellow'
        Escrever 'e falta de RAM. Liberar memoria (abaixo) e o que faz o disco sair dos 100%.' 'Yellow'
    }
    Escrever '(conta leitura+escrita de arquivos, inclusive o que vem do cache)'
} else {
    Escrever 'Nao foi possivel medir por processo nesta maquina. Use o Gerenciador de Tarefas,'
    Escrever 'aba Processos, clicando no cabecalho "Disco" para ordenar.'
}

# ---------------------------------------------------- o que sera desligado
Titulo 'SERVICOS DISPENSAVEIS'
$admin = EhAdmin
$originais = [ordered]@{}
if (Test-Path -LiteralPath $Registro) {
    $lido = Get-Content -LiteralPath $Registro -Raw | ConvertFrom-Json
    foreach ($p in $lido.PSObject.Properties) { $originais[$p.Name] = $p.Value }
}
$algumServico = $false
foreach ($nome in $Servicos.Keys) {
    $s = Get-Service -Name $nome
    if (-not $s) { continue }
    $chave = Get-ItemProperty -LiteralPath "HKLM:\SYSTEM\CurrentControlSet\Services\$nome"
    $inicio = switch ([int]$chave.Start) { 2 { if ($chave.DelayedAutostart -eq 1) { 'delayed-auto' } else { 'auto' } } 3 { 'demand' } 4 { 'disabled' } default { 'demand' } }
    if ($s.Status -ne 'Running' -and $inicio -eq 'disabled') { continue }
    $algumServico = $true
    $estado = if ($s.Status -eq 'Running') { 'rodando' } else { 'parado' }
    if (-not $Executar) {
        Escrever ('[desligaria] {0,-18} {1,-8} {2}' -f $nome, $estado, $Servicos[$nome])
        continue
    }
    if (-not $admin) { Escrever ('[pulado]  {0,-18} precisa de administrador' -f $nome); continue }

    if (-not $originais.Contains($nome)) { $originais[$nome] = $inicio }
    & sc.exe config $nome start= disabled | Out-Null
    $okConfig = ($LASTEXITCODE -eq 0)
    $okParou = $true
    if ($s.Status -eq 'Running') {
        try {
            $s.Stop()
            $s.WaitForStatus('Stopped', [TimeSpan]::FromSeconds(20))
        } catch { $okParou = $false }
    }
    if ($okConfig -and $okParou) { Escrever ('[desligado] {0,-18} {1}' -f $nome, $Servicos[$nome]) 'Green' }
    elseif ($okConfig)           { Escrever ('[parcial]  {0,-18} nao inicia mais, mas nao parou agora (para no proximo boot)' -f $nome) 'Yellow' }
    else                         { Escrever ('[falha]    {0,-18} o Windows nao deixou alterar (sc.exe codigo {1})' -f $nome, $LASTEXITCODE) 'Red' }
}
if (-not $algumServico) { Escrever 'Nenhum servico dispensavel ligado. Nada a fazer aqui.' }
if ($Executar -and $originais.Count -gt 0) {
    New-Item -ItemType Directory -Force -Path (Split-Path $Registro) | Out-Null
    $originais | ConvertTo-Json | Out-File -FilePath $Registro -Encoding UTF8
    Escrever ''
    Escrever "Configuracao original guardada em $Registro"
    Escrever 'Para voltar tudo como era:  .\aliviar-memoria.ps1 -Desfazer'
}

Titulo 'APLICATIVOS DISPENSAVEIS EM SEGUNDO PLANO'
$algumApp = $false
foreach ($nome in $Aplicativos.Keys) {
    $ps = @(Get-Process -Name $nome)
    if ($ps.Count -eq 0) { continue }
    $algumApp = $true
    $mem = ($ps | Measure-Object WorkingSet64 -Sum).Sum
    if (-not $Executar) {
        Escrever ('[fecharia] {0,-24} {1}  {2}' -f $nome, (ComoMB $mem), $Aplicativos[$nome])
        continue
    }
    $ps | Stop-Process -Force
    Escrever ('[fechado]  {0,-24} {1}  {2}' -f $nome, (ComoMB $mem), $Aplicativos[$nome]) 'Green'
}
if (-not $algumApp) { Escrever 'Nenhum aplicativo dispensavel aberto.' }

# --------------------------------------------------------------- resultado
Titulo 'RESULTADO'
if ($Executar) {
    Start-Sleep -Seconds 5
    $memDepois = Memoria
    Escrever ("RAM livre antes : {0}" -f (ComoGB $memAntes.Livre))
    Escrever ("RAM livre agora : {0}   (ganho de {1})" -f (ComoGB $memDepois.Livre), (ComoGB ($memDepois.Livre - $memAntes.Livre)))
    if (($memDepois.Livre - $memAntes.Livre) -lt 0.5GB) {
        Escrever ''
        Escrever 'Ganho pequeno: quem ocupa a memoria sao os programas abertos da lista acima' 'Yellow'
        Escrever '(abas do Chrome, apps como ChatGPT/WhatsApp). Feche o que nao estiver usando.' 'Yellow'
        Escrever 'Se nem assim sobrar 1 GB livre, a maquina precisa de mais memoria RAM:' 'Yellow'
        Escrever 'veja os "Slots usados" em Gerenciador de Tarefas > Desempenho > Memoria.' 'Yellow'
    }
} else {
    Escrever 'Para desligar o que esta marcado acima:'
    Escrever '  powershell -ExecutionPolicy Bypass -File .\aliviar-memoria.ps1 -Executar'
}
Escrever ''
Escrever 'Tambem vale conferir na mao (o script nao mexe nisso):'
Escrever '  - Gerenciador de Tarefas > Aplicativos de inicializacao: desative o que nao usa.'
Escrever '  - Edge > Configuracoes > Sistema: desligue "Aumento de inicializacao" e'
Escrever '    "Continuar executando extensoes em segundo plano".'
Escrever '  - Abas do Chrome abertas a toa (cada aba ocupa de 100 a 500 MB).'

$script:Linhas | Out-File -FilePath $Log -Encoding UTF8
Write-Host ''
Write-Host "Relatorio salvo em: $Log" -ForegroundColor Green
