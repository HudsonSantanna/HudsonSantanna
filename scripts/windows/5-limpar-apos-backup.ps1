#Requires -Version 5.1
<#
    5-limpar-apos-backup.ps1 - Apaga da maquina APENAS os arquivos que ja estao
    provados na copia do backup (mesmo caminho relativo, mesmo tamanho). Com
    -ConferirHash, exige tambem o mesmo SHA-256. Nunca apaga sem par confirmado.

    Trabalha a partir de uma pasta de backup na unidade de rede (ex.: `E:`), a
    mesma usada pelo `4-conferir-backup.ps1`. Para cada subpasta de primeiro
    nivel do backup voce diz onde fica o original na maquina; o script compara
    arquivo por arquivo e so apaga os que batem.

    Por padrao SIMULA (mostra o que seria apagado). Para apagar de verdade:
    -Executar (pede APAGAR para confirmar antes do primeiro delete).

    Uso:
      # 1) ver o que bateria com o backup
      .\5-limpar-apos-backup.ps1 -Backup "E:\Backup-PC-20261104" `
          -Pares @{ 'Documentos' = "$HOME\Documentos"; 'Imagens' = "$HOME\Imagens" }

      # 2) apagar de verdade (pede APAGAR)
      .\5-limpar-apos-backup.ps1 -Backup "E:\Backup-PC-20261104" `
          -Pares @{ 'Documentos' = "$HOME\Documentos" } -Executar

      # 3) extra seguro: conferir SHA-256 antes
      .\5-limpar-apos-backup.ps1 -Backup "E:\Backup-PC-20261104" `
          -Pares @{ 'Documentos' = "$HOME\Documentos" } -Executar -ConferirHash

    O parametro -Pares aceita uma tabela { pasta-no-backup = pasta-na-maquina }.
    Se voce nao passar, o script tenta adivinhar pelos nomes conhecidos (Area de
    Trabalho, Documentos, Imagens, Videos, Musicas, Favoritos, Downloads) usando
    [Environment]::GetFolderPath - que respeita redirecionamento (OneDrive, D:).
#>
[CmdletBinding()]
param(
    [Parameter(Mandatory = $true)][string]$Backup,
    [hashtable]$Pares,
    [switch]$Executar,
    [switch]$ConferirHash,
    [switch]$ApagarPastasVazias,
    [string]$Log
)

$ErrorActionPreference = 'SilentlyContinue'
$script:Linhas  = New-Object System.Collections.ArrayList
$script:Batem   = 0
$script:Bytes   = [int64]0
$script:SemPar  = 0
$script:Diferente = 0
$script:Travado = 0

$desk = [Environment]::GetFolderPath('Desktop')
if (-not $desk -or -not (Test-Path -LiteralPath $desk)) { $desk = $env:USERPROFILE }
if (-not $Log) {
    $Log = Join-Path $desk ("limpar-apos-backup-{0}.txt" -f (Get-Date -Format 'yyyyMMdd-HHmm'))
}

function Escrever([string]$Texto = '', [string]$Cor) {
    if ($Cor) { Write-Host $Texto -ForegroundColor $Cor } else { Write-Host $Texto }
    [void]$script:Linhas.Add($Texto)
}
function Titulo([string]$Texto) {
    Escrever ''
    Escrever ('=' * 72)
    Escrever "  $Texto"
    Escrever ('=' * 72)
}
function ComoGB($Bytes) { '{0,8:N2} GB' -f ($Bytes / 1GB) }
function GravarLog { $script:Linhas | Out-File -FilePath $Log -Encoding UTF8 }

# -------------------------------------------------- 1. valida backup
if (-not (Test-Path -LiteralPath $Backup)) {
    Escrever "Pasta de backup nao encontrada: $Backup" 'Red'
    Escrever 'Ligue o HD / confira a letra da unidade (ex.: net use E: \\servidor\compartilhamento).'
    GravarLog; exit 1
}
$Backup = (Get-Item -LiteralPath $Backup -Force).FullName.TrimEnd('\')

Escrever "Limpar apos backup - $(Get-Date -Format 'dd/MM/yyyy HH:mm')"
Escrever "Backup: $Backup"
Escrever "Log...: $Log"
Escrever ''
if (-not $Executar) {
    Escrever '>>> MODO SIMULACAO: nada sera apagado. Rode com -Executar para valer. <<<' 'Yellow'
}
if ($ConferirHash) {
    Escrever 'Vou conferir SHA-256 antes de apagar cada arquivo (demora mais).'
}

# -------------------------------------------------- 2. monta pares backup -> origem
$conhecidas = [ordered]@{
    'Area de Trabalho' = [Environment]::GetFolderPath('Desktop')
    'Documentos'       = [Environment]::GetFolderPath('MyDocuments')
    'Imagens'          = [Environment]::GetFolderPath('MyPictures')
    'Videos'           = [Environment]::GetFolderPath('MyVideos')
    'Musicas'          = [Environment]::GetFolderPath('MyMusic')
    'Favoritos'        = [Environment]::GetFolderPath('Favorites')
    'Downloads'        = Join-Path $env:USERPROFILE 'Downloads'
    'Contatos'         = Join-Path $env:USERPROFILE 'Contacts'
    'Links'            = Join-Path $env:USERPROFILE 'Links'
    'Jogos salvos'     = Join-Path $env:USERPROFILE 'Saved Games'
}

$itens = New-Object System.Collections.ArrayList
$subBackup = Get-ChildItem -LiteralPath $Backup -Directory -Force

if (-not $Pares -or $Pares.Count -eq 0) {
    foreach ($sub in $subBackup) {
        $nome = $sub.Name
        if ($conhecidas.Contains($nome)) {
            $origem = $conhecidas[$nome]
        } else {
            # Pasta sem par conhecido: pula (seguranca). Usuario pode indicar com -Pares.
            Escrever "  Pular '$nome' (sem par conhecido; use -Pares para indicar a origem)." 'Yellow'
            continue
        }
        if (-not (Test-Path -LiteralPath $origem)) {
            Escrever "  Pular '$nome' (origem $origem nao existe)." 'Yellow'
            continue
        }
        [void]$itens.Add([pscustomobject]@{
            Rotulo = $nome
            PastaBackup = $sub.FullName
            Origem = (Get-Item -LiteralPath $origem -Force).FullName.TrimEnd('\')
        })
    }
} else {
    foreach ($nome in $Pares.Keys) {
        $pastaBackup = Join-Path $Backup $nome
        if (-not (Test-Path -LiteralPath $pastaBackup)) {
            Escrever "  Nao existe '$nome' em $Backup. Pulando." 'Yellow'
            continue
        }
        $origem = [string]$Pares[$nome]
        if (-not (Test-Path -LiteralPath $origem)) {
            Escrever "  Origem nao existe: $origem. Pulando '$nome'." 'Yellow'
            continue
        }
        [void]$itens.Add([pscustomobject]@{
            Rotulo = $nome
            PastaBackup = (Get-Item -LiteralPath $pastaBackup -Force).FullName.TrimEnd('\')
            Origem = (Get-Item -LiteralPath $origem -Force).FullName.TrimEnd('\')
        })
    }
}

if ($itens.Count -eq 0) {
    Escrever ''
    Escrever 'Nenhum par para processar. Passe -Pares @{ "pasta-no-backup" = "pasta-na-maquina" }.' 'Yellow'
    GravarLog; exit 0
}

# Checagem obvia: alguem apontou a origem para dentro do proprio destino?
foreach ($it in $itens) {
    $o = $it.Origem + '\'
    $b = $it.PastaBackup + '\'
    if ($o.StartsWith($b, [StringComparison]::OrdinalIgnoreCase) -or
        $b.StartsWith($o, [StringComparison]::OrdinalIgnoreCase)) {
        Escrever ''
        Escrever "Par invalido: origem e backup se sobrepoem para '$($it.Rotulo)'." 'Red'
        Escrever "  Origem: $($it.Origem)"
        Escrever "  Backup: $($it.PastaBackup)"
        GravarLog; exit 1
    }
}

# -------------------------------------------------- 3. primeiro passo: planejar
$plano = @{}   # rotulo -> lista de FileInfo a apagar
foreach ($it in $itens) {
    Titulo $it.Rotulo
    Escrever "Backup: $($it.PastaBackup)"
    Escrever "Origem: $($it.Origem)"

    $raizOrigem = $it.Origem
    $raizBackup = $it.PastaBackup
    $paraApagar = New-Object System.Collections.ArrayList
    $totalOrigem = 0; $semParCat = 0; $diferenteCat = 0; $travadoCat = 0; $bytesCat = [int64]0

    foreach ($arq in (Get-ChildItem -LiteralPath $raizOrigem -Recurse -File -Force |
                      Where-Object { -not ($_.Attributes -band [IO.FileAttributes]::ReparsePoint) })) {
        $totalOrigem++
        $rel = $arq.FullName.Substring($raizOrigem.Length + 1)
        $copia = Join-Path $raizBackup $rel

        if (-not (Test-Path -LiteralPath $copia)) {
            $semParCat++
            continue
        }

        $infoCopia = Get-Item -LiteralPath $copia -Force
        if ($infoCopia.Length -ne $arq.Length) {
            $diferenteCat++
            continue
        }

        if ($ConferirHash) {
            try {
                $hOrig  = (Get-FileHash -LiteralPath $arq.FullName -Algorithm SHA256 -ErrorAction Stop).Hash
                $hCopia = (Get-FileHash -LiteralPath $copia       -Algorithm SHA256 -ErrorAction Stop).Hash
            } catch {
                # arquivo travado (em uso) ou sem permissao
                $travadoCat++
                continue
            }
            if ($hOrig -ne $hCopia) {
                $diferenteCat++
                continue
            }
        }

        [void]$paraApagar.Add($arq)
        $bytesCat += $arq.Length
    }

    $plano[$it.Rotulo] = $paraApagar
    $script:Batem     += $paraApagar.Count
    $script:Bytes     += $bytesCat
    $script:SemPar    += $semParCat
    $script:Diferente += $diferenteCat
    $script:Travado   += $travadoCat

    $cor = if ($semParCat -gt 0 -or $diferenteCat -gt 0 -or $travadoCat -gt 0) { 'Yellow' } else { 'Green' }
    Escrever ('  Origem.............: {0} arquivos' -f $totalOrigem)
    Escrever ('  Batem com a copia .: {0,5} ({1})' -f $paraApagar.Count, (ComoGB $bytesCat)) $cor
    if ($semParCat   -gt 0) { Escrever ('  Sem copia .........: {0,5}  (NAO vou apagar)' -f $semParCat) 'Yellow' }
    if ($diferenteCat -gt 0) { Escrever ('  Copia diferente ...: {0,5}  (NAO vou apagar)' -f $diferenteCat) 'Yellow' }
    if ($travadoCat  -gt 0) { Escrever ('  Em uso / sem acesso: {0,5}  (NAO vou apagar)' -f $travadoCat) 'Yellow' }
}

# -------------------------------------------------- 4. resumo + confirmacao
Titulo 'RESUMO'
Escrever ('Arquivos que batem com a copia .: {0}' -f $script:Batem)
Escrever ('Espaco que seria liberado ......: {0}' -f (ComoGB $script:Bytes))
Escrever ('Sem copia no backup ............: {0}' -f $script:SemPar)
Escrever ('Copia com tamanho/hash diferente: {0}' -f $script:Diferente)
Escrever ('Travados (arquivo em uso) ......: {0}' -f $script:Travado)

if ($script:Batem -eq 0) {
    Escrever ''
    Escrever 'Nada para apagar: nenhum par confirmado.' 'Yellow'
    GravarLog; exit 0
}

if (-not $Executar) {
    Escrever ''
    Escrever 'Simulacao. Rode de novo com -Executar para apagar de verdade.' 'Yellow'
    GravarLog; exit 0
}

Escrever ''
Escrever ('ATENCAO: {0} arquivos serao APAGADOS da origem ({1}).' -f $script:Batem, (ComoGB $script:Bytes)) 'Yellow'
Escrever 'Uma copia conferida de cada um fica no backup.' 'Yellow'
$resp = Read-Host 'Digite APAGAR para confirmar (qualquer outra coisa cancela)'
if ($resp -ne 'APAGAR') {
    Escrever 'Cancelado.' 'Red'
    GravarLog; exit 1
}

# -------------------------------------------------- 5. apaga
Titulo 'APAGANDO'
$feitos = 0; $liberado = [int64]0; $falhas = 0
foreach ($rotulo in $plano.Keys) {
    foreach ($arq in $plano[$rotulo]) {
        try {
            $tam = $arq.Length
            Remove-Item -LiteralPath $arq.FullName -Force -ErrorAction Stop
            $feitos++; $liberado += $tam
        } catch {
            $falhas++
            Escrever "  falhou: $($arq.FullName) - $($_.Exception.Message)" 'Yellow'
        }
    }
    Escrever ('  {0,-28} apagados: {1}' -f $rotulo, $plano[$rotulo].Count)
}

# pastas vazias (opcional)
if ($ApagarPastasVazias) {
    Escrever ''
    Escrever 'Removendo pastas vazias que sobraram...'
    foreach ($it in $itens) {
        Get-ChildItem -LiteralPath $it.Origem -Recurse -Directory -Force |
            Sort-Object { $_.FullName.Length } -Descending | ForEach-Object {
                if (-not (Get-ChildItem -LiteralPath $_.FullName -Force)) {
                    Remove-Item -LiteralPath $_.FullName -Force -ErrorAction SilentlyContinue
                }
            }
    }
}

Titulo 'FIM'
Escrever ('Arquivos apagados .: {0}' -f $feitos) 'Green'
Escrever ('Espaco liberado ...: {0}' -f (ComoGB $liberado)) 'Green'
if ($falhas -gt 0) {
    Escrever ('Falhas (ignoradas): {0}  (veja o log)' -f $falhas) 'Yellow'
}
Escrever ''
Escrever "Log: $Log"
GravarLog
