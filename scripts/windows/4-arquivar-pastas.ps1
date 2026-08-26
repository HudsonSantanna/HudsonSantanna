#Requires -Version 5.1
<#
    4-arquivar-pastas.ps1 - Inventaria as pastas de uma pasta-mae, mostra o
    tamanho real de cada uma e arquiva no HD externo as que voce autorizar.

    A ordem nunca muda: COPIA -> CONFERE POR HASH SHA256 -> so entao APAGA.
    Nada e movido sem voce nomear a pasta e passar -Confirmar.

    No lugar da pasta que saiu, fica um ATALHO apontando para o HD, e um
    indice em CSV registra o que foi para onde.

    Uso:
      # 1) mapa: tamanho, data e alertas de cada pasta (nao mexe em nada)
      .\4-arquivar-pastas.ps1 -Origem "C:\Users\hudso\Desktop\Argos"

      # 2) ensaio do arquivamento (nao copia nem apaga nada)
      .\4-arquivar-pastas.ps1 -Origem "..." -Pastas "Instaladores","backup HD"

      # 3) para valer
      .\4-arquivar-pastas.ps1 -Origem "..." -Pastas "Instaladores" -Confirmar

      # 4) achar depois o que foi arquivado
      .\4-arquivar-pastas.ps1 -Origem "..." -Procurar "nota fiscal"
#>
[CmdletBinding()]
param(
    [Parameter(Mandatory = $true)][string]$Origem,
    [string]  $Destino  = 'E:\Backup HUDSON_SANTANA',
    [string[]]$Pastas,
    [string]  $Procurar,
    [switch]  $Confirmar,
    [switch]  $SemAtalho,
    [string]  $Log = "$env:USERPROFILE\Desktop\arquivamento-$(Get-Date -Format 'yyyyMMdd-HHmm').txt"
)

$ErrorActionPreference = 'Stop'
$script:Linhas = New-Object System.Collections.ArrayList

# O robocopy tem log proprio: se escrevesse no mesmo arquivo, o resumo final
# sobrescreveria tudo que ele registrou.
$LogRobocopy = $Log -replace '\.txt$', '-robocopy.txt'

# --------------------------------------------------------------- ferramentas
function Escrever([string]$Texto = '') {
    Write-Host $Texto
    [void]$script:Linhas.Add($Texto)
}
function Titulo([string]$Texto) {
    Escrever ''
    Escrever ('=' * 74)
    Escrever "  $Texto"
    Escrever ('=' * 74)
}
function ComoGB($Bytes) {
    if ($null -eq $Bytes) { return '         -' }
    '{0,8:N2} GB' -f ($Bytes / 1GB)
}
function SalvarLog {
    $script:Linhas | Out-File -FilePath $Log -Encoding UTF8
    Write-Host ''
    Write-Host "Log: $Log" -ForegroundColor Green
    if (Test-Path -LiteralPath $LogRobocopy) {
        Write-Host "Log do robocopy: $LogRobocopy" -ForegroundColor Green
    }
}

# Lista FECHADA. Nada aqui e arquivado, nem que voce peca pelo nome.
$NUNCA_ARQUIVAR = @(
    'Windows', 'Program Files', 'Program Files (x86)', 'ProgramData',
    'AppData', 'Argos-Cerebro', 'Scripts',
    '.git', '.codex', '.claude', '.agents',
    'node_modules', 'dist', 'build', 'win-unpacked'
)

# Marcas que, se aparecerem DENTRO da pasta, exigem confirmacao extra.
$MARCAS_DE_RISCO = @('.git', '.codex', '.claude', '.agents', 'node_modules',
                     'dist', 'build', 'win-unpacked')

# Sugestao por nome. E so sugestao: o script nunca age sozinho por causa dela.
$SUGESTAO = [ordered]@{
    'instaladores'   = 'ARQUIVAR  - instalador se baixa de novo'
    'backup'         = 'ARQUIVAR  - backup nao precisa estar no disco de trabalho'
    'todas as pastas'= 'ARQUIVAR  - copia antiga em massa'
    'fotos'          = 'ARQUIVAR  - foto pesa e raramente e material de trabalho'
    'campanha'       = 'ARQUIVAR  - campanha encerrada'
    'marketing'      = 'ARQUIVAR  - peca pronta, consulta esporadica'
    'sorteio'        = 'ARQUIVAR  - evento passado'
    'ffmpeg'         = 'CONFIRMAR - pode estar no PATH de outro programa'
    'bixolon'        = 'CONFIRMAR - driver de impressora em uso?'
    'impressora'     = 'CONFIRMAR - driver de impressora em uso?'
    'fonte'          = 'CONFIRMAR - codigo-fonte: pequeno e precioso'
    'clientes'       = 'MANTER    - dado de negocio ativo'
    'leads'          = 'MANTER    - dado de negocio ativo'
    'documentos'     = 'MANTER    - documento em uso'
    'omni'           = 'MANTER    - projeto ativo'
    'whisper'        = 'MANTER    - projeto ativo'
    'khaosomni'      = 'MANTER    - projeto ativo'
}
function Sugerir([string]$Nome) {
    $n = $Nome.ToLower()
    foreach ($chave in $SUGESTAO.Keys) {
        if ($n.Contains($chave)) { return $SUGESTAO[$chave] }
    }
    return 'CONFIRMAR - nao reconheci pelo nome'
}

function Inspecionar([string]$Caminho) {
    $tam = [int64]0
    $qtd = 0
    $ultima = [datetime]'1900-01-01'
    $marcas = New-Object System.Collections.ArrayList

    Get-ChildItem -LiteralPath $Caminho -Recurse -Force -ErrorAction SilentlyContinue |
        ForEach-Object {
            if ($_.PSIsContainer) {
                if ($MARCAS_DE_RISCO -contains $_.Name -and -not $marcas.Contains($_.Name)) {
                    [void]$marcas.Add($_.Name)
                }
            } else {
                $tam += $_.Length
                $qtd++
                if ($_.LastWriteTime -gt $ultima) { $ultima = $_.LastWriteTime }
            }
        }

    [pscustomobject]@{
        Nome     = Split-Path $Caminho -Leaf
        Caminho  = $Caminho
        Tamanho  = $tam
        Arquivos = $qtd
        Ultima   = $ultima
        Marcas   = ($marcas -join ',')
    }
}

function MapaDeHashes([string]$Raiz, [string]$Rotulo) {
    $mapa = @{}
    $prefixo = (Resolve-Path -LiteralPath $Raiz).Path.TrimEnd('\') + '\'
    $n = 0
    Get-ChildItem -LiteralPath $Raiz -Recurse -File -Force -ErrorAction SilentlyContinue |
        ForEach-Object {
            $n++
            if (($n % 200) -eq 0) { Write-Host "  $Rotulo : $n arquivos conferidos" }
            $rel = $_.FullName.Substring($prefixo.Length)
            try {
                $mapa[$rel] = (Get-FileHash -LiteralPath $_.FullName -Algorithm SHA256).Hash
            } catch {
                # Nao conseguiu ler: registra como ilegivel para a conferencia falhar.
                $mapa[$rel] = "ILEGIVEL: $($_.Exception.Message)"
            }
        }
    return $mapa
}

# ------------------------------------------------------------------ validacao
if (-not (Test-Path -LiteralPath $Origem)) { throw "Origem nao encontrada: $Origem" }

$letraDestino = Split-Path -Qualifier $Destino
if (-not (Test-Path -LiteralPath "$letraDestino\")) {
    throw "O HD externo ($letraDestino) nao esta conectado. Ligue o HD e rode de novo."
}

Escrever "Arquivamento para o HD externo - $(Get-Date -Format 'dd/MM/yyyy HH:mm')"
Escrever "Origem .: $Origem"
Escrever "Destino : $Destino"

# ------------------------------------------------------------------- procurar
if ($Procurar) {
    Titulo "PROCURANDO '$Procurar' NO HD EXTERNO"
    if (-not (Test-Path -LiteralPath $Destino)) {
        Escrever 'Ainda nao ha nada arquivado neste destino.'
        SalvarLog
        exit 0
    }
    $achados = Get-ChildItem -LiteralPath $Destino -Recurse -Force -ErrorAction SilentlyContinue |
        Where-Object { $_.Name -like "*$Procurar*" }
    if ($achados) {
        foreach ($a in $achados) {
            if ($a.PSIsContainer) { $tamanho = '   (pasta)' } else { $tamanho = ComoGB $a.Length }
            Escrever ('{0}  {1:dd/MM/yyyy}  {2}' -f $tamanho, $a.LastWriteTime, $a.FullName)
        }
        Escrever ''
        Escrever ("{0} item(ns) encontrado(s)." -f @($achados).Count)
    } else {
        Escrever 'Nada encontrado com esse termo.'
        $indice = Join-Path $Destino '_indice-arquivados.csv'
        if (Test-Path -LiteralPath $indice) { Escrever "Consulte tambem o indice: $indice" }
    }
    SalvarLog
    exit 0
}

# --------------------------------------------------------------------- mapa
Titulo 'MAPA DAS PASTAS'
Escrever 'Medindo cada pasta... em disco cheio isso leva alguns minutos.'
Escrever ''

$subpastas = Get-ChildItem -LiteralPath $Origem -Directory -Force -ErrorAction SilentlyContinue
if (-not $subpastas) { throw "Nenhuma subpasta em $Origem" }

$inventario = New-Object System.Collections.ArrayList
foreach ($p in $subpastas) {
    [void]$inventario.Add((Inspecionar $p.FullName))
}

$ordenado = $inventario | Sort-Object Tamanho -Descending
Escrever ('{0,-34} {1,11} {2,9} {3,12}  {4}' -f 'Pasta', 'Tamanho', 'Arquivos', 'Ultima', 'Sugestao')
Escrever ('-' * 110)
foreach ($i in $ordenado) {
    $nomeCurto = $i.Nome
    if ($nomeCurto.Length -gt 33) { $nomeCurto = $nomeCurto.Substring(0, 30) + '...' }
    Escrever ('{0,-34} {1,11} {2,9} {3,12:dd/MM/yyyy}  {4}' -f `
        $nomeCurto, (ComoGB $i.Tamanho).Trim(), $i.Arquivos, $i.Ultima, (Sugerir $i.Nome))
    if ($i.Marcas) {
        Escrever ('{0,-34} ^^ contem: {1} - projeto de codigo, NAO arquive sem pensar' -f '', $i.Marcas)
    }
}

$total = ($inventario | Measure-Object -Property Tamanho -Sum).Sum
Escrever ''
Escrever ("Total em {0} pastas: {1}" -f @($inventario).Count, (ComoGB $total))

$unidadeSistema = $env:SystemDrive
$volC = Get-Volume -DriveLetter $unidadeSistema.TrimEnd(':') -ErrorAction SilentlyContinue
if ($volC) { Escrever ("Livre em {0} agora: {1}" -f $unidadeSistema, (ComoGB $volC.SizeRemaining)) }

Escrever ''
Escrever 'A coluna Sugestao e chute a partir do NOME. Quem decide e voce.'

if (-not $Pastas) {
    Escrever ''
    Escrever 'Nenhuma pasta escolhida. Para arquivar, repita nomeando as pastas:'
    Escrever '  .\4-arquivar-pastas.ps1 -Origem "..." -Pastas "Instaladores","backup HD"'
    Escrever 'Isso ainda sera um ensaio. Para agir de verdade, acrescente -Confirmar.'
    SalvarLog
    exit 0
}

# ---------------------------------------------------------------- selecao
Titulo 'PASTAS ESCOLHIDAS'
$fila = New-Object System.Collections.ArrayList
foreach ($nome in $Pastas) {
    $item = $inventario | Where-Object { $_.Nome -eq $nome }
    if (-not $item) {
        Escrever "IGNORADA (nao existe em $Origem): $nome"
        continue
    }
    if ($NUNCA_ARQUIVAR -contains $nome) {
        Escrever "RECUSADA (lista de protecao da casa): $nome"
        continue
    }
    if ($item.Caminho -like '*OneDrive*') {
        Escrever "RECUSADA (dentro do OneDrive - mover de la apaga da nuvem): $nome"
        continue
    }
    if ($item.Marcas) {
        Escrever "ATENCAO: $nome contem $($item.Marcas). Confira se nao e projeto vivo."
    }
    Escrever ('SELECIONADA: {0,-30} {1} em {2} arquivos' -f $item.Nome, (ComoGB $item.Tamanho), $item.Arquivos)
    [void]$fila.Add($item)
}

if (@($fila).Count -eq 0) { Escrever ''; Escrever 'Nada a fazer.'; SalvarLog; exit 1 }

$somaFila = ($fila | Measure-Object -Property Tamanho -Sum).Sum
$livreHD = (Get-Volume -DriveLetter $letraDestino.TrimEnd(':')).SizeRemaining
Escrever ''
Escrever ("A arquivar ....: {0}" -f (ComoGB $somaFila))
Escrever ("Livre no HD ...: {0}" -f (ComoGB $livreHD))
if ($somaFila -gt $livreHD) { throw 'Espaco insuficiente no HD externo.' }

if (-not $Confirmar) {
    Escrever ''
    Escrever '>>> ENSAIO: nada foi copiado nem apagado. <<<'
    Escrever 'Repita o mesmo comando com -Confirmar para executar.'
    SalvarLog
    exit 0
}

if (-not (Test-Path -LiteralPath $Destino)) { New-Item -ItemType Directory -Path $Destino -Force | Out-Null }

$indiceCsv = Join-Path $env:USERPROFILE 'Desktop\indice-arquivados.csv'
$liberado = [int64]0

foreach ($item in $fila) {
    Titulo "ARQUIVANDO: $($item.Nome)"
    $destinoFinal = Join-Path $Destino $item.Nome

    if ((Test-Path -LiteralPath $destinoFinal) -and
        @(Get-ChildItem -LiteralPath $destinoFinal -Force -ErrorAction SilentlyContinue).Count -gt 0) {
        Escrever "PULADA: ja existe conteudo em $destinoFinal. Resolva a mao."
        continue
    }

    # 1. COPIA
    Escrever '1/4 Copiando com robocopy...'
    & robocopy $item.Caminho $destinoFinal /E /COPY:DAT /DCOPY:DAT /R:2 /W:5 /NP /LOG+:"$LogRobocopy" | Out-Null
    $codigo = $LASTEXITCODE
    if ($codigo -ge 8) {
        Escrever "FALHOU: robocopy retornou $codigo. Origem intacta, nada apagado."
        continue
    }
    Escrever "    copia terminou (codigo robocopy $codigo)"

    # 2. CONFERE POR HASH
    Escrever '2/4 Conferindo por hash SHA256 (le os dois lados; e a parte demorada)...'
    $hOrigem  = MapaDeHashes $item.Caminho  'origem '
    $hDestino = MapaDeHashes $destinoFinal  'destino'

    $faltando   = New-Object System.Collections.ArrayList
    $diferentes = New-Object System.Collections.ArrayList
    foreach ($rel in $hOrigem.Keys) {
        if (-not $hDestino.ContainsKey($rel)) { [void]$faltando.Add($rel) }
        elseif ($hDestino[$rel] -ne $hOrigem[$rel]) { [void]$diferentes.Add($rel) }
    }

    Escrever ("    origem: {0} arquivos | destino: {1} arquivos" -f $hOrigem.Count, $hDestino.Count)
    if (@($faltando).Count -gt 0 -or @($diferentes).Count -gt 0) {
        Escrever ("    NAO CONFERE: {0} faltando, {1} diferentes. NADA sera apagado." -f `
            @($faltando).Count, @($diferentes).Count)
        foreach ($f in ($faltando   | Select-Object -First 10)) { Escrever "      faltando: $f" }
        foreach ($d in ($diferentes | Select-Object -First 10)) { Escrever "      diferente: $d" }
        continue
    }
    Escrever '    conferido: todos os hashes batem.'

    # 3. APAGA A ORIGEM
    Escrever '3/4 Apagando a origem...'
    Remove-Item -LiteralPath $item.Caminho -Recurse -Force
    $liberado += $item.Tamanho
    Escrever ("    liberado: {0}" -f (ComoGB $item.Tamanho))

    # 4. DEIXA O CAMINHO DE VOLTA
    if (-not $SemAtalho) {
        try {
            $ws = New-Object -ComObject WScript.Shell
            $atalho = $ws.CreateShortcut((Join-Path $Origem ("$($item.Nome) (no HD $($letraDestino.TrimEnd(':'))).lnk")))
            $atalho.TargetPath   = $destinoFinal
            $atalho.Description  = "Arquivado no HD externo em $(Get-Date -Format 'dd/MM/yyyy'). Ligue o HD para abrir."
            $atalho.Save()
            Escrever '4/4 Atalho criado no lugar da pasta.'
        } catch {
            Escrever "4/4 Nao consegui criar o atalho: $($_.Exception.Message)"
        }
    }

    [pscustomobject]@{
        Data       = Get-Date -Format 'yyyy-MM-dd HH:mm'
        Pasta      = $item.Nome
        DeOnde     = $item.Caminho
        ParaOnde   = $destinoFinal
        TamanhoGB  = [math]::Round($item.Tamanho / 1GB, 2)
        Arquivos   = $item.Arquivos
    } | Export-Csv -Path $indiceCsv -Append -NoTypeInformation -Encoding UTF8
}

# -------------------------------------------------------------------- resumo
Titulo 'RESUMO'
Escrever ("Liberado no disco interno: {0}" -f (ComoGB $liberado))
$unidadeSistema = $env:SystemDrive
$volDepois = Get-Volume -DriveLetter $unidadeSistema.TrimEnd(':') -ErrorAction SilentlyContinue
if ($volDepois) { Escrever ("Livre em {0} agora .....: {1}" -f $unidadeSistema, (ComoGB $volDepois.SizeRemaining)) }

if (Test-Path -LiteralPath $indiceCsv) {
    Copy-Item -LiteralPath $indiceCsv -Destination (Join-Path $Destino '_indice-arquivados.csv') -Force -ErrorAction SilentlyContinue
    Escrever ''
    Escrever "Indice do que foi arquivado: $indiceCsv"
    Escrever "Copia do indice no HD .....: $(Join-Path $Destino '_indice-arquivados.csv')"
}
Escrever ''
Escrever 'Para achar um arquivo depois:'
Escrever '  .\4-arquivar-pastas.ps1 -Origem "<a mesma pasta>" -Procurar "parte do nome"'

SalvarLog
