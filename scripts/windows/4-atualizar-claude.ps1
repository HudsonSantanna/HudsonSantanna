#Requires -Version 5.1
<#
    4-atualizar-claude.ps1 - Inventaria, confere e atualiza a configuracao do
    Claude Code do servidor: COMANDOS, AGENTES, SKILLS e HOOKS.

    Mexe SOMENTE nestas quatro coisas dentro de ~\.claude:
        commands\   agents\   skills\   e a chave "hooks" do settings.json
    Nao toca em credencial (.credentials.json, .claude.json), em sessoes,
    projects, plugins nem no venv de security.

    Por padrao apenas SIMULA e le. Para gravar de verdade, use -Executar.
    Nada e apagado: a copia e robocopy SEM /MIR, e todo arquivo tocado vai
    antes para um checkpoint com data e hora.

    Uso:
      # 1) so olhar: inventario + conferencia do que ja esta na maquina
      powershell -ExecutionPolicy Bypass -File .\4-atualizar-claude.ps1

      # 2) comparar com a origem da atualizacao (nao grava nada)
      .\4-atualizar-claude.ps1 -Origem "D:\ARGOS-SERVIDOR\dados\claude"

      # 3) aplicar de verdade (faz checkpoint antes)
      .\4-atualizar-claude.ps1 -Origem "D:\ARGOS-SERVIDOR\dados\claude" -Executar

      # rodar fora do KHAOSOMNI (o notebook, por exemplo)
      .\4-atualizar-claude.ps1 -Forcar
#>
[CmdletBinding()]
param(
    [string]$Claude      = "$env:USERPROFILE\.claude",
    [string]$Origem,
    [switch]$Executar,
    [switch]$Forcar,
    [string]$Servidor    = 'KHAOSOMNI',
    [string]$Checkpoints = 'C:\Argos-Backups\_checkpoints',
    [string]$Log
)

$ErrorActionPreference = 'Stop'

# A Area de Trabalho nem sempre e "$env:USERPROFILE\Desktop": com OneDrive ela
# vira "...\OneDrive\Area de Trabalho" e aquele caminho NAO existe. Perguntar ao
# Windows onde ela esta de verdade, e cair no perfil do usuario se nem isso der.
if (-not $Log) {
    $desk = [Environment]::GetFolderPath('Desktop')
    if (-not $desk -or -not (Test-Path -LiteralPath $desk)) { $desk = $env:USERPROFILE }
    $Log = Join-Path $desk "atualizar-claude-$(Get-Date -Format 'yyyyMMdd-HHmm').txt"
}

$script:Linhas    = New-Object System.Collections.ArrayList
$script:Problemas = New-Object System.Collections.ArrayList
$script:Carimbo   = Get-Date -Format 'yyyy-MM-dd_HHmm'

# as partes que este script gerencia; o resto do .claude fica intocado
$script:Partes = @('commands', 'agents', 'skills')

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
function Problema([string]$Onde, [string]$Texto) {
    [void]$script:Problemas.Add(('{0,-42} {1}' -f $Onde, $Texto))
}

function LerTexto([string]$Arquivo) {
    $txt = Get-Content -LiteralPath $Arquivo -Raw -Encoding UTF8 -ErrorAction SilentlyContinue
    if ($null -eq $txt) { return '' }
    $txt.TrimStart([char]0xFEFF)
}

# Le o bloco --- ... --- do topo do arquivo. Devolve so as chaves de primeiro
# nivel, que e o que o Claude Code usa para disparar (name, description...).
function LerFrontmatter([string]$Arquivo) {
    $campos = @{}
    $txt = LerTexto $Arquivo
    if ($txt -eq '') { return $campos }
    $linhas = $txt -split "`r?`n"
    if ($linhas[0].Trim() -ne '---') { return $campos }
    for ($i = 1; $i -lt $linhas.Count; $i++) {
        if ($linhas[$i].Trim() -eq '---') { break }
        if ($linhas[$i] -match '^([A-Za-z0-9_-]+)\s*:\s*(.*)$') {
            $campos[$matches[1].ToLower()] = $matches[2].Trim().Trim('"', "'")
        }
    }
    return $campos
}

# Tira do comando do hook todo caminho que da para conferir. Precisa achar
# tambem no meio da linha: "powershell -File C:\Scripts\x.ps1" e o formato
# mais comum, e ali o caminho nao esta no inicio.
function CaminhosDoComando([string]$Comando) {
    $achados = @()
    $padrao = '(?:[A-Za-z]:\\|\\\\|~[\\/])[^\s"'']+'
    foreach ($m in [regex]::Matches([string]$Comando, $padrao)) {
        $achados += ($m.Value.TrimEnd('\', '/', ',', ';') -replace '^~', $env:USERPROFILE)
    }
    return $achados
}

function Hash([string]$Arquivo) {
    (Get-FileHash -LiteralPath $Arquivo -Algorithm SHA256).Hash
}

# Copia para C:\Argos-Backups\_checkpoints\<carimbo>\<nome> antes de qualquer
# escrita. Regra da casa: toda alteracao tem volta.
function Checkpoint([string]$Caminho, [string]$Nome) {
    if (-not (Test-Path -LiteralPath $Caminho)) { return $null }
    $destino = Join-Path (Join-Path $Checkpoints $script:Carimbo) $Nome
    New-Item -ItemType Directory -Path (Split-Path $destino -Parent) -Force | Out-Null
    if (Test-Path -LiteralPath $Caminho -PathType Container) {
        & robocopy $Caminho $destino /E /R:1 /W:1 /NFL /NDL /NJH /NJS /NP | Out-Null
        if ($LASTEXITCODE -ge 8) { throw "Checkpoint de $Caminho falhou (robocopy $LASTEXITCODE)." }
    } else {
        Copy-Item -LiteralPath $Caminho -Destination $destino -Force
    }
    return $destino
}

# ------------------------------------------------------------ trava de dono
# As automacoes tem DONO UNICO. Rodar isto no notebook e no servidor deixa as
# duas maquinas com configuracoes divergentes, em silencio.
if ($env:COMPUTERNAME -ne $Servidor -and -not $Forcar) {
    Write-Host ''
    Write-Host "  PARE: esta maquina e $env:COMPUTERNAME, nao o servidor $Servidor." -ForegroundColor Red
    Write-Host '  Este script gerencia a configuracao do servidor. Se e mesmo aqui'  -ForegroundColor Red
    Write-Host '  que voce quer rodar, repita com -Forcar.'                          -ForegroundColor Red
    Write-Host ''
    exit 1
}

Escrever "Claude Code - comandos, agentes, skills e hooks"
Escrever "$(Get-Date -Format 'dd/MM/yyyy HH:mm')   Maquina: $env:COMPUTERNAME   Usuario: $env:USERNAME"
Escrever "Configuracao: $Claude"
if ($Origem)      { Escrever "Origem ......: $Origem" }
if (-not $Executar) { Escrever 'MODO SIMULACAO - nada sera gravado (use -Executar para valer)' }

if (-not (Test-Path -LiteralPath $Claude)) {
    Escrever ''
    Escrever "PARE: nao existe $Claude nesta maquina."
    Escrever 'Rode antes o 3-Migrar-Dados.ps1 do kit do servidor.'
    $script:Linhas | Set-Content -LiteralPath $Log -Encoding UTF8
    exit 1
}

# =============================================================== INVENTARIO
Titulo 'SKILLS'
$skills = @()
$pastaSkills = Join-Path $Claude 'skills'
if (Test-Path -LiteralPath $pastaSkills) {
    foreach ($dir in (Get-ChildItem -LiteralPath $pastaSkills -Directory | Sort-Object Name)) {
        $md = Join-Path $dir.FullName 'SKILL.md'
        if (-not (Test-Path -LiteralPath $md)) {
            Problema $dir.Name 'pasta de skill SEM SKILL.md - o Claude nao carrega'
            continue
        }
        $fm = LerFrontmatter $md
        $skills += [pscustomobject]@{
            Pasta     = $dir.Name
            Nome      = $fm['name']
            Descricao = $fm['description']
            Alterado  = (Get-Item -LiteralPath $md).LastWriteTime
        }
        if (-not $fm['name'])        { Problema $dir.Name 'SKILL.md sem "name" no frontmatter' }
        elseif ($fm['name'] -ne $dir.Name) { Problema $dir.Name "frontmatter name = '$($fm['name'])' difere da pasta" }
        if (-not $fm['description']) { Problema $dir.Name 'SKILL.md sem "description" - a skill nunca dispara sozinha' }
        elseif ($fm['description'].Length -lt 25) { Problema $dir.Name 'description curta demais - o disparo fica impreciso' }
    }
} else {
    Problema 'skills\' 'pasta nao existe'
}
Escrever ("{0} skill(s)" -f $skills.Count)
Escrever ''
Escrever ('{0,-32} {1,-16} {2}' -f 'PASTA', 'ALTERADA EM', 'DESCRICAO')
foreach ($s in $skills) {
    $d = $s.Descricao
    if (-not $d) { $d = '(sem description)' }
    if ($d.Length -gt 70) { $d = $d.Substring(0, 67) + '...' }
    Escrever ('{0,-32} {1,-16} {2}' -f $s.Pasta, $s.Alterado.ToString('dd/MM/yy HH:mm'), $d)
}

# As 6 "Hooks" do Cerebro (hook-radar, hook-cacador, hook-motor, hook-vigia,
# hook-vitrine, hook-escoador) sao SKILLS com esse nome - nao sao hooks do
# settings.json. Separar aqui evita procurar no lugar errado.
$hookSkills = @($skills | Where-Object { $_.Pasta -like 'hook-*' })
if ($hookSkills.Count -gt 0) {
    Escrever ''
    Escrever "Destas, $($hookSkills.Count) sao as 'Hooks' do Cerebro (skills chamadas hook-*):"
    Escrever ('  ' + (($hookSkills | ForEach-Object { $_.Pasta }) -join ' . '))
    Escrever '  (sao skills, nao hooks do settings.json - ver a secao HOOKS abaixo)'
}

Titulo 'COMANDOS  (as barras: /nome)'
$comandos = @()
$pastaCmd = Join-Path $Claude 'commands'
if (Test-Path -LiteralPath $pastaCmd) {
    foreach ($f in (Get-ChildItem -LiteralPath $pastaCmd -Recurse -File -Filter *.md | Sort-Object FullName)) {
        $rel = $f.FullName.Substring($pastaCmd.Length).TrimStart('\')
        # subpasta vira namespace: vendas\proposta.md -> /vendas:proposta
        $slash = '/' + ($rel -replace '\.md$', '' -replace '\\', ':')
        $fm = LerFrontmatter $f.FullName
        $comandos += [pscustomobject]@{
            Comando   = $slash
            Arquivo   = $rel
            Descricao = $fm['description']
            Alterado  = $f.LastWriteTime
        }
        if (-not $fm['description']) { Problema $slash 'comando sem "description" - nao aparece no /help' }
    }
} else {
    Problema 'commands\' 'pasta nao existe (nenhum comando proprio instalado)'
}
Escrever ("{0} comando(s)" -f $comandos.Count)
Escrever ''
foreach ($c in $comandos) {
    $d = $c.Descricao
    if (-not $d) { $d = '(sem description)' }
    if ($d.Length -gt 62) { $d = $d.Substring(0, 59) + '...' }
    Escrever ('{0,-28} {1,-16} {2}' -f $c.Comando, $c.Alterado.ToString('dd/MM/yy HH:mm'), $d)
}

Titulo 'AGENTES  (subagentes)'
$agentes = @()
$pastaAg = Join-Path $Claude 'agents'
if (Test-Path -LiteralPath $pastaAg) {
    foreach ($f in (Get-ChildItem -LiteralPath $pastaAg -Recurse -File -Filter *.md | Sort-Object FullName)) {
        $fm = LerFrontmatter $f.FullName
        $agentes += [pscustomobject]@{
            Arquivo   = $f.BaseName
            Nome      = $fm['name']
            Modelo    = $fm['model']
            Descricao = $fm['description']
            Alterado  = $f.LastWriteTime
        }
        if (-not $fm['name'])        { Problema $f.Name 'agente sem "name" no frontmatter' }
        elseif ($fm['name'] -ne $f.BaseName) { Problema $f.Name "frontmatter name = '$($fm['name'])' difere do arquivo" }
        if (-not $fm['description']) { Problema $f.Name 'agente sem "description" - o Claude nao sabe quando chamar' }
    }
} else {
    Problema 'agents\' 'pasta nao existe (nenhum subagente proprio instalado)'
}
Escrever ("{0} agente(s)" -f $agentes.Count)
Escrever ''
foreach ($a in $agentes) {
    $m = $a.Modelo
    if (-not $m) { $m = '(herda)' }
    $d = $a.Descricao
    if (-not $d) { $d = '(sem description)' }
    if ($d.Length -gt 50) { $d = $d.Substring(0, 47) + '...' }
    Escrever ('{0,-24} {1,-12} {2}' -f $a.Arquivo, $m, $d)
}

# Nome repetido entre skill e comando confunde o disparo: /x pode ser as duas.
foreach ($nome in ($skills | ForEach-Object { $_.Pasta })) {
    if ($comandos | Where-Object { $_.Comando -eq "/$nome" }) {
        Problema $nome 'existe como skill E como comando - o /nome fica ambiguo'
    }
}

Titulo 'HOOKS  (settings.json)'
$arqSettings = @(
    (Join-Path $Claude 'settings.json'),
    (Join-Path $Claude 'settings.local.json')
)
$totalHooks = 0
foreach ($arq in $arqSettings) {
    if (-not (Test-Path -LiteralPath $arq)) {
        Escrever "$(Split-Path $arq -Leaf): nao existe"
        continue
    }
    $cfg = $null
    try { $cfg = (LerTexto $arq) | ConvertFrom-Json }
    catch {
        Problema (Split-Path $arq -Leaf) "JSON invalido - o Claude ignora o arquivo inteiro: $($_.Exception.Message)"
        Escrever "$(Split-Path $arq -Leaf): JSON INVALIDO"
        continue
    }
    Escrever ''
    Escrever "$(Split-Path $arq -Leaf):"
    if (-not $cfg.hooks) { Escrever '  (nenhum hook configurado)'; continue }

    foreach ($evento in $cfg.hooks.PSObject.Properties) {
        foreach ($grupo in @($evento.Value)) {
            $matcher = $grupo.matcher
            if (-not $matcher) { $matcher = '*' }
            foreach ($h in @($grupo.hooks)) {
                $totalHooks++
                Escrever ('  {0,-18} {1,-14} {2}' -f $evento.Name, $matcher, $h.command)
                # o hook so vale se o que ele chama existir na maquina
                foreach ($caminho in (CaminhosDoComando $h.command)) {
                    if (-not (Test-Path -LiteralPath $caminho)) {
                        Problema "$($evento.Name)/$matcher" "hook chama caminho que nao existe: $caminho"
                    }
                }
            }
        }
    }
}
Escrever ''
Escrever "$totalHooks hook(s) configurado(s)"

# ================================================== COMPARACAO COM A ORIGEM
$paraCopiar = @()
if ($Origem) {
    Titulo 'COMPARACAO COM A ORIGEM'
    if (-not (Test-Path -LiteralPath $Origem)) {
        Escrever "PARE: origem nao encontrada: $Origem"
        $script:Linhas | Set-Content -LiteralPath $Log -Encoding UTF8
        exit 1
    }

    $novos = 0; $mudados = 0; $iguais = 0; $soAqui = 0
    foreach ($parte in $script:Partes) {
        $de   = Join-Path $Origem $parte
        $para = Join-Path $Claude $parte
        if (-not (Test-Path -LiteralPath $de)) {
            Escrever "$parte\: nao veio na origem - sera preservado como esta"
            continue
        }
        foreach ($f in (Get-ChildItem -LiteralPath $de -Recurse -File)) {
            $rel     = $f.FullName.Substring($de.Length).TrimStart('\')
            $destino = Join-Path $para $rel
            if (-not (Test-Path -LiteralPath $destino)) {
                $novos++; $paraCopiar += "$parte\$rel"
                Escrever ('  NOVO       {0}\{1}' -f $parte, $rel)
            } elseif ((Hash $f.FullName) -ne (Hash $destino)) {
                $mudados++; $paraCopiar += "$parte\$rel"
                Escrever ('  DIFERENTE  {0}\{1}' -f $parte, $rel)
            } else {
                $iguais++
            }
        }
        # o que existe so aqui nao e apagado: robocopy roda sem /MIR
        if (Test-Path -LiteralPath $para) {
            foreach ($f in (Get-ChildItem -LiteralPath $para -Recurse -File)) {
                $rel = $f.FullName.Substring($para.Length).TrimStart('\')
                if (-not (Test-Path -LiteralPath (Join-Path $de $rel))) {
                    $soAqui++
                    Escrever ('  SO AQUI    {0}\{1}   (preservado)' -f $parte, $rel)
                }
            }
        }
    }
    Escrever ''
    Escrever "novos: $novos   diferentes: $mudados   iguais: $iguais   so no servidor: $soAqui (nada e apagado)"
}

# ============================================================== APLICAR
if ($Origem -and $Executar) {
    Titulo 'APLICANDO'
    if ($paraCopiar.Count -eq 0) {
        Escrever 'Nada a copiar: comandos, agentes e skills ja estao iguais a origem.'
    } else {
        foreach ($parte in $script:Partes) {
            $de   = Join-Path $Origem $parte
            $para = Join-Path $Claude $parte
            if (-not (Test-Path -LiteralPath $de)) { continue }

            $cp = Checkpoint $para $parte
            if ($cp) { Escrever "checkpoint de $parte\ em $cp" }

            # /E subpastas . SEM /MIR: nada e apagado no destino
            & robocopy $de $para /E /R:1 /W:1 /NFL /NDL /NJH /NJS /NP | Out-Null
            if ($LASTEXITCODE -ge 8) {
                Escrever "  $parte\: FALHOU (robocopy $LASTEXITCODE)"
                Problema "$parte\" "copia falhou (robocopy $LASTEXITCODE)"
            } else {
                Escrever "  $parte\: OK (robocopy $LASTEXITCODE)"
            }
        }
    }

    # --- hooks: trocar SO a chave "hooks", preservando permissions e o resto -
    $origemSettings  = Join-Path $Origem 'settings.json'
    $destinoSettings = Join-Path $Claude 'settings.json'
    if (Test-Path -LiteralPath $origemSettings) {
        Escrever ''
        Escrever 'HOOKS: trocando so a chave "hooks" do settings.json'
        try {
            $novo = (LerTexto $origemSettings) | ConvertFrom-Json
        } catch {
            $novo = $null
            Problema 'settings.json (origem)' "JSON invalido - hooks nao atualizados: $($_.Exception.Message)"
            Escrever "  PULADO: o settings.json da origem tem JSON invalido."
        }
        if ($novo) {
            $atual = $null
            if (Test-Path -LiteralPath $destinoSettings) {
                try { $atual = (LerTexto $destinoSettings) | ConvertFrom-Json }
                catch {
                    Problema 'settings.json (servidor)' 'JSON invalido - nao mexi para nao piorar'
                    Escrever '  PULADO: o settings.json do servidor tem JSON invalido. Conserte a mao.'
                }
            } else {
                $atual = [pscustomobject]@{}
            }
            if ($atual) {
                $cp = Checkpoint $destinoSettings 'settings.json'
                if ($cp) { Escrever "  checkpoint em $cp" }
                if ($novo.PSObject.Properties.Name -contains 'hooks') {
                    if ($atual.PSObject.Properties.Name -contains 'hooks') {
                        $atual.hooks = $novo.hooks
                    } else {
                        $atual | Add-Member -NotePropertyName 'hooks' -NotePropertyValue $novo.hooks
                    }
                    # permissions e o resto do arquivo ficam como estavam.
                    # Gravar SEM BOM: o Claude le este arquivo como JSON, e um
                    # BOM no inicio faz o parser recusar o arquivo inteiro.
                    $json = $atual | ConvertTo-Json -Depth 20
                    [System.IO.File]::WriteAllText(
                        $destinoSettings, $json, (New-Object System.Text.UTF8Encoding($false)))
                    Escrever '  hooks atualizados; permissions e o restante preservados.'
                } else {
                    Escrever '  a origem nao traz "hooks" - nada a trocar.'
                }
            }
        }
    }

    Escrever ''
    Escrever 'FEITO. Abra o Claude Code e rode /help e /doctor para confirmar o carregamento.'
} elseif ($Origem) {
    Titulo 'NADA FOI GRAVADO'
    Escrever "Isto foi so a simulacao. Para aplicar, repita com -Executar:"
    Escrever "  .\4-atualizar-claude.ps1 -Origem `"$Origem`" -Executar"
    Escrever "Antes de gravar, tudo que for tocado vai para $Checkpoints\$script:Carimbo\."
}

# ============================================================== CONFERENCIA
Titulo 'CONFERENCIA'
if ($script:Problemas.Count -eq 0) {
    Escrever 'Nenhum problema encontrado nos comandos, agentes, skills e hooks.'
} else {
    Escrever "$($script:Problemas.Count) ponto(s) para olhar:"
    Escrever ''
    foreach ($p in $script:Problemas) { Escrever "  $p" }
}

Titulo 'RESUMO'
Escrever ("comandos: {0}   agentes: {1}   skills: {2}   hooks: {3}   problemas: {4}" -f `
    $comandos.Count, $agentes.Count, $skills.Count, $totalHooks, $script:Problemas.Count)
Escrever ''
Escrever "Relatorio salvo em: $Log"

$script:Linhas | Set-Content -LiteralPath $Log -Encoding UTF8
