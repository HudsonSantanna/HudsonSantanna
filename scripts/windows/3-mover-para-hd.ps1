#Requires -Version 5.1
<#
    3-mover-para-hd.ps1 - Copia uma pasta para o HD externo, CONFERE se a copia
    ficou integra e so entao (com -Remover) apaga a origem.

    A ordem importa: copia -> verifica -> apaga. Nunca move direto.

    Uso:
      # 1) copiar e conferir (nao apaga nada)
      .\3-mover-para-hd.ps1 -Origem "C:\Users\hudso\Videos\Antigos" -Destino "E:\Arquivo"

      # 2) depois de conferir o relatorio, liberar o espaco
      .\3-mover-para-hd.ps1 -Origem "C:\Users\hudso\Videos\Antigos" -Destino "E:\Arquivo" -Remover
#>
[CmdletBinding()]
param(
    [Parameter(Mandatory = $true)][string]$Origem,
    [Parameter(Mandatory = $true)][string]$Destino,
    [switch]$Remover,
    [string]$Log = "$env:USERPROFILE\Desktop\movimentacao-$(Get-Date -Format 'yyyyMMdd-HHmm').txt"
)

$ErrorActionPreference = 'Stop'

function ComoGB($Bytes) { '{0,8:N2} GB' -f ($Bytes / 1GB) }
# Tamanho e quantidade de arquivos numa passada so, direto pelo .NET (bem mais
# rapido que Get-ChildItem -Recurse). Nao entra em junctions/links simbolicos.
# Pastas sem permissao sao contadas em PastasNegadas: se houver alguma, a
# conferencia nao e confiavel e a origem nao sera apagada.
function Medir([string]$Caminho) {
    $raiz = New-Object System.IO.DirectoryInfo $Caminho
    $reparse  = [System.IO.FileAttributes]::ReparsePoint
    $bytes    = [int64]0
    $arquivos = [int64]0
    $negadas  = 0
    $pilha    = New-Object System.Collections.Stack
    if ($raiz.Exists) { $pilha.Push($raiz) }
    while ($pilha.Count -gt 0) {
        $dir = $pilha.Pop()
        try { $entradas = $dir.GetFileSystemInfos() } catch { $negadas++; continue }
        foreach ($e in $entradas) {
            if ($e -is [System.IO.DirectoryInfo]) {
                if (($e.Attributes -band $reparse) -eq 0) { $pilha.Push($e) }
            } else {
                $bytes += $e.Length
                $arquivos++
            }
        }
    }
    [pscustomobject]@{ Bytes = $bytes; Arquivos = $arquivos; PastasNegadas = $negadas }
}

if (-not (Test-Path -LiteralPath $Origem)) { throw "Origem nao encontrada: $Origem" }

$raizDestino = Split-Path -Qualifier $Destino
if (-not (Test-Path -LiteralPath $raizDestino)) {
    throw "Unidade de destino $raizDestino nao esta conectada. Ligue o HD externo."
}

$nomePasta   = Split-Path $Origem -Leaf
$destinoFinal = Join-Path $Destino $nomePasta

$medOrigem = Medir $Origem
$tamOrigem = $medOrigem.Bytes
$qtdOrigem = $medOrigem.Arquivos
$livreDestino = (New-Object IO.DriveInfo $raizDestino).AvailableFreeSpace

Write-Host ''
Write-Host "Origem ........: $Origem"
Write-Host "Destino .......: $destinoFinal"
Write-Host ("Tamanho .......: {0} em {1} arquivos" -f (ComoGB $tamOrigem), $qtdOrigem)
Write-Host ("Livre no destino: {0}" -f (ComoGB $livreDestino))

if ($tamOrigem -gt $livreDestino) {
    throw "Espaco insuficiente no destino. Precisa de $(ComoGB $tamOrigem), ha $(ComoGB $livreDestino)."
}

if ($Remover) {
    Write-Host ''
    Write-Host 'ATENCAO: apos copiar e conferir, a pasta de origem sera APAGADA.' -ForegroundColor Yellow
    $resp = Read-Host "Digite APAGAR para confirmar (qualquer outra coisa cancela)"
    if ($resp -ne 'APAGAR') { Write-Host 'Cancelado.'; exit 1 }
}

# ------------------------------------------------------------------ copia
Write-Host ''
Write-Host 'Copiando com robocopy...'
& robocopy $Origem $destinoFinal /E /COPY:DAT /DCOPY:DAT /R:2 /W:2 /NP /TEE /LOG+:"$Log"
$codigo = $LASTEXITCODE

# robocopy: 0-7 = sucesso (com ou sem copias); 8 ou mais = falha real
if ($codigo -ge 8) {
    throw "Robocopy falhou com codigo $codigo. Veja o log: $Log"
}
Write-Host "Copia concluida (codigo robocopy $codigo)."

# -------------------------------------------------------------- conferencia
Write-Host ''
Write-Host 'Conferindo a copia (tamanho e contagem de arquivos)...'
$medDestino = Medir $destinoFinal
$tamDestino = $medDestino.Bytes
$qtdDestino = $medDestino.Arquivos

Write-Host ("Origem : {0} em {1} arquivos" -f (ComoGB $tamOrigem), $qtdOrigem)
Write-Host ("Destino: {0} em {1} arquivos" -f (ComoGB $tamDestino), $qtdDestino)

if ($medOrigem.PastasNegadas -gt 0 -or $medDestino.PastasNegadas -gt 0) {
    Write-Host ("Pastas sem permissao de leitura: origem {0}, destino {1}." -f `
        $medOrigem.PastasNegadas, $medDestino.PastasNegadas) -ForegroundColor Yellow
}
$integra = ($tamDestino -eq $tamOrigem -and $qtdDestino -eq $qtdOrigem -and
            $medOrigem.PastasNegadas -eq 0 -and $medDestino.PastasNegadas -eq 0)
if (-not $integra) {
    Write-Host ''
    Write-Host 'A copia NAO confere com a origem. Nada sera apagado.' -ForegroundColor Red
    Write-Host "Log: $Log"
    exit 1
}
Write-Host 'Copia integra.' -ForegroundColor Green

# ------------------------------------------------------------------ remocao
if ($Remover) {
    Write-Host ''
    Write-Host 'Apagando a origem...'
    Remove-Item -LiteralPath $Origem -Recurse -Force
    Write-Host ("Liberado no disco interno: {0}" -f (ComoGB $tamOrigem)) -ForegroundColor Green
    "Origem removida em $(Get-Date -Format 'dd/MM/yyyy HH:mm'): $Origem" |
        Out-File -FilePath $Log -Append -Encoding UTF8
} else {
    Write-Host ''
    Write-Host 'Origem preservada. Confira os arquivos no HD externo e, quando tiver certeza,'
    Write-Host 'rode o mesmo comando acrescentando  -Remover  para liberar o espaco.'
}

Write-Host ''
Write-Host "Log: $Log"
