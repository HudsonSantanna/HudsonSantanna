#Requires -Version 5.1
<#
    5-quarentena-hd.ps1 - Manda para o HD externo o que nao precisa ficar
    nesta maquina, seguindo a regra do Hudson (nota MANUTENCAO do Cerebro):

        "nao exclua, envia para uma pasta de backup no HD externo"

    Protocolo, sempre nesta ordem:  COPIA -> CONFERE SHA-256 -> so entao APAGA.
    Nada e apagado sem o hash bater. HD desconectado = nao faz nada.

    Destino: E:\_Quarentena-Argos\<AAAA-MM-DD>\  (+ INDICE.csv na raiz)
    O indice e o "se precisar e so buscar no HD": diz o que saiu, de onde,
    quando e com qual hash. E o -Restaurar traz de volta.

    Uso:
      # 1) so olhar: mede o disco e propoe o que pode ir (NAO move nada)
      powershell -ExecutionPolicy Bypass -File .\5-quarentena-hd.ps1

      # 2) copiar para o HD e conferir (ainda NAO apaga da maquina)
      .\5-quarentena-hd.ps1 -Executar

      # 3) depois de conferir o relatorio, liberar o espaco
      .\5-quarentena-hd.ps1 -Executar -Remover

      # trazer de volta o que precisar
      .\5-quarentena-hd.ps1 -Restaurar "Downloads-antigos" -Executar
      .\5-quarentena-hd.ps1 -Listar
#>
[CmdletBinding()]
param(
    [string]  $Destino     = 'E:',
    [string]  $Raiz        = '_Quarentena-Argos',
    [switch]  $Executar,
    [switch]  $Remover,
    [switch]  $Listar,
    [string]  $Restaurar   = '',
    [int]     $MinimoMB    = 200,
    [int]     $DiasParado  = 60,
    [string[]]$Incluir     = @(),
    [string]  $Log         = "$env:USERPROFILE\Desktop\quarentena-$(Get-Date -Format 'yyyyMMdd-HHmm').txt"
)

$ErrorActionPreference = 'Stop'
$script:Linhas = New-Object System.Collections.ArrayList

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
function ComoGB($Bytes) { '{0,8:N2} GB' -f ($Bytes / 1GB) }
function Salvar {
    $script:Linhas | Out-File -FilePath $Log -Encoding UTF8
    Write-Host ''
    Write-Host "Relatorio salvo em: $Log" -ForegroundColor Green
}

# ------------------------------------------------------------------ regras
# Nunca sai daqui. Cada item tem motivo - se mexer, a maquina quebra ou o
# trabalho para.
$PROTEGIDOS = @(
    @{ Padrao = 'claudevm\.bundle';        Motivo = 'VM do Claude Code em uso' }
    @{ Padrao = '\\\.claude(\\|$)';        Motivo = 'skills e config do Claude' }
    @{ Padrao = 'hiberfil\.sys';           Motivo = 'salva o trabalho quando a bateria acaba' }
    @{ Padrao = 'pagefile\.sys|swapfile\.sys'; Motivo = 'memoria virtual do Windows' }
    @{ Padrao = '\\Windows(\\|$)';         Motivo = 'sistema' }
    @{ Padrao = '\\Program Files';         Motivo = 'programas instalados' }
    @{ Padrao = 'Argos-Cerebro';           Motivo = 'o Cerebro e a fonte da verdade' }
    @{ Padrao = 'ArgosPrint|catalogo_argos|impressora_argos'; Motivo = 'agente de etiquetas em producao' }
    @{ Padrao = '07-Financeiro|espionagem|espiao'; Motivo = 'sigilo - decisao manual do Hudson' }
)

function EhProtegido([string]$Caminho) {
    foreach ($p in $PROTEGIDOS) {
        if ($Caminho -match $p.Padrao) { return $p.Motivo }
    }
    return $null
}

# ⚠️ ARMADILHA DE MEDICAO (nota MANUTENCAO, 22/07): Measure-Object Length devolve
# o tamanho LOGICO. Arquivo do OneDrive que esta so na nuvem NAO ocupa disco,
# mas conta ali - foi assim que "49,5 GB" de OneDrive viraram 8,89 GB reais.
# Placeholder tem o atributo FILE_ATTRIBUTE_RECALL_ON_DATA_ACCESS (0x400000).
$RECALL = 0x400000
function EstaNaNuvem($Arquivo) {
    return (([int]$Arquivo.Attributes -band $RECALL) -ne 0)
}
function TamanhoReal([string]$Caminho) {
    $total = [int64]0
    Get-ChildItem -LiteralPath $Caminho -Recurse -File -Force -ErrorAction SilentlyContinue |
        ForEach-Object { if (-not (EstaNaNuvem $_)) { $total += $_.Length } }
    return $total
}

# ------------------------------------------------------------------- HD
$raizQuarentena = Join-Path $Destino $Raiz
$pastaHoje      = Join-Path $raizQuarentena (Get-Date -Format 'yyyy-MM-dd')
$indice         = Join-Path $raizQuarentena 'INDICE.csv'

function ExigirHD {
    if (-not (Test-Path -LiteralPath "$Destino\")) {
        Escrever ''
        Escrever "PARE: o HD $Destino nao esta conectado."
        Escrever 'Regra do Hudson: sem HD plugado, NAO limpa. Ligue o HD e rode de novo.'
        Salvar
        exit 1
    }
}

Escrever "Quarentena para o HD - $(Get-Date -Format 'dd/MM/yyyy HH:mm')"
Escrever "Computador: $env:COMPUTERNAME   Usuario: $env:USERNAME"

# ---------------------------------------------------------------- listar
if ($Listar) {
    ExigirHD
    Titulo "O QUE JA ESTA NO HD $Destino"
    if (-not (Test-Path -LiteralPath $indice)) {
        Escrever '  Nada em quarentena ainda (INDICE.csv nao existe).'
    } else {
        foreach ($linha in (Import-Csv $indice)) {
            Escrever ("  {0,-34} {1,10}  {2}  de {3}" -f `
                $linha.Item, $linha.Tamanho, $linha.Data, $linha.Origem)
        }
    }
    Salvar
    exit 0
}

# -------------------------------------------------------------- restaurar
if ($Restaurar) {
    ExigirHD
    Titulo "RESTAURANDO '$Restaurar' DO HD"
    if (-not (Test-Path -LiteralPath $indice)) { throw "Indice nao encontrado em $indice" }
    $alvo = Import-Csv $indice | Where-Object { $_.Item -eq $Restaurar } | Select-Object -Last 1
    if (-not $alvo) {
        Escrever "  Nao achei '$Restaurar' no indice. Rode -Listar para ver os nomes."
        Salvar
        exit 1
    }
    Escrever "  No HD ...: $($alvo.Caminho)"
    Escrever "  Volta para: $($alvo.Origem)"
    if (-not $Executar) {
        Escrever ''
        Escrever '  (simulacao - acrescente -Executar para restaurar de verdade)'
        Salvar
        exit 0
    }
    $pai = Split-Path $alvo.Origem -Parent
    if (-not (Test-Path -LiteralPath $pai)) { New-Item -ItemType Directory $pai -Force | Out-Null }
    robocopy $alvo.Caminho $alvo.Origem /E /COPY:DAT /R:1 /W:1 /NFL /NDL /NP | Out-Null
    if ($LASTEXITCODE -ge 8) { throw "robocopy falhou (codigo $LASTEXITCODE)" }
    Escrever '  Restaurado. O material continua no HD - nada foi apagado de la.'
    Salvar
    exit 0
}

# ------------------------------------------------------------- diagnostico
Titulo 'ESPACO EM DISCO'
$unidade = Get-PSDrive -Name ($env:SystemDrive.TrimEnd(':')) -PSProvider FileSystem
$livre = $unidade.Free; $usado = $unidade.Used
Escrever ("  $($env:SystemDrive) livre: {0} de {1}" -f (ComoGB $livre), (ComoGB ($livre + $usado)))
if ($livre -lt 20GB) {
    Escrever '  *** Abaixo de 20 GB: e o limiar de alerta da rotina de manutencao.'
}
if (Test-Path -LiteralPath "$Destino\") {
    $hd = Get-PSDrive -Name ($Destino.TrimEnd(':')) -PSProvider FileSystem
    Escrever ("  $Destino  livre: {0} de {1}" -f (ComoGB $hd.Free), (ComoGB ($hd.Free + $hd.Used)))
} else {
    Escrever "  $Destino  NAO CONECTADO"
}

# ------------------------------------------------------------- candidatos
Titulo "CANDIDATOS A SAIR DESTA MAQUINA (parados ha mais de $DiasParado dias)"
Escrever '  Criterio: material do usuario que nao e usado ha tempo e nao e do'
Escrever '  sistema nem da operacao. Cache e temporario NAO entram aqui - para'
Escrever '  isso existe o 2-limpeza.ps1, que apaga o que o Windows recria.'
Escrever ''

$perfil = $env:USERPROFILE
$raizes = @(
    "$perfil\Downloads"
    "$perfil\Videos"
    "$perfil\Documents"
    "$perfil\Pictures"
    "$perfil\Desktop"
) + $Incluir

$limite     = (Get-Date).AddDays(-$DiasParado)
$candidatos = New-Object System.Collections.ArrayList
$ignorados  = New-Object System.Collections.ArrayList

foreach ($raiz in $raizes) {
    if (-not (Test-Path -LiteralPath $raiz)) { continue }
    foreach ($item in (Get-ChildItem -LiteralPath $raiz -Force -ErrorAction SilentlyContinue)) {
        $motivo = EhProtegido $item.FullName
        if ($motivo) {
            [void]$ignorados.Add([pscustomobject]@{ Caminho = $item.FullName; Motivo = $motivo })
            continue
        }
        if ($item.PSIsContainer) {
            $tamanho = TamanhoReal $item.FullName
            $ultimo  = (Get-ChildItem -LiteralPath $item.FullName -Recurse -File -Force -ErrorAction SilentlyContinue |
                        Measure-Object -Property LastWriteTime -Maximum).Maximum
            if ($null -eq $ultimo) { $ultimo = $item.LastWriteTime }
        } else {
            if (EstaNaNuvem $item) {
                [void]$ignorados.Add([pscustomobject]@{ Caminho = $item.FullName; Motivo = 'so na nuvem, nao ocupa disco' })
                continue
            }
            $tamanho = $item.Length
            $ultimo  = $item.LastWriteTime
        }
        if ($tamanho -lt ($MinimoMB * 1MB)) { continue }
        if ($ultimo -gt $limite) {
            [void]$ignorados.Add([pscustomobject]@{ Caminho = $item.FullName; Motivo = "usado em $($ultimo.ToString('dd/MM/yyyy'))" })
            continue
        }
        [void]$candidatos.Add([pscustomobject]@{
            Nome    = $item.Name
            Caminho = $item.FullName
            Bytes   = $tamanho
            Ultimo  = $ultimo
        })
    }
}

$candidatos = @($candidatos | Sort-Object Bytes -Descending)
if ($candidatos.Count -eq 0) {
    Escrever '  Nenhum candidato pelos criterios atuais.'
    Escrever "  Afrouxe com -MinimoMB 50 -DiasParado 30, ou aponte pastas com -Incluir."
} else {
    foreach ($c in $candidatos) {
        Escrever ("  {0} {1,-44} parado desde {2}" -f (ComoGB $c.Bytes), $c.Nome, $c.Ultimo.ToString('dd/MM/yyyy'))
    }
    Escrever ''
    Escrever ("  TOTAL a liberar: {0}" -f (ComoGB (($candidatos | Measure-Object Bytes -Sum).Sum)))
}

if ($ignorados.Count -gt 0) {
    Titulo 'DEIXADOS ONDE ESTAO (e por que)'
    foreach ($i in ($ignorados | Select-Object -First 25)) {
        Escrever ("  {0,-50} {1}" -f (Split-Path $i.Caminho -Leaf), $i.Motivo)
    }
}

if (-not $Executar) {
    Titulo 'NADA FOI MOVIDO'
    Escrever '  Isto foi so a analise. Confira a lista acima e, se concordar:'
    Escrever ''
    Escrever '    .\5-quarentena-hd.ps1 -Executar            # copia para o HD e confere'
    Escrever '    .\5-quarentena-hd.ps1 -Executar -Remover   # e so entao libera o espaco'
    Salvar
    exit 0
}

# ----------------------------------------------------------------- mover
ExigirHD
if ($candidatos.Count -eq 0) { Escrever ''; Escrever 'Nada a mover.'; Salvar; exit 0 }

$precisa = ($candidatos | Measure-Object Bytes -Sum).Sum
$hd = Get-PSDrive -Name ($Destino.TrimEnd(':')) -PSProvider FileSystem
if ($hd.Free -lt ($precisa * 1.05)) {
    throw ("HD sem espaco: precisa de {0}, tem {1}." -f (ComoGB $precisa), (ComoGB $hd.Free))
}

Titulo "COPIANDO PARA $pastaHoje"
New-Item -ItemType Directory $pastaHoje -Force | Out-Null
$manifesto = New-Object System.Collections.ArrayList
$movidos = 0; $falhas = 0; $liberado = [int64]0

foreach ($c in $candidatos) {
    $alvo = Join-Path $pastaHoje $c.Nome
    Escrever ''
    Escrever ("  {0}  ->  {1}" -f $c.Caminho, $alvo)

    # 1. COPIA (nunca mover direto: mover entre volumes e copiar+apagar sem conferir)
    if (Test-Path -LiteralPath $c.Caminho -PathType Container) {
        robocopy $c.Caminho $alvo /E /COPY:DAT /R:1 /W:1 /NFL /NDL /NP | Out-Null
        $codigo = $LASTEXITCODE
        if ($codigo -ge 8) { Escrever "    ERRO: robocopy codigo $codigo"; $falhas++; continue }
    } else {
        Copy-Item -LiteralPath $c.Caminho -Destination $alvo -Force
    }

    # 2. CONFERE SHA-256, arquivo por arquivo
    Escrever '    conferindo SHA-256...'
    if (Test-Path -LiteralPath $c.Caminho -PathType Container) {
        $origemArquivos = @(Get-ChildItem -LiteralPath $c.Caminho -Recurse -File -Force -ErrorAction SilentlyContinue |
                            Where-Object { -not (EstaNaNuvem $_) })
    } else {
        $origemArquivos = @(Get-Item -LiteralPath $c.Caminho)
    }
    $divergentes = 0
    foreach ($arq in $origemArquivos) {
        $relativo = $arq.FullName.Substring($c.Caminho.Length).TrimStart('\')
        $copia    = if ($relativo) { Join-Path $alvo $relativo } else { $alvo }
        if (-not (Test-Path -LiteralPath $copia)) { $divergentes++; continue }
        $h1 = (Get-FileHash -LiteralPath $arq.FullName -Algorithm SHA256).Hash
        $h2 = (Get-FileHash -LiteralPath $copia       -Algorithm SHA256).Hash
        if ($h1 -ne $h2) { $divergentes++ }
    }

    if ($divergentes -gt 0) {
        Escrever "    *** $divergentes arquivo(s) nao conferem. NADA foi apagado deste item."
        $falhas++
        continue
    }
    Escrever ("    OK: {0} arquivo(s) conferidos" -f $origemArquivos.Count)
    $movidos++

    $registro = [pscustomobject]@{
        Item     = $c.Nome
        Origem   = $c.Caminho
        Caminho  = $alvo
        Tamanho  = (ComoGB $c.Bytes).Trim()
        Bytes    = $c.Bytes
        Arquivos = $origemArquivos.Count
        Data     = (Get-Date -Format 'yyyy-MM-dd HH:mm')
        Removido = $false
    }
    [void]$manifesto.Add($registro)

    # 3. So agora apaga a origem
    if ($Remover) {
        Remove-Item -LiteralPath $c.Caminho -Recurse -Force
        $liberado += $c.Bytes
        $registro.Removido = $true
        Escrever '    origem removida (a copia conferida esta no HD)'
    }
}

# ---------------------------------------------------------------- indice
if ($manifesto.Count -gt 0) {
    $manifesto | Export-Csv -Path (Join-Path $pastaHoje 'MANIFESTO.csv') -NoTypeInformation -Encoding UTF8
    $todos = @()
    if (Test-Path -LiteralPath $indice) { $todos += Import-Csv $indice }
    $todos += $manifesto
    $todos | Export-Csv -Path $indice -NoTypeInformation -Encoding UTF8
}

Titulo 'RESUMO'
Escrever ("  Itens copiados e conferidos : {0}" -f $movidos)
Escrever ("  Itens com problema          : {0}" -f $falhas)
if ($Remover) {
    Escrever ("  Espaco liberado             : {0}" -f (ComoGB $liberado))
} else {
    Escrever '  Nada foi apagado (faltou -Remover). O espaco ainda nao foi liberado.'
}
Escrever ''
Escrever "  Indice do HD: $indice"
Escrever "  Para achar depois : .\5-quarentena-hd.ps1 -Listar"
Escrever "  Para trazer de volta: .\5-quarentena-hd.ps1 -Restaurar `"<nome>`" -Executar"
Salvar
