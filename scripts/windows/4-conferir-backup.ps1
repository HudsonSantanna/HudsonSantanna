#Requires -Version 5.1
<#
    4-conferir-backup.ps1 - Confere o que esta na unidade de backup (por padrao E:)
    sem mexer em nada. Mostra espaco livre, pastas de primeiro nivel com tamanho e
    data da ultima alteracao, e sinaliza pastas que nao sao atualizadas ha muito
    tempo (potenciais backups parados).

    Uso:
      # relatorio basico na unidade E:
      powershell -ExecutionPolicy Bypass -File .\4-conferir-backup.ps1

      # outra unidade e profundidade maior
      .\4-conferir-backup.ps1 -Unidade F: -Profundidade 2

      # comparar com uma pasta de origem (tamanho e contagem de arquivos)
      .\4-conferir-backup.ps1 -Origem "C:\Users\hudso\Documentos" -Destino "E:\Backup\Documentos"
#>
[CmdletBinding()]
param(
    [string]$Unidade = 'E:',
    [int]$Profundidade = 1,
    [int]$DiasParado = 30,
    [string]$Origem,
    [string]$Destino,
    [string]$Log = (Join-Path ([Environment]::GetFolderPath('Desktop')) "conferir-backup-$(Get-Date -Format 'yyyyMMdd-HHmm').txt")
)

$ErrorActionPreference = 'SilentlyContinue'
$script:Linhas = New-Object System.Collections.ArrayList

function Escrever([string]$Texto = '') {
    Write-Host $Texto
    [void]$script:Linhas.Add($Texto)
}
function ComoGB($Bytes) { '{0,10:N2} GB' -f ($Bytes / 1GB) }
function ComoMB($Bytes) { '{0,10:N2} MB' -f ($Bytes / 1MB) }
function TamanhoPasta([string]$Caminho) {
    $s = (Get-ChildItem -LiteralPath $Caminho -Recurse -File -Force |
            Measure-Object -Property Length -Sum).Sum
    if ($null -eq $s) { [int64]0 } else { [int64]$s }
}
function ContarArquivos([string]$Caminho) {
    @(Get-ChildItem -LiteralPath $Caminho -Recurse -File -Force).Count
}

Escrever "Conferencia de backup - $(Get-Date -Format 'dd/MM/yyyy HH:mm')"
Escrever ''

# ------------------------------------------------------------- unidade
$letra = $Unidade.TrimEnd(':','\')
$raiz  = "${letra}:\"
if (-not (Test-Path -LiteralPath $raiz)) {
    Escrever "Unidade $raiz nao esta conectada. Ligue o HD / verifique a letra."
    $script:Linhas | Out-File -FilePath $Log -Encoding UTF8
    exit 1
}

$vol = Get-Volume -DriveLetter $letra -ErrorAction SilentlyContinue
if ($vol) {
    $total = $vol.Size
    $livre = $vol.SizeRemaining
    $usado = $total - $livre
    $pctUsado = if ($total -gt 0) { [math]::Round(($usado / $total) * 100, 1) } else { 0 }
    Escrever ("Unidade {0}  ({1})" -f $raiz, ($vol.FileSystemLabel))
    Escrever ("  Tamanho total : {0}" -f (ComoGB $total))
    Escrever ("  Usado ........: {0}  ({1}%)" -f (ComoGB $usado), $pctUsado)
    Escrever ("  Livre ........: {0}" -f (ComoGB $livre))
    Escrever ("  Sistema ......: {0}" -f $vol.FileSystem)
    if ($livre -lt 10GB) {
        Escrever '  !! Menos de 10 GB livres. Avalie antes do proximo backup.'
    }
} else {
    Escrever "Unidade $raiz encontrada mas sem info de volume."
}
Escrever ''

# ---------------------------------------------------- pastas de topo
Escrever "-- Pastas em $raiz (profundidade $Profundidade) --"
$agora = Get-Date
$itens = Get-ChildItem -LiteralPath $raiz -Directory -Force |
    Where-Object { $_.Name -notin '$RECYCLE.BIN','System Volume Information','Recovery' }

if (-not $itens) {
    Escrever '  (nenhuma pasta encontrada no primeiro nivel)'
} else {
    $linhas = foreach ($pasta in $itens) {
        $tam = TamanhoPasta $pasta.FullName
        $qtd = ContarArquivos $pasta.FullName
        $ult = (Get-ChildItem -LiteralPath $pasta.FullName -Recurse -File -Force |
                Sort-Object LastWriteTime -Descending |
                Select-Object -First 1).LastWriteTime
        [pscustomobject]@{
            Nome      = $pasta.Name
            TamanhoB  = $tam
            Tamanho   = ComoGB $tam
            Arquivos  = $qtd
            Ultima    = if ($ult) { $ult.ToString('dd/MM/yyyy HH:mm') } else { '-' }
            Dias      = if ($ult) { [int]($agora - $ult).TotalDays } else { -1 }
        }
    }
    $linhas = $linhas | Sort-Object TamanhoB -Descending
    Escrever ('  {0,-32}  {1,12}  {2,10}  {3,-16}  {4}' -f 'Pasta','Tamanho','Arquivos','Ultima alteracao','Parado')
    Escrever ('  {0}' -f ('-' * 85))
    foreach ($l in $linhas) {
        $marca = ''
        if ($l.Dias -ge 0 -and $l.Dias -gt $DiasParado) { $marca = "!! ha $($l.Dias) dias sem alteracao" }
        Escrever ('  {0,-32}  {1}  {2,10:N0}  {3,-16}  {4}' -f $l.Nome, $l.Tamanho, $l.Arquivos, $l.Ultima, $marca)
    }
}
Escrever ''

# ------------------------------------------- profundidade adicional
if ($Profundidade -ge 2) {
    Escrever "-- Subpastas (nivel 2) --"
    foreach ($pasta in $itens) {
        $subs = Get-ChildItem -LiteralPath $pasta.FullName -Directory -Force
        if (-not $subs) { continue }
        Escrever ("  [{0}]" -f $pasta.Name)
        foreach ($s in ($subs | Sort-Object Name)) {
            $tam = TamanhoPasta $s.FullName
            $ult = (Get-ChildItem -LiteralPath $s.FullName -Recurse -File -Force |
                    Sort-Object LastWriteTime -Descending |
                    Select-Object -First 1).LastWriteTime
            $quando = if ($ult) { $ult.ToString('dd/MM/yyyy') } else { '-' }
            Escrever ('    {0,-40}  {1}   ultima: {2}' -f $s.Name, (ComoGB $tam), $quando)
        }
    }
    Escrever ''
}

# ---------------------------------- comparacao opcional origem/destino
if ($Origem -and $Destino) {
    Escrever '-- Comparacao origem x destino --'
    if (-not (Test-Path -LiteralPath $Origem))  { Escrever "Origem nao encontrada: $Origem";  $script:Linhas | Out-File $Log -Encoding UTF8; exit 1 }
    if (-not (Test-Path -LiteralPath $Destino)) { Escrever "Destino nao encontrado: $Destino"; $script:Linhas | Out-File $Log -Encoding UTF8; exit 1 }

    $tamO = TamanhoPasta $Origem;  $qtdO = ContarArquivos $Origem
    $tamD = TamanhoPasta $Destino; $qtdD = ContarArquivos $Destino

    Escrever ("  Origem .: {0} em {1,8:N0} arquivos   {2}" -f (ComoGB $tamO), $qtdO, $Origem)
    Escrever ("  Destino : {0} em {1,8:N0} arquivos   {2}" -f (ComoGB $tamD), $qtdD, $Destino)

    $difTam = $tamD - $tamO
    $difQtd = $qtdD - $qtdO
    if ($difTam -eq 0 -and $difQtd -eq 0) {
        Escrever '  OK: tamanho e contagem conferem.'
    } else {
        Escrever ("  !! Diferenca: {0} e {1:N0} arquivo(s)." -f (ComoMB $difTam), $difQtd)
        Escrever '     Rode:  robocopy "<origem>" "<destino>" /E /L   para ver o que falta.'
    }
    Escrever ''
}

Escrever ('=' * 60)
Escrever 'Pronto. Nada foi alterado na unidade.'
$script:Linhas | Out-File -FilePath $Log -Encoding UTF8
Write-Host ''
Write-Host "Log salvo em: $Log" -ForegroundColor Green
