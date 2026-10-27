#Requires -Version 5.1
<#
    4-navegadores.ps1 - Descobre por que varios navegadores (ou varias janelas)
    abrem sozinhos de uma vez e desliga a causa.

    Procura nos lugares de onde um navegador pode ser disparado sem voce pedir:
      - recurso do Windows que reabre os apps ao entrar na conta
      - programas que iniciam com o Windows (registro e pasta Inicializar)
      - tarefas agendadas
      - politicas forcadas nos navegadores (sinal classico de adware)
      - atalhos adulterados com um site embutido
      - gatilhos WMI (persistencia avancada - so relata)

    Por padrao SO DIAGNOSTICA. Para corrigir, use -Executar.
    Antes de mudar qualquer coisa salva um backup na Area de Trabalho.
    Itens de inicializacao sao DESATIVADOS (igual ao Gerenciador de Tarefas)
    e tarefas agendadas sao desabilitadas - nada e apagado.

    Uso:
      powershell -ExecutionPolicy Bypass -File .\4-navegadores.ps1              # diagnostica
      powershell -ExecutionPolicy Bypass -File .\4-navegadores.ps1 -Executar    # corrige
      ... -Executar -RemoverPoliticas    # tambem remove politicas forcadas
      ... -VerificarVirus                # verificacao rapida do Windows Defender
#>
[CmdletBinding()]
param(
    [switch]$Executar,
    [switch]$RemoverPoliticas,
    [switch]$VerificarVirus,
    [string]$Log = "$env:USERPROFILE\Desktop\navegadores-$(Get-Date -Format 'yyyyMMdd-HHmm').txt"
)

$ErrorActionPreference = 'SilentlyContinue'
$script:Linhas     = New-Object System.Collections.ArrayList
$script:Achados    = 0
$script:Corrigidos = 0
$script:Backup     = "$env:USERPROFILE\Desktop\backup-navegadores-$(Get-Date -Format 'yyyyMMdd-HHmm')"
$script:NumBackup  = 0

# Executaveis de navegador e sinais de que o comando abre uma janela/site
$reNavegador = '(?i)(\\(msedge|chrome|firefox|opera|brave|vivaldi|iexplore|browser)\.exe|\\opera[^\\]*\\launcher\.exe)'
$reSite      = '(?i)(https?://|www\.|microsoft-edge:)'
# Estes parametros iniciam o navegador sem janela (pre-carga, atualizacao)
$reSemJanela = '(?i)(--no-startup-window|--silent-launch|--scheduledautoupdate|--backgroundtask)'

$aprovadoHKCU = 'HKCU:\Software\Microsoft\Windows\CurrentVersion\Explorer\StartupApproved'
$aprovadoHKLM = 'HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Explorer\StartupApproved'
$shell = New-Object -ComObject WScript.Shell

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
function Achado([string]$Texto) {
    $script:Achados++
    Escrever "  [!] $Texto"
}
function AbreJanela([string]$Comando) {
    if ($Comando -match $reSite) { return $true }
    ($Comando -match $reNavegador) -and ($Comando -notmatch $reSemJanela)
}
function PastaBackup {
    if (-not (Test-Path -LiteralPath $script:Backup)) {
        New-Item -ItemType Directory -Path $script:Backup -Force | Out-Null
    }
    $script:Backup
}
function ArquivoBackup([string]$Nome) {
    $script:NumBackup++
    $limpo = $Nome -replace '[\\/:*?"<>|]', '_'
    Join-Path (PastaBackup) ('{0:D3}-{1}' -f $script:NumBackup, $limpo)
}
function ExportarChave([string]$Chave) {
    $destino = ArquivoBackup (($Chave -replace '^[^:]+:\\', '') + '.reg')
    reg.exe export ($Chave -replace ':', '') $destino /y | Out-Null
}
# Executa uma correcao, contando sucesso ou registrando a falha.
function Corrigir([string]$Descricao, [scriptblock]$Acao) {
    $ErrorActionPreference = 'Stop'
    try {
        & $Acao
        $script:Corrigidos++
        Escrever "      -> corrigido: $Descricao"
    } catch {
        Escrever "      -> FALHOU: $Descricao ($($_.Exception.Message))"
    }
}
function DesativarNaInicializacao([string]$ChaveAprovado, [string]$NomeValor) {
    if (-not (Test-Path -LiteralPath $ChaveAprovado)) {
        New-Item -Path $ChaveAprovado -Force | Out-Null
    }
    # 03 = desativado; os 8 bytes seguintes sao a data da desativacao
    $valor = [byte[]]((3, 0, 0, 0) + [BitConverter]::GetBytes((Get-Date).ToFileTime()))
    New-ItemProperty -LiteralPath $ChaveAprovado -Name $NomeValor -PropertyType Binary -Value $valor -Force | Out-Null
}
function EstaDesativado([string]$ChaveAprovado, [string]$NomeValor) {
    $b = (Get-ItemProperty -LiteralPath $ChaveAprovado -Name $NomeValor).$NomeValor
    ($b -is [byte[]]) -and ($b.Length -gt 0) -and (($b[0] -band 1) -eq 1)
}
function ComandoDoArquivo($Arquivo) {
    switch ($Arquivo.Extension.ToLower()) {
        '.lnk' {
            $l = $shell.CreateShortcut($Arquivo.FullName)
            return "$($l.TargetPath) $($l.Arguments)"
        }
        '.url' {
            return [string](Get-Content -LiteralPath $Arquivo.FullName |
                Where-Object { $_ -like 'URL=*' } | Select-Object -First 1)
        }
        default {
            if ($Arquivo.Length -lt 64KB) { return [string](Get-Content -LiteralPath $Arquivo.FullName -Raw) }
        }
    }
    ''
}

$admin = EhAdmin
Escrever "Navegadores abrindo sozinhos - $(Get-Date -Format 'dd/MM/yyyy HH:mm')"
Escrever "Computador: $env:COMPUTERNAME   Usuario: $env:USERNAME"
if (-not $Executar) {
    Escrever ''
    Escrever '>>> MODO DIAGNOSTICO: nada sera alterado. Repita com -Executar para corrigir. <<<'
}
if (-not $admin) {
    Escrever ''
    Escrever '*** Sem privilegio de administrador: itens do sistema (HKLM, tarefas'
    Escrever '*** agendadas, WMI) podem nao aparecer ou nao ser corrigidos.'
}

# -------------------------------------------------- abertos neste momento
Titulo 'NAVEGADORES ABERTOS AGORA'
$algumAberto = $false
foreach ($n in 'msedge', 'chrome', 'firefox', 'opera', 'brave', 'vivaldi') {
    $procs = @(Get-Process -Name $n)
    if ($procs.Count -eq 0) { continue }
    $algumAberto = $true
    $janelas = @($procs | Where-Object { $_.MainWindowHandle -ne 0 })
    Escrever ('  {0,-10} {1,4} processos   {2,3} janela(s) visivel(is)' -f $n, $procs.Count, $janelas.Count)
}
if ($algumAberto) {
    Escrever ''
    Escrever '  Obs.: dezenas de processos por navegador e normal (cada aba e um processo).'
    Escrever '  O que importa e o numero de janelas e de navegadores diferentes.'
} else {
    Escrever '  Nenhum navegador aberto.'
}

# --------------------------------------- Windows reabrindo apps no login
Titulo 'WINDOWS REABRINDO OS APLICATIVOS AO ENTRAR'
$winlogon = 'HKCU:\Software\Microsoft\Windows NT\CurrentVersion\Winlogon'
if ((Get-ItemProperty -LiteralPath $winlogon -Name RestartApps).RestartApps -eq 1) {
    Achado 'Ligado: "Salvar automaticamente meus aplicativos reinicializaveis e reinicia-los ao entrar".'
    Escrever '      Cada navegador aberto no desligamento volta sozinho no proximo login.'
    if ($Executar) {
        Corrigir 'opcao desligada (Configuracoes > Contas > Opcoes de entrada)' {
            Set-ItemProperty -LiteralPath $winlogon -Name RestartApps -Value 0 -Type DWord
        }
    }
} else {
    Escrever '  [ok] Desligado.'
}

# ---------------------------------------------- inicializacao (registro)
Titulo 'INICIALIZACAO DO WINDOWS (registro)'
$chavesRun = @(
    @{ Chave = 'HKCU:\Software\Microsoft\Windows\CurrentVersion\Run';             Aprovado = "$aprovadoHKCU\Run" },
    @{ Chave = 'HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Run';             Aprovado = "$aprovadoHKLM\Run" },
    @{ Chave = 'HKLM:\SOFTWARE\WOW6432Node\Microsoft\Windows\CurrentVersion\Run'; Aprovado = "$aprovadoHKLM\Run32" },
    @{ Chave = 'HKCU:\Software\Microsoft\Windows\CurrentVersion\RunOnce';         Aprovado = $null },
    @{ Chave = 'HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\RunOnce';         Aprovado = $null }
)
$achouRun = $false
foreach ($c in $chavesRun) {
    $k = Get-Item -LiteralPath $c.Chave
    if (-not $k) { continue }
    foreach ($nome in $k.GetValueNames()) {
        if (-not $nome) { continue }
        $cmd = [string]$k.GetValue($nome)
        if (-not (AbreJanela $cmd)) { continue }
        if ($c.Aprovado -and (EstaDesativado $c.Aprovado $nome)) {
            Escrever "  [ok] Ja desativado: $nome"
            continue
        }
        $achouRun = $true
        Achado "$nome"
        Escrever "      $cmd"
        Escrever "      ($($c.Chave))"
        if (-not $Executar) { continue }
        if ($c.Aprovado) {
            Corrigir 'desativado na inicializacao (reativa pelo Gerenciador de Tarefas)' {
                DesativarNaInicializacao $c.Aprovado $nome
            }
        } else {
            Corrigir 'removido do RunOnce (backup .reg salvo)' {
                ExportarChave $c.Chave
                Remove-ItemProperty -LiteralPath $c.Chave -Name $nome
            }
        }
    }
}
if (-not $achouRun) { Escrever '  [ok] Nenhuma entrada abrindo navegador ou site.' }
Escrever ''
Escrever '  Obs.: entradas do Edge/Chrome com --no-startup-window so pre-carregam o'
Escrever '  navegador sem abrir janela; por isso nao entram na lista.'

# --------------------------------------------- inicializacao (pastas)
Titulo 'INICIALIZACAO DO WINDOWS (pasta Inicializar)'
$achouPasta = $false
foreach ($pasta in @([Environment]::GetFolderPath('Startup'), [Environment]::GetFolderPath('CommonStartup'))) {
    if (-not $pasta) { continue }
    foreach ($arq in (Get-ChildItem -LiteralPath $pasta -File -Force | Where-Object { $_.Name -ne 'desktop.ini' })) {
        $cmd = ComandoDoArquivo $arq
        if (-not (AbreJanela $cmd)) { continue }
        $achouPasta = $true
        Achado $arq.FullName
        Escrever "      $($cmd.Trim())"
        if ($Executar) {
            Corrigir 'retirado da pasta Inicializar (guardado no backup)' {
                Move-Item -LiteralPath $arq.FullName -Destination (ArquivoBackup $arq.Name)
            }
        }
    }
}
if (-not $achouPasta) { Escrever '  [ok] Nada abrindo navegador ou site.' }

# ------------------------------------------------------ tarefas agendadas
Titulo 'TAREFAS AGENDADAS'
$achouTarefa = $false
foreach ($t in (Get-ScheduledTask | Where-Object { $_.State -ne 'Disabled' })) {
    $cmds = @($t.Actions | Where-Object { $_.Execute } | ForEach-Object { "$($_.Execute) $($_.Arguments)" })
    $suspeito = @($cmds | Where-Object { AbreJanela $_ })
    if ($suspeito.Count -eq 0) { continue }
    $achouTarefa = $true
    Achado "$($t.TaskPath)$($t.TaskName)"
    $suspeito | ForEach-Object { Escrever "      $_" }
    if ($Executar) {
        Corrigir 'tarefa desabilitada (XML no backup)' {
            Export-ScheduledTask -TaskName $t.TaskName -TaskPath $t.TaskPath |
                Out-File -FilePath (ArquivoBackup "tarefa-$($t.TaskName).xml") -Encoding UTF8
            Disable-ScheduledTask -TaskName $t.TaskName -TaskPath $t.TaskPath | Out-Null
        }
    }
}
if (-not $achouTarefa) { Escrever '  [ok] Nenhuma tarefa abrindo navegador ou site.' }
Escrever ''
Escrever '  Obs.: tarefas de atualizacao (GoogleUpdate, MicrosoftEdgeUpdate...) nao'
Escrever '  abrem janela e ficam de fora.'

# --------------------------------------------- politicas nos navegadores
Titulo 'POLITICAS FORCADAS NOS NAVEGADORES'
$politicas = @(
    'HKLM:\SOFTWARE\Policies\Google\Chrome',        'HKCU:\SOFTWARE\Policies\Google\Chrome',
    'HKLM:\SOFTWARE\Policies\Microsoft\Edge',       'HKCU:\SOFTWARE\Policies\Microsoft\Edge',
    'HKLM:\SOFTWARE\Policies\BraveSoftware\Brave',  'HKCU:\SOFTWARE\Policies\BraveSoftware\Brave',
    'HKLM:\SOFTWARE\Policies\Mozilla\Firefox',      'HKCU:\SOFTWARE\Policies\Mozilla\Firefox'
)
$achouPolitica = $false
foreach ($p in $politicas) {
    if (-not (Test-Path -LiteralPath $p)) { continue }
    $achouPolitica = $true
    Achado $p
    $chaves = @(Get-Item -LiteralPath $p) + @(Get-ChildItem -LiteralPath $p -Recurse)
    $mostradas = 0
    foreach ($k in $chaves) {
        foreach ($nome in $k.GetValueNames()) {
            if ($mostradas -ge 15) { break }
            $mostradas++
            $rel = $k.Name.Substring($k.Name.IndexOf('\Policies\') + 10)
            Escrever ("      {0}\{1} = {2}" -f $rel, $nome, $k.GetValue($nome))
        }
    }
    if ($Executar -and $RemoverPoliticas) {
        Corrigir "politicas removidas (backup .reg salvo)" {
            ExportarChave $p
            Remove-Item -LiteralPath $p -Recurse -Force
        }
    }
}
if ($achouPolitica) {
    Escrever ''
    Escrever '  RestoreOnStartup / RestoreOnStartupURLs fazem o navegador abrir sites'
    Escrever '  sozinho; ExtensionInstallForcelist instala extensoes que voce nao remove.'
    Escrever '  Em PC de casa isso costuma ser adware. Em PC de empresa pode ser da TI.'
    if (-not $RemoverPoliticas) {
        Escrever '  Para remover: .\4-navegadores.ps1 -Executar -RemoverPoliticas'
    }
} else {
    Escrever '  [ok] Nenhuma politica forcada.'
}

# ------------------------------------------------- atalhos adulterados
Titulo 'ATALHOS DE NAVEGADOR COM SITE EMBUTIDO'
$locais = @(
    [Environment]::GetFolderPath('Desktop'),
    [Environment]::GetFolderPath('CommonDesktopDirectory'),
    [Environment]::GetFolderPath('StartMenu'),
    [Environment]::GetFolderPath('CommonStartMenu'),
    "$env:APPDATA\Microsoft\Internet Explorer\Quick Launch\User Pinned\TaskBar"
) | Where-Object { $_ -and (Test-Path -LiteralPath $_) }
$achouAtalho = $false
foreach ($arq in (Get-ChildItem -LiteralPath $locais -Filter *.lnk -Recurse -Force)) {
    $l = $shell.CreateShortcut($arq.FullName)
    if (-not (($l.TargetPath -match $reNavegador) -and ($l.Arguments -match $reSite))) { continue }
    $achouAtalho = $true
    Achado $arq.FullName
    Escrever "      $($l.TargetPath) $($l.Arguments)"
    if ($Executar) {
        Corrigir 'site retirado do atalho (original no backup)' {
            Copy-Item -LiteralPath $arq.FullName -Destination (ArquivoBackup $arq.Name)
            $l.Arguments = ($l.Arguments -replace '(?i)"?(https?://|www\.|microsoft-edge:)[^\s"]*"?', '').Trim()
            $l.Save()
        }
    }
}
if (-not $achouAtalho) { Escrever '  [ok] Atalhos limpos.' }

# ------------------------------------------------------------ WMI
Titulo 'GATILHOS WMI (somente relata)'
$consumidores = @(Get-CimInstance -Namespace root\subscription -ClassName CommandLineEventConsumer)
if ($consumidores.Count -gt 0) {
    foreach ($w in $consumidores) {
        Achado "Gatilho WMI '$($w.Name)': $($w.CommandLineTemplate)"
    }
    Escrever ''
    Escrever '  Gatilhos WMI sao usados por alguns fabricantes, mas tambem por malware'
    Escrever '  para se esconder. Rode -VerificarVirus e, se persistir, a verificacao'
    Escrever '  offline do Windows Defender (Seguranca do Windows > Opcoes de verificacao).'
} elseif ($admin) {
    Escrever '  [ok] Nenhum gatilho de linha de comando.'
} else {
    Escrever '  Nao verificado (requer administrador).'
}

# ----------------------------------------------------------- antivirus
if ($VerificarVirus) {
    Titulo 'VERIFICACAO RAPIDA DO WINDOWS DEFENDER'
    $mp = Get-MpComputerStatus
    if (-not $mp -or -not $mp.AntivirusEnabled) {
        Escrever '  Defender desligado ou substituido por outro antivirus. Use o seu antivirus.'
    } else {
        Escrever '  Atualizando definicoes...'
        Update-MpSignature
        Escrever '  Verificando (leva alguns minutos)...'
        Start-MpScan -ScanType QuickScan
        $ameacas = @(Get-MpThreat)
        if ($ameacas.Count -gt 0) {
            foreach ($a in $ameacas) { Achado "Ameaca: $($a.ThreatName)" }
            Escrever '  Abra Seguranca do Windows > Protecao contra virus para remover.'
        } else {
            Escrever '  [ok] Nenhuma ameaca encontrada.'
        }
    }
}

# --------------------------------------------------------------- resumo
Titulo 'RESUMO'
Escrever "Itens encontrados: $script:Achados"
if ($Executar) {
    Escrever "Itens corrigidos : $script:Corrigidos"
    if (Test-Path -LiteralPath $script:Backup) { Escrever "Backup em        : $script:Backup" }
    Escrever ''
    Escrever 'Reinicie o computador para confirmar que os navegadores pararam de abrir.'
} elseif ($script:Achados -gt 0) {
    Escrever ''
    Escrever 'Para corrigir:'
    Escrever '  .\4-navegadores.ps1 -Executar'
}
Escrever ''
Escrever 'Se nada foi encontrado e as janelas continuam se multiplicando:'
Escrever '  - Configuracoes do navegador > "Ao iniciar": troque "Continuar de onde'
Escrever '    parou" por "Abrir a pagina Nova guia" (reabre todas as janelas antigas).'
Escrever '  - Confira as extensoes instaladas e remova as que nao reconhece.'
Escrever '  - PC lento: clicar de novo no icone enquanto o navegador demora abre outra'
Escrever '    janela a cada clique. Clique uma vez e aguarde; rode 1-diagnostico.ps1'
Escrever '    e 2-limpeza.ps1 para a maquina voltar a responder rapido.'

$script:Linhas | Out-File -FilePath $Log -Encoding UTF8
Write-Host ''
Write-Host "Relatorio salvo em: $Log" -ForegroundColor Green
