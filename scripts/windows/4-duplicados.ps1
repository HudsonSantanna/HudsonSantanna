#Requires -Version 5.1
<#
    4-duplicados.ps1 - Encontra arquivos duplicados (mesmo conteudo, conferido
    por SHA-256) e, se voce mandar, tira as copias extras do caminho.

    De cada grupo de duplicados fica UMA copia: a de caminho mais curto (em
    empate, a mais antiga). Pastas de sistema, programas e AppData sao ignoradas
    por padrao, porque duplicados ali sao normais e apagar quebra programas.

    Por padrao so gera o relatorio. Para agir:
      -Quarentena <pasta>  move as copias extras para la (recomendado)
      -Apagar              apaga as copias extras (pede confirmacao)

    Uso:
      # 1) so relatorio
      .\4-duplicados.ps1 -Pasta "C:\Users\hudso"

      # 2) mover duplicados para uma pasta de quarentena
      .\4-duplicados.ps1 -Pasta "E:\Backup-PC-20261015" -Quarentena "E:\Duplicados"

      # 3) apagar de vez (depois de conferir o relatorio)
      .\4-duplicados.ps1 -Pasta "E:\Backup-PC-20261015" -Apagar
#>
[CmdletBinding()]
param(
    [Parameter(Mandatory = $true)][string[]]$Pasta,
    [int]     $MinimoKB   = 100,
    [string]  $Quarentena,
    [switch]  $Apagar,
    [string[]]$Ignorar    = @('\Windows\', '\Program Files\', '\Program Files (x86)\',
                              '\ProgramData\', '\AppData\', '\$Recycle.Bin\',
                              '\System Volume Information\', '\node_modules\', '\.git\'),
    [string]  $Saida      = "$env:USERPROFILE\Desktop\duplicados-$(Get-Date -Format 'yyyyMMdd-HHmm')"
)

$ErrorActionPreference = 'Stop'

function ComoGB($Bytes) { '{0,8:N2} GB' -f ($Bytes / 1GB) }
function Ignorado([string]$Caminho) {
    foreach ($trecho in $Ignorar) {
        if ($Caminho.IndexOf($trecho, [StringComparison]::OrdinalIgnoreCase) -ge 0) { return $true }
    }
    if ($Quarentena -and $Caminho.StartsWith($Quarentena, [StringComparison]::OrdinalIgnoreCase)) { return $true }
    return $false
}

if ($Quarentena -and $Apagar) { throw 'Use -Quarentena OU -Apagar, nao os dois.' }
foreach ($p in $Pasta) {
    if (-not (Test-Path -LiteralPath $p)) { throw "Pasta nao encontrada: $p" }
}
if ($Quarentena) { $Quarentena = [IO.Path]::GetFullPath($Quarentena).TrimEnd('\') + '\' }

# ------------------------------------------------------------- 1. varredura
Write-Host ''
Write-Host "Varrendo $($Pasta -join ', ') (arquivos a partir de $MinimoKB KB)..."
$minimo = [int64]$MinimoKB * 1KB
$arquivos = foreach ($p in $Pasta) {
    Get-ChildItem -LiteralPath $p -Recurse -File -Force -ErrorAction SilentlyContinue |
        Where-Object {
            $_.Length -ge $minimo -and
            -not ($_.Attributes -band [IO.FileAttributes]::ReparsePoint) -and
            -not (Ignorado $_.FullName)
        }
}
Write-Host ("{0} arquivos analisados." -f @($arquivos).Count)

# So calcula hash de quem tem tamanho repetido: e o que deixa a busca rapida.
$candidatos = @($arquivos | Group-Object Length | Where-Object Count -gt 1 |
                ForEach-Object { $_.Group })
Write-Host ("{0} arquivos com tamanho repetido; calculando SHA-256..." -f $candidatos.Count)

$i = 0
$comHash = foreach ($a in $candidatos) {
    $i++
    if ($i % 50 -eq 0) {
        Write-Progress -Activity 'Calculando hash' -Status "$i de $($candidatos.Count)" `
                       -PercentComplete ($i * 100 / $candidatos.Count)
    }
    try {
        $h = (Get-FileHash -LiteralPath $a.FullName -Algorithm SHA256).Hash
        [pscustomobject]@{ Hash = $h; Arquivo = $a }
    } catch {
        Write-Warning "Nao foi possivel ler (em uso?): $($a.FullName)"
    }
}
Write-Progress -Activity 'Calculando hash' -Completed

# ------------------------------------------------------------- 2. grupos
$grupos = @($comHash | Group-Object Hash | Where-Object Count -gt 1)
$linhas = New-Object System.Collections.ArrayList
$extras = New-Object System.Collections.ArrayList
$desperdicio = [int64]0
$n = 0

foreach ($g in $grupos) {
    $n++
    $ordenados = @($g.Group | ForEach-Object { $_.Arquivo } |
                   Sort-Object @{ e = { $_.FullName.Length } }, LastWriteTime)
    $manter = $ordenados[0]
    [void]$linhas.Add([pscustomobject]@{
        Grupo = $n; Acao = 'MANTER'; TamanhoMB = [math]::Round($manter.Length / 1MB, 2)
        Modificado = $manter.LastWriteTime; Caminho = $manter.FullName; Hash = $g.Name })
    foreach ($d in $ordenados[1..($ordenados.Count - 1)]) {
        [void]$extras.Add($d)
        $desperdicio += $d.Length
        [void]$linhas.Add([pscustomobject]@{
            Grupo = $n; Acao = 'DUPLICADO'; TamanhoMB = [math]::Round($d.Length / 1MB, 2)
            Modificado = $d.LastWriteTime; Caminho = $d.FullName; Hash = $g.Name })
    }
}

$csv = "$Saida.csv"
$linhas | Export-Csv -LiteralPath $csv -NoTypeInformation -Encoding UTF8 -Delimiter ';'

Write-Host ''
Write-Host ('=' * 60)
Write-Host ("Grupos de duplicados ....: {0}" -f $grupos.Count)
Write-Host ("Copias extras ...........: {0}" -f $extras.Count)
Write-Host ("Espaco ocupado por elas .: {0}" -f (ComoGB $desperdicio))
Write-Host "Relatorio (abre no Excel): $csv"
Write-Host ('=' * 60)

if ($extras.Count -eq 0) { Write-Host 'Nenhum duplicado encontrado.'; exit 0 }

if (-not $Quarentena -and -not $Apagar) {
    Write-Host ''
    Write-Host 'Nada foi alterado. Confira o relatorio (coluna Acao) e depois rode com'
    Write-Host '  -Quarentena "E:\Duplicados"   para mover as copias extras, ou'
    Write-Host '  -Apagar                       para apagar de vez.'
    exit 0
}

# ------------------------------------------------------------- 3. acao
Write-Host ''
if ($Apagar) {
    Write-Host ("ATENCAO: {0} arquivos serao APAGADOS (uma copia de cada fica)." -f $extras.Count) -ForegroundColor Yellow
    $palavra = 'APAGAR'
} else {
    Write-Host ("{0} arquivos serao MOVIDOS para {1}" -f $extras.Count, $Quarentena) -ForegroundColor Yellow
    $palavra = 'MOVER'
}
$resp = Read-Host "Digite $palavra para confirmar (qualquer outra coisa cancela)"
if ($resp -ne $palavra) { Write-Host 'Cancelado.'; exit 1 }

$feitos = 0; $liberado = [int64]0
foreach ($d in $extras) {
    try {
        if ($Apagar) {
            Remove-Item -LiteralPath $d.FullName -Force
        } else {
            # Recria a estrutura original dentro da quarentena: C:\a\b.txt -> <Q>\C\a\b.txt
            $relativo = $d.FullName -replace '^\\\\', 'REDE\' -replace ':', ''
            $alvo = Join-Path $Quarentena $relativo
            New-Item -ItemType Directory -Path (Split-Path $alvo) -Force | Out-Null
            Move-Item -LiteralPath $d.FullName -Destination $alvo -Force
        }
        $feitos++; $liberado += $d.Length
    } catch {
        Write-Warning "Falhou: $($d.FullName) - $($_.Exception.Message)"
    }
}

Write-Host ''
Write-Host ("{0} de {1} arquivos tratados, {2} liberados." -f $feitos, $extras.Count, (ComoGB $liberado)) -ForegroundColor Green
if ($Quarentena) {
    Write-Host "Confira $Quarentena; quando tiver certeza, apague essa pasta para liberar o espaco."
}
