#Requires -Version 5.1
<#
    6-configurar-etiquetadora.ps1 - Monta o caminho ZPL/RAW do Argos Estoque:
    fila 'Generic / Text Only' na porta da BIXOLON de estoque, compartilhada, e
    o impressora_argos.txt ao lado do ArgosPrint.exe.

    O QUE ELE NAO FAZ, POR CONSTRUCAO:
    Nao altera, nao renomeia, nao recompartilha e nao remove NENHUMA impressora
    que ja exista nesta maquina - inclusive a BIXOLON FISCAL do UpSeller. Tudo
    o que ele escreve acontece numa fila NOVA, criada por ele. A unica excecao e
    apagar job preso, e so em fila BIXOLON que nao seja fiscal.

    Isso importa porque as duas BIXOLON desta maquina nao tem numero de serie:
    o Windows so as distingue pela porta USB, e porta USB troca de lugar. Um
    script que "adivinha" qual e qual acaba reconfigurando a fiscal no meio do
    despacho. Este aqui erra, no maximo, mandando etiqueta de teste para a
    impressora errada - e ai voce corrige com -PortaUsb.

    Por padrao SO MOSTRA O PLANO. Para executar de verdade, -Confirmar.

    Uso:
      powershell -ExecutionPolicy Bypass -File .\6-configurar-etiquetadora.ps1
      powershell -ExecutionPolicy Bypass -File .\6-configurar-etiquetadora.ps1 -Confirmar
      powershell -ExecutionPolicy Bypass -File .\6-configurar-etiquetadora.ps1 -ImpressoraEstoque "BIXOLON XD3-40t - BPL-Z #2" -Confirmar
#>
[CmdletBinding()]
param(
    [string]  $FilaArgos   = 'ARGOS - Codigo Estoque',
    [string]  $ImpressoraEstoque,
    [string[]]$Proteger    = @(),
    [string]  $PortaUsb,
    [int]     $PortaAgente = 9110,
    [switch]  $Confirmar,
    [switch]  $SemTeste
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
function Passo([string]$T) { Write-Host "  ->      $T" }

# Em modo plano nada e escrito: a acao vira uma linha de texto.
function Fazer([string]$Descricao, [scriptblock]$Acao) {
    if (-not $Confirmar) {
        Write-Host "  [PLANO] $Descricao"
        return $true
    }
    Passo $Descricao
    try {
        & $Acao | Out-Null
        return $true
    } catch {
        Erro "$Descricao -> $($_.Exception.Message)"
        return $false
    }
}

Write-Host ''
Write-Host "ARGOS - configuracao da etiquetadora  $(Get-Date -Format 'dd/MM/yyyy HH:mm')"
if ($Confirmar) {
    Write-Host 'MODO EXECUCAO: as mudancas abaixo serao aplicadas.'
} else {
    Write-Host 'MODO PLANO: nada sera alterado. Reveja e rode de novo com -Confirmar.'
}

# ------------------------------------------------------------------- 0. admin
Titulo '0. PRE-REQUISITOS'
$idt     = [Security.Principal.WindowsIdentity]::GetCurrent()
$ehAdmin = ([Security.Principal.WindowsPrincipal]$idt).IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)
if ($ehAdmin) {
    OK 'PowerShell como Administrador'
} elseif ($Confirmar) {
    Erro 'Criar e compartilhar fila exige Administrador. Abra o PowerShell como administrador.'
    exit 1
} else {
    Aviso 'sem Administrador - da para ver o plano, mas -Confirmar vai exigir elevacao'
}

foreach ($c in @('Get-Printer', 'Add-Printer', 'Get-PrinterDriver')) {
    if (-not (Get-Command $c -ErrorAction SilentlyContinue)) {
        Erro "$c indisponivel nesta versao do Windows - este script depende do modulo PrintManagement"
        exit 1
    }
}
OK 'modulo PrintManagement disponivel'

# ------------------------------------------------------- 1. quem NAO se toca
# A fiscal e reconhecida pelo nome/compartilhamento. O que cair nesta lista fica
# fora de qualquer operacao daqui para baixo - inclusive da limpeza de fila.
Titulo '1. IMPRESSORAS DESTA MAQUINA'
$todas = @(Get-Printer | Sort-Object Name)
if ($todas.Count -eq 0) {
    Erro 'nenhuma impressora instalada - nao ha porta USB conhecida para usar'
    exit 1
}
foreach ($p in $todas) {
    Write-Host ("  {0,-38} porta={1,-10} driver={2}" -f $p.Name, $p.PortName, $p.DriverName)
}

# Procurar "fiscal" no nome nao protege nada: nesta instalacao a impressora que
# tira a etiqueta de nota fiscal se chama 'BIXOLON XD3-40t - BPL'. Entao a lista
# de intocaveis nao depende so do nome - entra tambem a impressora PADRAO do
# Windows e tudo que vier em -Proteger.
$intocaveis = @($todas | Where-Object {
    $_.Name -match 'fiscal' -or $_.ShareName -match 'fiscal' -or ($Proteger -contains $_.Name)
})
$padrao = @(Get-CimInstance Win32_Printer -ErrorAction SilentlyContinue | Where-Object { $_.Default })
if ($padrao.Count -gt 0) {
    $nomePadrao = $padrao[0].Name
    if ($nomePadrao -ne $ImpressoraEstoque -and
        (@($intocaveis | ForEach-Object { $_.Name }) -notcontains $nomePadrao)) {
        $obj = @($todas | Where-Object { $_.Name -eq $nomePadrao })
        if ($obj.Count -gt 0) { $intocaveis += $obj[0] }
    }
}
if ($intocaveis.Count -gt 0) {
    Write-Host ''
    foreach ($f in $intocaveis) { Aviso "INTOCAVEL: $($f.Name)  (porta $($f.PortName))" }
}

# ---------------------------------------------------- 2. a porta da etiquetadora
Titulo '2. PORTA DA BIXOLON DE ESTOQUE'
$nomesIntocaveis = @($intocaveis | ForEach-Object { $_.Name })
$bixolons = @($todas | Where-Object {
    ($_.Name -match 'BIXOLON' -or $_.DriverName -match 'BIXOLON|BPL') -and
    ($nomesIntocaveis -notcontains $_.Name)
})

$porta   = $null
$estoque = $null
if ($ImpressoraEstoque) {
    $achada = @($todas | Where-Object { $_.Name -eq $ImpressoraEstoque })
    if ($achada.Count -eq 0) {
        Erro "nao existe impressora chamada '$ImpressoraEstoque' nesta maquina"
        Write-Host '  Os nomes disponiveis estao na lista do item 1, copiados exatamente como aparecem.'
        exit 1
    }
    if (@($intocaveis | ForEach-Object { $_.Name }) -contains $ImpressoraEstoque) {
        Erro "'$ImpressoraEstoque' esta na lista de intocaveis - recusando"
        exit 1
    }
    $estoque = $achada[0]
    $porta   = $estoque.PortName
    OK "impressora de estoque indicada: $($estoque.Name) -> porta $porta"
} elseif ($PortaUsb) {
    $porta = $PortaUsb
    OK "porta forcada por -PortaUsb: $porta"
} elseif ($bixolons.Count -eq 1) {
    $estoque = $bixolons[0]
    $porta   = $estoque.PortName
    OK "uma unica BIXOLON fora da lista de intocaveis: $($estoque.Name) -> porta $porta"
} elseif ($bixolons.Count -eq 0) {
    Erro 'nenhuma BIXOLON nao-fiscal instalada - nao da para deduzir a porta'
    Write-Host '  Rode com -PortaUsb USB001 (ou USB002) depois de conferir qual e qual.'
    exit 1
} else {
    Aviso "$($bixolons.Count) BIXOLON candidatas - nao da para adivinhar qual e a do estoque:"
    foreach ($b in $bixolons) { Write-Host ("     {0,-38} porta={1}" -f $b.Name, $b.PortName) }
    Write-Host ''
    Write-Host '  Diga qual e a do ESTOQUE (a que NAO tira etiqueta de nota fiscal),'
    Write-Host '  copiando o nome exatamente como aparece acima:'
    Write-Host "     .\6-configurar-etiquetadora.ps1 -ImpressoraEstoque `"$($bixolons[0].Name)`""
    Write-Host ''
    Write-Host '  E proteja explicitamente a da nota fiscal:'
    Write-Host "     ... -Proteger `"$($bixolons[0].Name)`""
    Write-Host ''
    Write-Host '  Se a etiqueta de teste sair na impressora errada, rode de novo com a outra:'
    Write-Host '  o script so mexe na fila NOVA, nunca nas que ja existem.'
    exit 1
}

# O instance id de cada USBPRINT termina no nome da porta - e assim que da para
# saber quais portas tem impressora LIGADA agora. LPT3: e USB005 orfa aceitam
# trabalho e engolem calados: o spooler nao reclama, o papel nao sai.
$portasVivas = @()
if (Get-Command 'Get-PnpDevice' -ErrorAction SilentlyContinue) {
    $portasVivas = @(@(Get-PnpDevice -PresentOnly -ErrorAction SilentlyContinue |
        Where-Object { $_.InstanceId -like 'USBPRINT\*' } |
        ForEach-Object { if ($_.InstanceId -match '(USB\d+)$') { $Matches[1] } }) |
        Select-Object -Unique)
}
if ($portasVivas.Count -gt 0) {
    Write-Host "  Portas com impressora ligada agora: $($portasVivas -join ', ')"
    if ($portasVivas -notcontains $porta) {
        Erro "a porta $porta NAO tem impressora ligada agora"
        Write-Host ''
        Write-Host '  Fila apontada para porta morta aceita o trabalho e nao imprime nada:'
        Write-Host '  o spooler nao acusa erro e o site diz que imprimiu. E o que ja acontece'
        Write-Host "  hoje com a fila '$FilaArgos' apontada para LPT3:."
        Write-Host ''
        Write-Host "  Use uma das portas vivas: $($portasVivas -join ', ')"
        Write-Host "     .\6-configurar-etiquetadora.ps1 -PortaUsb $($portasVivas[0]) -Confirmar"
        exit 1
    }
    OK "porta $porta tem impressora ligada"
}

if ($porta -and ($intocaveis | Where-Object { $_.PortName -eq $porta })) {
    Erro "a porta $porta e a da FISCAL ($(($intocaveis | Where-Object { $_.PortName -eq $porta })[0].Name))."
    Erro 'Recusando: a fila do estoque nessa porta mandaria ZPL para a impressora fiscal.'
    Write-Host '  Confira a porta certa e passe -PortaUsb com a outra.'
    exit 1
}

# ------------------------------------------------------------ 3. job preso
Titulo '3. JOB PRESO'
# Apagar job e destrutivo e nao tem volta: um job apagado na fila da nota fiscal
# e uma etiqueta de envio que ninguem imprimiu e ninguem sabe que faltou. Entao
# so acontece na fila que foi IDENTIFICADA como a do estoque - nunca varrendo
# todas as BIXOLON.
if (-not $estoque) {
    Aviso 'fila do estoque nao identificada com certeza - limpeza pulada'
    Aviso 'Passe -ImpressoraEstoque "<nome>" para eu apagar job preso da fila certa.'
} else {
    $jobs = @(Get-PrintJob -PrinterName $estoque.Name -ErrorAction SilentlyContinue)
    if ($jobs.Count -eq 0) {
        Write-Host "  $($estoque.Name): fila vazia"
    } else {
        Write-Host "  $($estoque.Name): $($jobs.Count) job(s) preso(s)"
        foreach ($j in $jobs) { Write-Host ("     id {0}  {1}  enviado {2}" -f $j.Id, $j.JobStatus, $j.SubmittedTime) }
        $nome = $estoque.Name
        [void](Fazer "apagar $($jobs.Count) job(s) preso(s) de '$nome'" {
            Get-PrintJob -PrinterName $nome | Remove-PrintJob
        })
    }
}

# ------------------------------------------------------- 4. driver Generic/Text
Titulo '4. DRIVER Generic / Text Only'
# O nome do driver muda com o idioma do Windows. Procurar os dois.
$nomesDriver = @('Generic / Text Only', 'Generico / Somente texto')
$driver = $null
foreach ($n in $nomesDriver) {
    $d = Get-PrinterDriver -Name $n -ErrorAction SilentlyContinue
    if ($d) { $driver = $n; break }
}
if ($driver) {
    OK "driver ja instalado: $driver"
} else {
    $driver = $nomesDriver[0]
    $alvo = $driver
    if (-not (Fazer "instalar o driver '$alvo' (vem com o Windows)" { Add-PrinterDriver -Name $alvo })) {
        Erro 'nao foi possivel instalar o driver Generic / Text Only'
        Erro 'Sem ele nao existe caminho ZPL/RAW. Instale por Painel de Controle > Dispositivos e Impressoras.'
        exit 1
    }
}

# ------------------------------------------------------------- 5. a fila nova
Titulo "5. FILA '$FilaArgos'"
$existente = Get-Printer -Name $FilaArgos -ErrorAction SilentlyContinue
if ($existente) {
    OK "fila ja existe (porta atual: $($existente.PortName))"
    if ($existente.PortName -ne $porta) {
        [void](Fazer "mover a fila '$FilaArgos' da porta $($existente.PortName) para $porta" {
            Set-Printer -Name $FilaArgos -PortName $porta
        })
    }
    if ($existente.DriverName -ne $driver) {
        Aviso "driver atual: '$($existente.DriverName)'"
        Aviso 'ZPL cru passando por driver de impressora sai deformado - o caminho RAW precisa do Generic / Text Only.'
        [void](Fazer "trocar o driver da fila para '$driver'" {
            Set-Printer -Name $FilaArgos -DriverName $driver
        })
    } else {
        OK "driver ja e '$driver'"
    }
    if (-not $existente.Shared -or $existente.ShareName -ne $FilaArgos) {
        [void](Fazer "compartilhar a fila como '$FilaArgos'" {
            Set-Printer -Name $FilaArgos -Shared $true -ShareName $FilaArgos
        })
    } else {
        OK "ja compartilhada como '$FilaArgos'"
    }
} else {
    $d = $driver
    if (-not (Fazer "criar a fila '$FilaArgos' (driver '$d', porta $porta), compartilhada" {
        Add-Printer -Name $FilaArgos -DriverName $d -PortName $porta -Shared -ShareName $FilaArgos
    })) {
        Erro 'nao foi possivel criar a fila - o resto depende dela'
        exit 1
    }
}

# -------------------------------------------------------- 6. impressora_argos.txt
Titulo '6. impressora_argos.txt'
$destino = "\\localhost\$FilaArgos"
$proc  = @(Get-Process -Name 'ArgosPrint' -ErrorAction SilentlyContinue)
$pasta = $null
if ($proc.Count -gt 0 -and $proc[0].Path) { $pasta = Split-Path $proc[0].Path -Parent }
if (-not $pasta) {
    $candidatos = @(
        [Environment]::GetFolderPath('Desktop'),
        "$env:USERPROFILE\Desktop",
        "$env:USERPROFILE\Scripts",
        "$env:USERPROFILE\ArgosPrint",
        'C:\ArgosPrint',
        'C:\Argos',
        "$env:APPDATA\Microsoft\Windows\Start Menu\Programs\Startup"
    ) | Where-Object { $_ } | Select-Object -Unique
    foreach ($c in $candidatos) {
        $achado = Get-ChildItem -LiteralPath $c -Filter 'ArgosPrint.exe' -Recurse -Depth 2 -File -ErrorAction SilentlyContinue |
                    Select-Object -First 1
        if ($achado) { $pasta = $achado.DirectoryName; break }
    }
}
if (-not $pasta) {
    Erro 'ArgosPrint.exe nao encontrado - nao sei onde gravar o impressora_argos.txt'
    Write-Host "  Crie o arquivo a mao, ao lado do ArgosPrint.exe, com uma linha:  $destino"
} else {
    OK "pasta do agente: $pasta"
    $txt = Join-Path $pasta 'impressora_argos.txt'
    $atual = $null
    if (Test-Path -LiteralPath $txt) {
        $bruto = Get-Content -LiteralPath $txt -Raw -ErrorAction SilentlyContinue
        if ($bruto) { $atual = $bruto.TrimStart([char]0xFEFF).Trim() }
    }
    if ($atual -eq $destino) {
        OK "impressora_argos.txt ja aponta para [$destino]"
    } else {
        if ($atual) { Aviso "conteudo atual: [$atual] - sera substituido" }
        # Sem BOM: o agente le a linha crua, e um BOM na frente vira parte do nome.
        [void](Fazer "gravar $txt com [$destino]" {
            [IO.File]::WriteAllText($txt, $destino, (New-Object Text.UTF8Encoding($false)))
        })
    }
}

# ------------------------------------------------------------ 7. reiniciar agente
Titulo '7. AGENTE ArgosPrint'
if ($proc.Count -eq 0) {
    Aviso 'ArgosPrint.exe nao esta rodando'
    if ($pasta) {
        $exe = Join-Path $pasta 'ArgosPrint.exe'
        [void](Fazer "iniciar $exe" { Start-Process -FilePath $exe -WorkingDirectory $pasta })
    }
} else {
    # O destino e lido na subida: sem reiniciar, o agente segue no valor antigo.
    $exe = $proc[0].Path
    if (-not $exe -and $pasta) { $exe = Join-Path $pasta 'ArgosPrint.exe' }
    if (-not $exe -or -not (Test-Path -LiteralPath $exe)) {
        Aviso 'nao consegui descobrir o caminho do ArgosPrint.exe em execucao'
        Aviso 'Feche e abra o agente a mao - senao ele segue com o destino antigo.'
    } else {
        # Encerrar TODAS as instancias, nao so a primeira: cada execucao deste
        # script subia mais uma e deixava as antigas vivas. Sobra um bando de
        # ArgosPrint disputando a 9110 - uma ganha, as outras ficam de enfeite,
        # e nao da para saber qual respondeu o /status.
        $ids = @($proc | ForEach-Object { $_.Id })
        [void](Fazer "encerrar $($ids.Count) instancia(s) do ArgosPrint (PID $($ids -join ', ')) e subir UMA" {
            foreach ($i in $ids) { Stop-Process -Id $i -Force -ErrorAction SilentlyContinue }
            Start-Sleep -Seconds 2
            Start-Process -FilePath $exe -WorkingDirectory (Split-Path $exe -Parent)
        })
        if ($Confirmar) { Start-Sleep -Seconds 3 }
    }
}

# -------------------------------------------------------------- 8. etiqueta teste
Titulo '8. ETIQUETA DE TESTE'
if ($SemTeste) {
    Aviso 'pulado por -SemTeste'
} elseif (-not $Confirmar) {
    Write-Host "  [PLANO] mandar uma etiqueta ZPL de teste para '$FilaArgos'"
} else {
    # RAW de verdade: WritePrinter, sem passar por driver. E o mesmo caminho que
    # o agente usa - se esta sair, o dele sai.
    $zpl = "^XA^FO40,40^A0N,36,36^FDARGOS TESTE^FS^FO40,100^A0N,28,28^FD$porta^FS^XZ`r`n"
    try {
        if (-not ('Argos.RawPrinterNative' -as [type])) {
            Add-Type -Namespace Argos -Name RawPrinterNative -MemberDefinition @'
[DllImport("winspool.drv", CharSet=CharSet.Auto, SetLastError=true)]
public static extern bool OpenPrinter(string src, out IntPtr hPrinter, IntPtr pd);
[DllImport("winspool.drv", SetLastError=true)]
public static extern bool ClosePrinter(IntPtr hPrinter);
[DllImport("winspool.drv", CharSet=CharSet.Auto, SetLastError=true)]
public static extern bool StartDocPrinter(IntPtr hPrinter, int level, [In, MarshalAs(UnmanagedType.LPStruct)] DOCINFO di);
[DllImport("winspool.drv", SetLastError=true)]
public static extern bool EndDocPrinter(IntPtr hPrinter);
[DllImport("winspool.drv", SetLastError=true)]
public static extern bool StartPagePrinter(IntPtr hPrinter);
[DllImport("winspool.drv", SetLastError=true)]
public static extern bool EndPagePrinter(IntPtr hPrinter);
[DllImport("winspool.drv", SetLastError=true)]
public static extern bool WritePrinter(IntPtr hPrinter, IntPtr pBytes, int count, out int written);
[StructLayout(LayoutKind.Sequential, CharSet=CharSet.Auto)]
public class DOCINFO {
    [MarshalAs(UnmanagedType.LPTStr)] public string pDocName = "ARGOS teste";
    [MarshalAs(UnmanagedType.LPTStr)] public string pOutputFile = null;
    [MarshalAs(UnmanagedType.LPTStr)] public string pDataType = "RAW";
}
'@
        }
        $h = [IntPtr]::Zero
        if (-not [Argos.RawPrinterNative]::OpenPrinter($FilaArgos, [ref]$h, [IntPtr]::Zero)) {
            throw "OpenPrinter falhou para '$FilaArgos'"
        }
        try {
            $di = New-Object Argos.RawPrinterNative+DOCINFO
            [void][Argos.RawPrinterNative]::StartDocPrinter($h, 1, $di)
            [void][Argos.RawPrinterNative]::StartPagePrinter($h)
            $bytes = [Text.Encoding]::ASCII.GetBytes($zpl)
            $buf   = [Runtime.InteropServices.Marshal]::AllocCoTaskMem($bytes.Length)
            try {
                [Runtime.InteropServices.Marshal]::Copy($bytes, 0, $buf, $bytes.Length)
                $escrito = 0
                [void][Argos.RawPrinterNative]::WritePrinter($h, $buf, $bytes.Length, [ref]$escrito)
                OK "$escrito byte(s) de ZPL enviados para '$FilaArgos'"
            } finally {
                [Runtime.InteropServices.Marshal]::FreeCoTaskMem($buf)
            }
            [void][Argos.RawPrinterNative]::EndPagePrinter($h)
            [void][Argos.RawPrinterNative]::EndDocPrinter($h)
        } finally {
            [void][Argos.RawPrinterNative]::ClosePrinter($h)
        }
    } catch {
        Aviso "nao consegui mandar a etiqueta de teste: $($_.Exception.Message)"
        Aviso 'O caminho pode estar certo mesmo assim - prove pelo Argos Estoque no Chrome.'
    }
}

# ------------------------------------------------------------------- resumo
Titulo 'RESUMO'
if (-not $Confirmar) {
    Write-Host '  Isto foi so o PLANO - nada mudou nesta maquina.'
    Write-Host '  Se as portas e os nomes acima estiverem certos, rode:'
    Write-Host '     .\6-configurar-etiquetadora.ps1 -Confirmar'
} else {
    Write-Host '  CONFIRA AGORA, com os olhos:'
    Write-Host '  1. A etiqueta "ARGOS TESTE" saiu na etiquetadora do ESTOQUE?'
    Write-Host "     Se saiu na FISCAL, rode de novo com a outra porta -PortaUsb."
    Write-Host "     So a fila '$FilaArgos' muda de porta; a fiscal nao e tocada."
    Write-Host '  2. Depois, no Chrome logado no Argos Estoque (F12 -> Console):'
    Write-Host '        await ArgosPrint.disponivel()      // tem que dar true'
    Write-Host ''
    Write-Host '  E rode o diagnostico de novo para o relatorio final:'
    Write-Host '     .\5-diagnostico-etiquetadora.ps1'
}
Write-Host ''
