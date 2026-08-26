#Requires -Version 5.1
<#
    7-nomear-impressoras.ps1 - Da nome proprio as duas BIXOLON.

    Nesta maquina as duas se chamam 'BIXOLON XD3-40t - BPL' e
    'BIXOLON XD3-40t - BPL-Z #2'. Os nomes so diferem por um sufixo de driver,
    entao na hora do Ctrl+P todo mundo escolhe pelo palpite - e as etiquetas
    saem trocadas. Depois deste script elas se chamam 'Codigo de Barra' e
    'Etiqueta Fiscal', e nao ha mais o que confundir.

    IDENTIFICAR ANTES DE RENOMEAR. As duas BIXOLON nao tem numero de serie: o
    Windows so as distingue pela porta USB, e porta USB troca de lugar. Nomear
    pelo palpite grava o erro em vez de corrigi-lo - por isso o passo -Identificar
    manda um papel por cada fila com o nome dela impresso. Voce olha qual
    impressora cuspiu qual papel, e SO ENTAO renomeia.

    Uso:
      # 1. descobrir quem e quem (so imprime papel, nao altera nada)
      powershell -ExecutionPolicy Bypass -File .\7-nomear-impressoras.ps1 -Identificar

      # 2. renomear, com o que o papel provou
      powershell -ExecutionPolicy Bypass -File .\7-nomear-impressoras.ps1 `
          -DeCodigoDeBarra 'BIXOLON XD3-40t - BPL-Z #2' `
          -DeEtiquetaFiscal 'BIXOLON XD3-40t - BPL' -Confirmar
#>
[CmdletBinding()]
param(
    [switch]$Identificar,
    [string]$DeCodigoDeBarra,
    [string]$DeEtiquetaFiscal,
    [string]$NomeCodigoDeBarra = 'Codigo de Barra',
    [string]$NomeEtiquetaFiscal = 'Etiqueta Fiscal',
    [switch]$Confirmar
)

$ErrorActionPreference = 'Stop'

function Titulo([string]$T) {
    Write-Host ''
    Write-Host ('=' * 72)
    Write-Host "  $T"
    Write-Host ('=' * 72)
}
function OK([string]$T)    { Write-Host "  [OK]    $T" }
function Erro([string]$T)  { Write-Host "  [ERRO]  $T" }
function Aviso([string]$T) { Write-Host "  [!]     $T" }

Write-Host ''
Write-Host "ARGOS - nomes das impressoras  $(Get-Date -Format 'dd/MM/yyyy HH:mm')"

foreach ($c in @('Get-Printer', 'Rename-Printer')) {
    if (-not (Get-Command $c -ErrorAction SilentlyContinue)) {
        Erro "$c indisponivel - este script depende do modulo PrintManagement"
        exit 1
    }
}

# --------------------------------------------------------------- as candidatas
Titulo 'IMPRESSORAS BIXOLON'
$todas = @(Get-Printer | Sort-Object Name)
$bix   = @($todas | Where-Object { $_.Name -match 'BIXOLON' -or $_.DriverName -match 'BIXOLON|BPL' })
if ($bix.Count -eq 0) {
    Erro 'nenhuma BIXOLON instalada nesta maquina'
    exit 1
}
foreach ($b in $bix) {
    Write-Host ("  {0,-38} porta={1,-10} driver={2}" -f $b.Name, $b.PortName, $b.DriverName)
}

# ------------------------------------------------------------------ identificar
if ($Identificar) {
    Titulo 'IDENTIFICACAO'
    Write-Host '  Vou mandar um papel por fila, com o nome da fila impresso nele.'
    Write-Host '  Va ate as impressoras e veja qual cuspiu qual nome.'
    Write-Host ''
    foreach ($b in $bix) {
        $linhas = @(
            '',
            '=== QUEM SOU EU ===',
            $b.Name,
            "porta: $($b.PortName)",
            '',
            'Se esta e a do ESTOQUE (codigo de barra dos produtos),',
            'este nome vai virar: ' + $NomeCodigoDeBarra,
            'Se e a da NOTA FISCAL (etiqueta de envio),',
            'este nome vai virar: ' + $NomeEtiquetaFiscal,
            ''
        )
        try {
            # Pelo driver, nao em RAW: as duas podem estar em linguagens
            # diferentes (BPL x BPL-Z), e aqui so interessa sair papel.
            $linhas | Out-Printer -Name $b.Name
            OK "papel enviado para '$($b.Name)'"
        } catch {
            Aviso "nao consegui imprimir em '$($b.Name)': $($_.Exception.Message)"
        }
    }
    Write-Host ''
    Write-Host '  Com os dois papeis na mao, renomeie:'
    Write-Host ''
    Write-Host "     .\7-nomear-impressoras.ps1 ``"
    Write-Host "         -DeCodigoDeBarra '<nome da que imprimiu no ESTOQUE>' ``"
    Write-Host "         -DeEtiquetaFiscal '<nome da que imprimiu a NOTA FISCAL>' ``"
    Write-Host "         -Confirmar"
    Write-Host ''
    exit 0
}

# --------------------------------------------------------------------- renomear
if (-not $DeCodigoDeBarra -and -not $DeEtiquetaFiscal) {
    Titulo 'O QUE FAZER AGORA'
    Write-Host '  Nao sei qual das BIXOLON e qual. Rode primeiro:'
    Write-Host ''
    Write-Host '     .\7-nomear-impressoras.ps1 -Identificar'
    Write-Host ''
    Write-Host '  Ele manda um papel por fila com o nome impresso. Nao altera nada.'
    Write-Host ''
    exit 0
}

Titulo 'RENOMEAR'
$plano = @()
if ($DeCodigoDeBarra)  { $plano += ,@($DeCodigoDeBarra,  $NomeCodigoDeBarra) }
if ($DeEtiquetaFiscal) { $plano += ,@($DeEtiquetaFiscal, $NomeEtiquetaFiscal) }

# Um nome so pode virar um destino, e um destino so pode vir de um nome. Sem
# esta trava, um par invertido renomeia as duas para a mesma coisa.
if ($DeCodigoDeBarra -and $DeEtiquetaFiscal -and $DeCodigoDeBarra -eq $DeEtiquetaFiscal) {
    Erro 'as duas opcoes apontam para a MESMA impressora - confira os nomes'
    exit 1
}
if ($NomeCodigoDeBarra -eq $NomeEtiquetaFiscal) {
    Erro 'os dois nomes novos sao iguais - as impressoras ficariam indistinguiveis'
    exit 1
}

$erros = 0
foreach ($par in $plano) {
    $de   = $par[0]
    $para = $par[1]

    $alvo = @($todas | Where-Object { $_.Name -eq $de })
    if ($alvo.Count -eq 0) {
        Erro "nao existe impressora chamada '$de'"
        Write-Host '  Copie o nome exatamente como aparece na lista acima.'
        $erros++
        continue
    }
    if ($de -eq $para) {
        OK "'$de' ja tem o nome desejado"
        continue
    }
    if (@($todas | Where-Object { $_.Name -eq $para }).Count -gt 0) {
        Erro "ja existe uma impressora chamada '$para' - escolha outro nome"
        $erros++
        continue
    }

    # Job na fila e trabalho de alguem. Renomear com fila cheia perde o job.
    $jobs = @(Get-PrintJob -PrinterName $de -ErrorAction SilentlyContinue)
    if ($jobs.Count -gt 0) {
        Erro "'$de' tem $($jobs.Count) job(s) na fila - renomear agora perderia esse trabalho"
        Write-Host '  Espere a fila escoar (ou resolva o job preso) e rode de novo.'
        $erros++
        continue
    }

    if (-not $Confirmar) {
        Write-Host "  [PLANO] renomear '$de'  ->  '$para'"
        continue
    }
    try {
        Rename-Printer -Name $de -NewName $para
        OK "'$de'  ->  '$para'"
        # releitura: sem isso a checagem de nome repetido do proximo par olharia
        # a lista de antes do rename
        $todas = @(Get-Printer | Sort-Object Name)
    } catch {
        Erro "falhou renomear '$de': $($_.Exception.Message)"
        $erros++
    }
}

Titulo 'RESUMO'
if (-not $Confirmar) {
    Write-Host '  Isto foi so o PLANO - nada mudou. Repita com -Confirmar.'
} elseif ($erros -gt 0) {
    Write-Host "  $erros erro(s) acima. As impressoras que falharam mantem o nome antigo."
} else {
    Write-Host '  Nomes trocados. Agora:'
    Write-Host ''
    Write-Host '  1. No Chrome, no Ctrl+P, escolha o novo nome UMA vez - ele memoriza.'
    Write-Host "  2. Confira que a etiqueta de envio sai na `"$NomeEtiquetaFiscal`"."
    Write-Host ''
    Write-Host '  A porta USB nao mudou: renomear troca so o rotulo, nao o caminho.'
    Write-Host '  Se as impressoras trocarem de lugar de novo (cabo em outra porta USB),'
    Write-Host '  o nome passa a mentir - identifique de novo com -Identificar.'
}
Write-Host ''
