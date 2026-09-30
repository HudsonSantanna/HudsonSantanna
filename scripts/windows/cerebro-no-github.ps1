#Requires -Version 5.1
<#
    cerebro-no-github.ps1 - Agente que mantem o Cerebro do KHAOSOMNI no GitHub,
    sozinho, de tempos em tempos.

    O problema real: o push do Cerebro era MANUAL ("o Claude faz ao fechar
    marco"). Quando ninguem fecha marco, o GitHub para no tempo - em 28/09 ele
    ainda estava em 07/09. Tudo que le o Cerebro pelo GitHub (o Claude na
    nuvem, o notebook fora da rede) passa a trabalhar com memoria velha e
    ninguem percebe.

    Cada rodada:
      0. Kit Claude: copia skills, agentes, comandos e o CLAUDE.md do
         ~\.claude do servidor para o .claude\ do Cerebro (script
         Publicar-Kit-Claude-no-GitHub.ps1, que mora no proprio Cerebro).
         Sem isso o Claude na nuvem fica com os comandos da ultima vez que
         alguem lembrou de publicar a mao. Falha aqui nao impede o resto.
      1. git add -A  (o .gitignore do Cerebro ja segura financeiro, espiao,
                      credenciais, _travas e as copias *.do-notebook-*)
      2. TRAVAS antes do commit - se qualquer uma disparar, desfaz o add e
         NAO envia nada:
           - caminho com cara de segredo (credencial, senha, token, .env, .pem...)
           - conteudo com cara de chave (sk-ant-, ghp_, AKIA, PRIVATE KEY...)
           - arquivos demais de uma vez (a enxurrada de 3.290 _travas de 07/09)
      3. commit, fetch, merge do que veio do GitHub (outra maquina pode ter
         enviado). Conflito: aborta o merge e para - conflito se resolve a mao.
      4. push.

    Nunca usa --force, nunca faz rebase, nunca apaga arquivo.

    Uso:
      # uma rodada, olhando (nao grava nada)
      powershell -ExecutionPolicy Bypass -File .\cerebro-no-github.ps1 -Simular

      # uma rodada de verdade
      powershell -ExecutionPolicy Bypass -File .\cerebro-no-github.ps1

      # instalar como tarefa agendada (a cada 30 min)
      powershell -ExecutionPolicy Bypass -File .\cerebro-no-github.ps1 -Instalar

    Saida: 0 = enviado ou nada a enviar; 1 = parou numa trava ou erro.
    Log: %LOCALAPPDATA%\Argos\cerebro-no-github.log (FORA do Cerebro, para o
    proprio log nao virar mudanca a enviar).
#>
[CmdletBinding()]
param(
    [string]$Cerebro        = "$env:USERPROFILE\Argos-Cerebro",
    [switch]$Simular,
    [switch]$Instalar,
    [int]   $Intervalo      = 30,
    [int]   $LimiteArquivos = 400,
    [switch]$Forcar,
    [switch]$SemKit,
    [string]$Kit            = '05-Recursos\Kit-Claude-Nuvem\Publicar-Kit-Claude-no-GitHub.ps1',
    [string]$Servidor       = 'KHAOSOMNI',
    [string]$Tarefa         = 'ARGOS - Cerebro no GitHub',
    [string]$Log            = "$env:LOCALAPPDATA\Argos\cerebro-no-github.log"
)

$ErrorActionPreference = 'Stop'

# Caminho que parece ARQUIVO de segredo. O .gitignore e a primeira barreira;
# esta e a segunda, para o dia em que alguem criar uma nota nova com
# credencial. "token" NAO entra aqui: em 28/09 ela barrou 4 notas de sessao
# que so FALAVAM de token no titulo. Token colado dentro da nota e trabalho
# da trava de conteudo, logo abaixo. "senha" so como palavra inteira: a nota
# "GPT desenha, Kimi codifica" caia na trava por causa do "de-SENHA".
$script:CaminhoSensivel = '(?i)(credencia|\bsenhas?\b|\bpasswords?\b|\.env$|\.pem$|\.pfx$|\.p12$|\.key$|id_rsa|id_ed25519|\.credentials\.json$|SERVIDOR-CONFIG)'
# Conteudo que parece chave de verdade (so linhas ADICIONADAS nesta rodada):
# Anthropic, OpenAI, GitHub, AWS, chave privada, Slack, Meta/Facebook, Google,
# e qualquer "access_token/refresh_token/api_key/client_secret = <valor longo>".
$script:ConteudoSensivel = '(sk-ant-[A-Za-z0-9_-]{10,}|sk-[A-Za-z0-9]{32,}|ghp_[A-Za-z0-9]{30,}|github_pat_[A-Za-z0-9_]{30,}|AKIA[0-9A-Z]{16}|-----BEGIN [A-Z ]*PRIVATE KEY-----|xox[baprs]-[A-Za-z0-9-]{10,}|EAA[A-Za-z0-9]{60,}|AIza[0-9A-Za-z_-]{35}|(?i:access_token|refresh_token|api_key|apikey|client_secret|partner_key)["''\s:=]+[A-Za-z0-9._-]{20,})'

function Registrar([string]$Texto) {
    $linha = "$(Get-Date -Format 'yyyy-MM-dd HH:mm:ss')  $Texto"
    Write-Host $linha
    try {
        $pasta = Split-Path $Log -Parent
        if (-not (Test-Path -LiteralPath $pasta)) { New-Item -ItemType Directory -Path $pasta -Force | Out-Null }
        Add-Content -LiteralPath $Log -Value $linha -Encoding UTF8
    } catch { }
}

# git escreve progresso no stderr. No PowerShell 5.1, com 'Stop', isso vira
# excecao no meio de um push que deu certo. Aqui o stderr e so texto, e quem
# decide se falhou e o codigo de saida.
# Nome proprio de proposito: o PowerShell nao diferencia maiusculas, e uma
# funcao chamada "Git" faria o '& git' de dentro chamar ela mesma, em laco.
function RodarGit {
    $anterior = $ErrorActionPreference
    $ErrorActionPreference = 'Continue'
    try {
        # quotePath=false: nome com acento sai legivel, e nao "03-Sess\303\265es".
        $saida = & git -C $Cerebro -c core.quotePath=false @args 2>&1 | ForEach-Object { "$_" }
        $script:GitCodigo = $LASTEXITCODE
    } finally {
        $ErrorActionPreference = $anterior
    }
    return $saida
}

function Parar([string]$Motivo) {
    Registrar "[ERRO] $Motivo"
    exit 1
}

# ------------------------------------------------------------ trava de dono
# Um escritor so. Se o notebook tambem enviasse sozinho, os dois brigariam
# em merge o dia inteiro.
if ($env:COMPUTERNAME -ne $Servidor -and -not $Forcar) {
    Write-Host ''
    Write-Host "  PARE: esta maquina e $env:COMPUTERNAME, nao o servidor $Servidor." -ForegroundColor Red
    Write-Host '  O agente do Cerebro tem dono unico. Se e mesmo aqui, repita com -Forcar.' -ForegroundColor Red
    Write-Host ''
    exit 1
}

# ------------------------------------------------------------------ instalar
if ($Instalar) {
    # Nao usar "$env:USERDOMAIN\$env:USERNAME": numa sessao SSH o Windows diz
    # WORKGROUP e o Register-ScheduledTask morre com 0x80070534. whoami acerta.
    $usuario = (& whoami).Trim()
    $argumentos = "-NoProfile -ExecutionPolicy Bypass -WindowStyle Hidden -File `"$PSCommandPath`" -Cerebro `"$Cerebro`""
    $acao    = New-ScheduledTaskAction -Execute 'powershell.exe' -Argument $argumentos
    $gatilho = New-ScheduledTaskTrigger -Once -At (Get-Date).AddMinutes(1) `
                   -RepetitionInterval (New-TimeSpan -Minutes $Intervalo)
    # Interactive: roda com o usuario logado, que e quem tem a credencial do
    # GitHub guardada no Gerenciador de Credenciais do Windows.
    $dono    = New-ScheduledTaskPrincipal -UserId $usuario -LogonType Interactive
    $ajustes = New-ScheduledTaskSettingsSet -StartWhenAvailable -MultipleInstances IgnoreNew `
                   -ExecutionTimeLimit (New-TimeSpan -Minutes 20)
    Register-ScheduledTask -TaskName $Tarefa -Action $acao -Trigger $gatilho `
        -Principal $dono -Settings $ajustes -Force | Out-Null

    $t = Get-ScheduledTask -TaskName $Tarefa
    Registrar "[OK] Tarefa '$Tarefa' instalada ($($t.State)), a cada $Intervalo min, como $usuario."
    Registrar "     Script: $PSCommandPath"
    exit 0
}

# --------------------------------------------------------------- pre-requisitos
if (-not (Get-Command git -ErrorAction SilentlyContinue)) { Parar 'git nao esta instalado ou nao esta no PATH.' }
if (-not (Test-Path -LiteralPath (Join-Path $Cerebro '.git'))) { Parar "$Cerebro nao e um repositorio git." }

# Um de cada vez: a tarefa e um clique manual ao mesmo tempo corromperiam o index.
$mutex = New-Object System.Threading.Mutex($false, 'Global\ArgosCerebroNoGitHub')
if (-not $mutex.WaitOne(0)) { Registrar '[!] Outra rodada ainda em andamento - pulando esta.'; exit 0 }

try {
    $gitDir = Join-Path $Cerebro '.git'
    foreach ($meio in 'MERGE_HEAD', 'rebase-merge', 'rebase-apply', 'CHERRY_PICK_HEAD') {
        if (Test-Path -LiteralPath (Join-Path $gitDir $meio)) {
            Parar "O repositorio esta no meio de um merge/rebase ($meio). Resolva a mao antes."
        }
    }

    $ramo = (RodarGit rev-parse --abbrev-ref HEAD | Select-Object -First 1)
    if ($script:GitCodigo -ne 0 -or $ramo -eq 'HEAD') { Parar 'Nao ha ramo atual (HEAD solto?).' }
    $remoto = (RodarGit remote get-url origin | Select-Object -First 1)
    if ($script:GitCodigo -ne 0) { Parar 'O repositorio nao tem o remoto "origin".' }

    # ------------------------------------------------------ 0. Kit Claude
    # Roda em outro processo: o script do kit usa 'throw' e nao pode derrubar
    # esta rodada. O relatorio dele vai para a pasta do log, e nao para a Area
    # de Trabalho, senao nasceria um arquivo novo la a cada 30 minutos.
    # Na simulacao nao roda, porque o kit grava no .claude\ do Cerebro.
    $kitScript = Join-Path $Cerebro $Kit
    if ($SemKit -or $Simular) {
        # nada
    } elseif (-not (Test-Path -LiteralPath $kitScript)) {
        Registrar "[!] Kit Claude nao publicado: $kitScript nao existe."
    } else {
        $kitLog = Join-Path (Split-Path $Log -Parent) 'kit-claude-github.txt'
        $anterior = $ErrorActionPreference
        $ErrorActionPreference = 'Continue'
        & powershell.exe -NoProfile -ExecutionPolicy Bypass -File $kitScript `
            -Executar -Cerebro $Cerebro -Log $kitLog 2>&1 | Out-Null
        $kitCodigo = $LASTEXITCODE
        $ErrorActionPreference = $anterior
        if ($kitCodigo -ne 0) {
            Registrar "[!] Kit Claude falhou (codigo $kitCodigo) - o Cerebro segue sem ele. Veja $kitLog"
        }
    }

    # ------------------------------------------------------------- 1. add
    RodarGit add -A | Out-Null
    if ($script:GitCodigo -ne 0) { Parar 'git add falhou.' }
    $mudados = @(RodarGit diff --cached --name-only | Where-Object { $_ })

    if ($mudados.Count -gt 0) {
        # ------------------------------------------------------ 2. travas
        $problema = $null
        $sensiveis = @($mudados | Where-Object { $_ -match $script:CaminhoSensivel })
        if ($sensiveis.Count -gt 0) {
            $problema = "caminho com cara de segredo: $($sensiveis[0..([Math]::Min(4, $sensiveis.Count) - 1)] -join ', ')"
        } elseif ($mudados.Count -gt $LimiteArquivos) {
            $problema = "$($mudados.Count) arquivos de uma vez (limite $LimiteArquivos). Pasta nova que devia estar no .gitignore?"
        } else {
            # Diz EM QUAL nota esta o problema (o valor nunca vai para o log).
            $atual = $null
            $comChave = New-Object System.Collections.ArrayList
            foreach ($l in (RodarGit diff --cached -U0 --no-color)) {
                if ($l.StartsWith('+++ ')) { $atual = ($l.Substring(4) -replace '^b/', '').TrimEnd("`t"); continue }
                if ($l.StartsWith('+') -and $l -match $script:ConteudoSensivel -and
                    -not $comChave.Contains($atual)) { [void]$comChave.Add($atual) }
            }
            if ($comChave.Count -gt 0) {
                $problema = "conteudo com cara de chave/token em $($comChave.Count) arquivo(s) (valor nao registrado): $(@($comChave)[0..([Math]::Min(4, $comChave.Count) - 1)] -join ', ')"
            }
        }
        if ($problema) {
            RodarGit reset -q | Out-Null   # desfaz o add; os arquivos ficam como estavam
            Parar "TRAVA - nada enviado: $problema"
        }

        if ($Simular) {
            RodarGit reset -q | Out-Null
            Registrar "[SIMULACAO] Enviaria $($mudados.Count) arquivo(s) para $remoto ($ramo):"
            $mudados | Select-Object -First 20 | ForEach-Object { Registrar "    $_" }
            exit 0
        }

        # ----------------------------------------------------- 3. commit
        $msg = "Sincronizacao automatica do $env:COMPUTERNAME - $(Get-Date -Format 'dd/MM/yyyy HH:mm') ($($mudados.Count) arquivo(s))"
        RodarGit commit -q -m $msg | Out-Null
        if ($script:GitCodigo -ne 0) { Parar 'git commit falhou (user.name/user.email configurados?).' }
    } elseif ($Simular) {
        Registrar '[SIMULACAO] Nada novo no Cerebro.'
        exit 0
    }

    # ------------------------------------------- 4. trazer o que veio de fora
    RodarGit fetch -q origin $ramo | Out-Null
    if ($script:GitCodigo -ne 0) { Parar "git fetch falhou - sem internet ou sem acesso a $remoto." }
    $atras  = [int](RodarGit rev-list --count "HEAD..origin/$ramo" | Select-Object -First 1)
    if ($atras -gt 0) {
        RodarGit merge --no-edit -q "origin/$ramo" | Out-Null
        if ($script:GitCodigo -ne 0) {
            RodarGit merge --abort | Out-Null
            Parar "CONFLITO ao juntar $atras commit(s) do GitHub. Merge desfeito; o commit local foi mantido. Resolva a mao."
        }
    }

    # ------------------------------------------------------------- 5. push
    $frente = [int](RodarGit rev-list --count "origin/$ramo..HEAD" | Select-Object -First 1)
    if ($frente -eq 0) {
        Registrar "[OK] Nada a enviar. GitHub em dia ($ramo)."
        exit 0
    }
    RodarGit push -q origin $ramo | Out-Null
    if ($script:GitCodigo -ne 0) { Parar "git push falhou - credencial do GitHub expirou? Rode um 'git push' a mao em $Cerebro." }

    # Mandei nao e mandou: confere que o GitHub ficou igual.
    RodarGit fetch -q origin $ramo | Out-Null
    $local  = (RodarGit rev-parse HEAD | Select-Object -First 1)
    $github = (RodarGit rev-parse "origin/$ramo" | Select-Object -First 1)
    if ($local -ne $github) { Parar "Push respondeu OK, mas o GitHub esta em $github e aqui em $local." }

    Registrar "[OK] Enviado: $($mudados.Count) arquivo(s) novo(s)/alterado(s), $frente commit(s), recebidos $atras. GitHub em $($local.Substring(0,7))."
    exit 0
} finally {
    $mutex.ReleaseMutex()
    $mutex.Dispose()
}
