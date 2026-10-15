#Requires -Version 5.1
<#
    5-backup-formatacao.ps1 - Backup completo antes de formatar.

    1. Testa o acesso ao servidor (ping, porta SMB 445, leitura e escrita no
       compartilhamento) e mostra para onde aponta cada unidade de rede.
    2. Confere a unidade de destino (padrao E:) e o espaco livre.
    3. Copia as pastas do usuario, perfis de navegador, assinaturas e PSTs do
       Outlook e as pastas extras que voce indicar.
    4. Exporta o que se perde na formatacao: lista de programas, drivers,
       impressoras, unidades mapeadas, perfis Wi-Fi, chave OEM do Windows.
    5. Confere arquivo por arquivo (caminho e tamanho) e diz se pode formatar.

    Nunca apaga nada da maquina. Por padrao so SIMULA (mostra o que copiaria
    e quanto ocupa). Para copiar de verdade, use -Executar. Pode rodar de novo
    quantas vezes quiser: o robocopy so copia o que faltou.

    Uso:
      # testar servidor + simular
      .\5-backup-formatacao.ps1 -Servidor "\\khaosomni\backup"

      # backup de verdade na unidade E:
      .\5-backup-formatacao.ps1 -Servidor "\\khaosomni\backup" -Executar

      # incluir pastas fora do perfil do usuario
      .\5-backup-formatacao.ps1 -Executar -Extras "C:\Projetos","D:\Fotos"
#>
[CmdletBinding()]
param(
    [string]  $Destino = 'E:\',
    [string]  $Servidor,
    [string[]]$Extras  = @(),
    [switch]  $Executar,
    [switch]  $IncluirOneDrive,
    [switch]  $WifiComSenha,
    [string]  $Nome    = "Backup-$env:COMPUTERNAME-$(Get-Date -Format 'yyyyMMdd')"
)

$ErrorActionPreference = 'Continue'
$script:Linhas = New-Object System.Collections.ArrayList
$script:Problemas = New-Object System.Collections.ArrayList
$script:DestinoRuim = $false

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
function Problema([string]$Texto) {
    [void]$script:Problemas.Add($Texto)
    Escrever "  [!] $Texto" 'Red'
}
function ComoGB($Bytes) { '{0,8:N2} GB' -f ($Bytes / 1GB) }
function EhAdmin {
    $id = [Security.Principal.WindowsIdentity]::GetCurrent()
    (New-Object Security.Principal.WindowsPrincipal $id).IsInRole(
        [Security.Principal.WindowsBuiltInRole]::Administrator)
}
function TesteEscrita([string]$Pasta) {
    $teste = Join-Path $Pasta ".teste-escrita-$PID.tmp"
    try {
        Set-Content -LiteralPath $teste -Value 'ok' -ErrorAction Stop
        Remove-Item -LiteralPath $teste -Force -ErrorAction SilentlyContinue
        return $true
    } catch { return $false }
}

# Lista arquivos com caminho relativo e tamanho, pulando junctions (como o
# robocopy /XJ) e as pastas excluidas. Usada antes e depois da copia, para que
# a conferencia compare exatamente o mesmo conjunto.
function Listar([string]$Raiz, [string[]]$ExcluirPastas) {
    $mapa = @{}
    if (-not (Test-Path -LiteralPath $Raiz)) { return $mapa }
    $raizCheia = (Get-Item -LiteralPath $Raiz -Force).FullName.TrimEnd('\')
    $pilha = New-Object System.Collections.Stack
    $pilha.Push($raizCheia)
    while ($pilha.Count -gt 0) {
        $atual = $pilha.Pop()
        try {
            foreach ($info in (New-Object IO.DirectoryInfo $atual).EnumerateFileSystemInfos()) {
                if ($info.Attributes -band [IO.FileAttributes]::ReparsePoint) { continue }
                if ($info -is [IO.DirectoryInfo]) {
                    if ($ExcluirPastas -notcontains $info.Name) { $pilha.Push($info.FullName) }
                } else {
                    $mapa[$info.FullName.Substring($raizCheia.Length + 1)] = $info.Length
                }
            }
        } catch { }  # pasta sem permissao: segue com o que conseguiu ler
    }
    return $mapa
}

Escrever "Backup antes da formatacao - $(Get-Date -Format 'dd/MM/yyyy HH:mm')"
Escrever "Computador: $env:COMPUTERNAME   Usuario: $env:USERNAME"
if (-not $Executar) {
    Escrever ''
    Escrever '>>> MODO SIMULACAO: nada sera copiado. Repita com -Executar para valer. <<<' 'Yellow'
}
if (-not (EhAdmin)) {
    Escrever ''
    Escrever '*** Sem administrador: a exportacao de drivers sera pulada.' 'Yellow'
}

# ================================================================ 1. servidor
Titulo '1. ACESSO A REDE E AO SERVIDOR'

$mapeadas = @(Get-CimInstance Win32_LogicalDisk -Filter 'DriveType=4' -ErrorAction SilentlyContinue)
if ($mapeadas.Count -eq 0) {
    Escrever 'Nenhuma unidade de rede mapeada.'
} else {
    Escrever 'Unidades de rede mapeadas:'
    foreach ($m in $mapeadas) {
        $estado = if ($m.Size) { 'conectada, livre ' + (ComoGB $m.FreeSpace) } else { 'DESCONECTADA' }
        Escrever ('  {0}  ->  {1}   ({2})' -f $m.DeviceID, $m.ProviderName, $estado)
    }
}

if ($Servidor) {
    $hostAlvo = ($Servidor -replace '^\\\\', '' -split '\\')[0]
    $compartilhamento = if ($Servidor -match '^\\\\[^\\]+\\.+') { $Servidor } else { $null }
    Escrever ''
    Escrever "Servidor: $hostAlvo"

    $ping = Test-Connection -ComputerName $hostAlvo -Count 2 -Quiet -ErrorAction SilentlyContinue
    Escrever ('  Responde ping ............: {0}' -f $(if ($ping) { 'sim' } else { 'nao (pode ser so firewall)' }))

    $smb = $false
    try {
        $smb = (Test-NetConnection -ComputerName $hostAlvo -Port 445 -WarningAction SilentlyContinue).TcpTestSucceeded
    } catch { }
    Escrever ('  Porta SMB 445 aberta .....: {0}' -f $(if ($smb) { 'sim' } else { 'NAO' }))
    if (-not $smb) {
        Problema "Servidor $hostAlvo inacessivel na porta 445. Confira VPN/cabo, nome e firewall."
    }

    if ($compartilhamento) {
        if (Test-Path -LiteralPath $compartilhamento) {
            Escrever "  Leitura em $compartilhamento .: ok"
            if (TesteEscrita $compartilhamento) {
                Escrever "  Escrita em $compartilhamento .: ok" 'Green'
            } else {
                Problema "Sem permissao de escrita em $compartilhamento."
            }
        } else {
            Problema "Compartilhamento $compartilhamento nao abre (permissao ou caminho errado)."
            Escrever '      Para mapear com usuario e senha:'
            Escrever "      net use E: $compartilhamento /user:DOMINIO\usuario /persistent:yes"
        }
    } else {
        Escrever '  (Informe o compartilhamento completo, ex: \\servidor\pasta, para testar leitura e escrita.)'
    }
} else {
    Escrever ''
    Escrever 'Servidor nao informado. Use -Servidor "\\nome-do-servidor\compartilhamento" para testar.'
}

# ================================================================ 2. destino
Titulo '2. DESTINO'

$letra = if ($Destino -match '^\\\\') { $null } else { Split-Path -Qualifier $Destino }
if (-not (Test-Path -LiteralPath $Destino)) {
    Problema "Destino $Destino nao encontrado. Ligue o HD externo ou mapeie a unidade de rede."
    $script:DestinoRuim = $true
    $livre = [int64]0
} else {
    if ($letra) {
        $disco = Get-CimInstance Win32_LogicalDisk -Filter "DeviceID='$letra'"
        $tipo = switch ($disco.DriveType) { 2 { 'removivel' } 3 { 'disco local' } 4 { 'rede -> ' + $disco.ProviderName } default { "tipo $($disco.DriveType)" } }
        $livre = [int64]$disco.FreeSpace
        Escrever ("Unidade {0} ({1})   livre: {2}" -f $letra, $tipo, (ComoGB $livre))
        if ($letra -eq $env:SystemDrive) {
            Problema "O destino esta no proprio disco do sistema ($letra). Ele sera apagado na formatacao!"
            $script:DestinoRuim = $true
        }
    } else {
        $livre = [int64]::MaxValue
        Escrever "Destino de rede: $Destino (espaco livre nao informado pelo Windows)"
    }
    if (TesteEscrita $Destino) { Escrever 'Escrita no destino: ok' }
    else { Problema "Sem permissao de escrita em $Destino."; $script:DestinoRuim = $true }
}
$raizBackup = Join-Path $Destino $Nome
Escrever "Pasta do backup: $raizBackup"

# ================================================================ 3. o que copiar
Titulo '3. O QUE SERA COPIADO'

$perfil = $env:USERPROFILE
$cacheNavegador = @('Cache', 'Code Cache', 'GPUCache', 'Service Worker', 'ShaderCache',
                    'GrShaderCache', 'Crashpad', 'cache2', 'startupCache')
$itens = New-Object System.Collections.ArrayList
function Adicionar([string]$Rotulo, [string]$Origem, [string]$Destino, [string[]]$Excluir = @(), [string[]]$Filtro = @()) {
    if (-not $Origem -or -not (Test-Path -LiteralPath $Origem)) { return }
    $cheia = (Get-Item -LiteralPath $Origem -Force).FullName.TrimEnd('\')
    foreach ($ja in $script:itens) {
        if ($cheia -eq $ja.Origem -or $cheia.StartsWith($ja.Origem + '\', [StringComparison]::OrdinalIgnoreCase)) { return }
    }
    [void]$script:itens.Add([pscustomobject]@{
        Rotulo = $Rotulo; Origem = $cheia; Destino = $Destino; Excluir = $Excluir; Filtro = $Filtro })
}

# Pastas conhecidas: pega o caminho real (podem ter sido redirecionadas p/ OneDrive ou D:)
$conhecidas = [ordered]@{
    'Area de Trabalho' = [Environment]::GetFolderPath('Desktop')
    'Documentos'       = [Environment]::GetFolderPath('MyDocuments')
    'Imagens'          = [Environment]::GetFolderPath('MyPictures')
    'Videos'           = [Environment]::GetFolderPath('MyVideos')
    'Musicas'          = [Environment]::GetFolderPath('MyMusic')
    'Favoritos'        = [Environment]::GetFolderPath('Favorites')
    'Downloads'        = Join-Path $perfil 'Downloads'
    'Contatos'         = Join-Path $perfil 'Contacts'
    'Links'            = Join-Path $perfil 'Links'
    'Jogos salvos'     = Join-Path $perfil 'Saved Games'
}
foreach ($k in $conhecidas.Keys) { Adicionar $k $conhecidas[$k] "Usuario\$k" }

# Demais pastas soltas no perfil (projetos, etc.)
$pulaPerfil = @('AppData', 'OneDrive', 'MicrosoftEdgeBackups', 'IntelGraphicsProfiles', 'ansel', '3D Objects')
Get-ChildItem -LiteralPath $perfil -Directory -Force -ErrorAction SilentlyContinue |
    Where-Object { -not ($_.Attributes -band [IO.FileAttributes]::ReparsePoint) -and
                   -not ($_.Attributes -band [IO.FileAttributes]::Hidden) -and
                   $pulaPerfil -notcontains $_.Name -and $_.Name -notlike 'OneDrive*' } |
    ForEach-Object { Adicionar $_.Name $_.FullName "Usuario\$($_.Name)" }

if ($IncluirOneDrive) {
    Get-ChildItem -LiteralPath $perfil -Directory -Filter 'OneDrive*' -ErrorAction SilentlyContinue |
        ForEach-Object { Adicionar $_.Name $_.FullName "Usuario\$($_.Name)" }
}

# Navegadores (favoritos, senhas salvas, extensoes, historico) sem os caches
$la = $env:LOCALAPPDATA; $ra = $env:APPDATA
Adicionar 'Chrome'  "$la\Google\Chrome\User Data"         'Navegadores\Chrome'  $cacheNavegador
Adicionar 'Edge'    "$la\Microsoft\Edge\User Data"        'Navegadores\Edge'    $cacheNavegador
Adicionar 'Brave'   "$la\BraveSoftware\Brave-Browser\User Data" 'Navegadores\Brave' $cacheNavegador
Adicionar 'Firefox' "$ra\Mozilla\Firefox\Profiles"        'Navegadores\Firefox' $cacheNavegador

# Outlook: arquivos PST e assinaturas (OST se recria sozinho a partir do servidor)
Adicionar 'Outlook PST'         "$la\Microsoft\Outlook" 'Outlook\PST' @() @('*.pst')
Adicionar 'Outlook assinaturas' "$ra\Microsoft\Signatures" 'Outlook\Assinaturas'

foreach ($e in $Extras) {
    if (Test-Path -LiteralPath $e) {
        $rotulo = ($e -replace '[:\\]+', '_').Trim('_')
        Adicionar $rotulo $e "Extras\$rotulo"
    } else {
        Problema "Pasta extra nao encontrada: $e"
    }
}

# Calcula tamanhos (mesma regra de exclusao da copia)
$total = [int64]0
foreach ($it in $itens) {
    $mapa = Listar $it.Origem $it.Excluir
    if ($it.Filtro.Count) {
        $filtrado = @{}
        foreach ($k in $mapa.Keys) { foreach ($f in $it.Filtro) { if ((Split-Path $k -Leaf) -like $f) { $filtrado[$k] = $mapa[$k] } } }
        $mapa = $filtrado
    }
    $soma = [int64]0; foreach ($v in $mapa.Values) { $soma += $v }
    $it | Add-Member -NotePropertyName Mapa -NotePropertyValue $mapa
    $it | Add-Member -NotePropertyName Bytes -NotePropertyValue $soma
    $total += $soma
    Escrever ('  {0,-24} {1}  {2,8} arq.  {3}' -f $it.Rotulo, (ComoGB $soma), $mapa.Count, $it.Origem)
}
Escrever ''
Escrever ("TOTAL: {0}" -f (ComoGB $total))

# Pastas na raiz dos discos que nao sao do Windows: o usuario decide
$padraoRaiz = @('Windows', 'Program Files', 'Program Files (x86)', 'ProgramData', 'Users',
                'PerfLogs', 'Recovery', '$Recycle.Bin', '$WinREAgent', 'System Volume Information',
                'Config.Msi', 'Documents and Settings', 'OneDriveTemp', 'Intel', 'AMD', 'NVIDIA', 'drivers')
$discosLocais = Get-CimInstance Win32_LogicalDisk -Filter 'DriveType=3' | Where-Object { $_.DeviceID -ne $letra }
$soltas = foreach ($d in $discosLocais) {
    Get-ChildItem -LiteralPath "$($d.DeviceID)\" -Directory -Force -ErrorAction SilentlyContinue |
        Where-Object { $padraoRaiz -notcontains $_.Name -and -not ($_.Attributes -band [IO.FileAttributes]::Hidden) } |
        Where-Object { $o = $_.FullName.TrimEnd('\'); -not ($itens | Where-Object { $_.Origem -eq $o }) }
}
if ($soltas) {
    Escrever ''
    Escrever 'Pastas fora do perfil que NAO estao no backup (confira se precisa):' 'Yellow'
    $soltas | ForEach-Object { Escrever "  $($_.FullName)" }
    Escrever '  Para incluir: -Extras "C:\Pasta1","D:\Pasta2"'
}
if (-not $IncluirOneDrive -and (Get-ChildItem -LiteralPath $perfil -Directory -Filter 'OneDrive*' -ErrorAction SilentlyContinue)) {
    Escrever ''
    Escrever 'OneDrive ficou de fora (ja esta na nuvem). Para copiar mesmo assim: -IncluirOneDrive' 'Yellow'
}

if ($total -gt $livre) {
    Problema ("Espaco insuficiente no destino: precisa de {0}, ha {1}. Libere espaco em {2} ou use outro destino." -f (ComoGB $total), (ComoGB $livre), $Destino)
    $script:DestinoRuim = $true
}

if (-not $Executar) {
    Titulo 'RESUMO DA SIMULACAO'
    if ($script:Problemas.Count) {
        Escrever 'Resolva antes de executar:' 'Red'
        $script:Problemas | ForEach-Object { Escrever "  - $_" }
    } else {
        Escrever 'Tudo pronto. Feche navegadores e Outlook e rode de novo com -Executar.' 'Green'
    }
    exit 0
}
if ($script:DestinoRuim) {
    Escrever ''
    Escrever 'Backup cancelado: o destino nao esta utilizavel (veja acima).' 'Red'
    exit 1
}

# ================================================================ 4. copia
Titulo '4. COPIANDO'
Escrever 'Feche navegadores e Outlook: arquivos abertos nao sao copiados.'
New-Item -ItemType Directory -Path $raizBackup -Force | Out-Null
$logRobo = Join-Path $raizBackup 'robocopy.log'

foreach ($it in $itens) {
    $alvo = Join-Path $raizBackup $it.Destino
    Escrever ''
    Escrever ">> $($it.Rotulo)"
    $args_ = @($it.Origem, $alvo) + $it.Filtro + @('/E', '/COPY:DAT', '/DCOPY:T', '/XJ', '/R:1', '/W:1',
              '/MT:8', '/NP', '/NFL', '/NDL', "/LOG+:$logRobo")
    if ($it.Excluir.Count) { $args_ += '/XD'; $args_ += $it.Excluir }
    & robocopy @args_ | Out-Null
    $codigo = $LASTEXITCODE
    $it | Add-Member -NotePropertyName Codigo -NotePropertyValue $codigo
    if ($codigo -ge 8) { Escrever "   robocopy codigo $codigo (houve falhas, veja robocopy.log)" 'Yellow' }
    else { Escrever "   ok (robocopy $codigo)" }
}

# ================================================================ 5. sistema
Titulo '5. EXPORTANDO CONFIGURACOES DO SISTEMA'
$sis = Join-Path $raizBackup '_sistema'
New-Item -ItemType Directory -Path $sis -Force | Out-Null

$chaves = 'HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Uninstall\*',
          'HKLM:\SOFTWARE\WOW6432Node\Microsoft\Windows\CurrentVersion\Uninstall\*',
          'HKCU:\SOFTWARE\Microsoft\Windows\CurrentVersion\Uninstall\*'
Get-ItemProperty $chaves -ErrorAction SilentlyContinue |
    Where-Object { $_.DisplayName -and -not $_.SystemComponent } |
    Select-Object DisplayName, DisplayVersion, Publisher, InstallDate |
    Sort-Object DisplayName -Unique |
    Export-Csv (Join-Path $sis 'programas-instalados.csv') -NoTypeInformation -Encoding UTF8 -Delimiter ';'
Escrever '  programas-instalados.csv'

if (Get-Command winget -ErrorAction SilentlyContinue) {
    winget export -o (Join-Path $sis 'winget-programas.json') --accept-source-agreements 2>&1 | Out-Null
    if (Test-Path (Join-Path $sis 'winget-programas.json')) {
        Escrever '  winget-programas.json  (reinstala tudo com: winget import -i winget-programas.json)'
    }
}

Get-CimInstance Win32_LogicalDisk -Filter 'DriveType=4' | Select-Object DeviceID, ProviderName |
    Export-Csv (Join-Path $sis 'unidades-de-rede.csv') -NoTypeInformation -Encoding UTF8 -Delimiter ';'
Get-Printer -ErrorAction SilentlyContinue | Select-Object Name, DriverName, PortName, Shared |
    Export-Csv (Join-Path $sis 'impressoras.csv') -NoTypeInformation -Encoding UTF8 -Delimiter ';'
Escrever '  unidades-de-rede.csv, impressoras.csv'

$wifi = Join-Path $sis 'wifi'
New-Item -ItemType Directory -Path $wifi -Force | Out-Null
if ($WifiComSenha) {
    netsh wlan export profile key=clear folder="$wifi" | Out-Null
    Escrever '  wifi\  (COM senhas em texto: guarde em local seguro)' 'Yellow'
} else {
    netsh wlan export profile folder="$wifi" | Out-Null
    Escrever '  wifi\  (sem senhas; use -WifiComSenha para incluir)'
}

$chaveOem = (Get-CimInstance SoftwareLicensingService -ErrorAction SilentlyContinue).OA3xOriginalProductKey
$so = Get-CimInstance Win32_OperatingSystem
$cs = Get-CimInstance Win32_ComputerSystem
@(
    "Computador : $env:COMPUTERNAME"
    "Modelo     : $($cs.Manufacturer) $($cs.Model)"
    "Windows    : $($so.Caption) build $($so.BuildNumber)"
    "Chave OEM  : $(if ($chaveOem) { $chaveOem } else { 'nao encontrada na BIOS (licenca digital ou volume)' })"
) | Out-File (Join-Path $sis 'licenca-windows.txt') -Encoding UTF8
Escrever '  licenca-windows.txt'

$bl = Get-BitLockerVolume -ErrorAction SilentlyContinue | Where-Object ProtectionStatus -eq 'On'
if ($bl) {
    Escrever ("  BitLocker ativo em: {0}. Salve a chave de recuperacao antes de formatar (aka.ms/myrecoverykey)." -f (($bl.MountPoint) -join ', ')) 'Yellow'
}

if (EhAdmin) {
    Escrever '  exportando drivers (alguns minutos)...'
    Export-WindowsDriver -Online -Destination (Join-Path $sis 'drivers') -ErrorAction SilentlyContinue | Out-Null
    Escrever '  drivers\  (reinstale com: pnputil /add-driver drivers\*.inf /subdirs /install)'
}

# ================================================================ 6. conferencia
Titulo '6. CONFERENCIA ARQUIVO POR ARQUIVO'
$relatorio = New-Object System.Collections.ArrayList
$tudoOk = $true
foreach ($it in $itens) {
    $copia = Listar (Join-Path $raizBackup $it.Destino) @()
    $faltando = New-Object System.Collections.ArrayList
    foreach ($k in $it.Mapa.Keys) {
        if (-not $copia.ContainsKey($k) -or $copia[$k] -ne $it.Mapa[$k]) { [void]$faltando.Add($k) }
    }
    $ok = $faltando.Count -eq 0
    if (-not $ok) { $tudoOk = $false }
    $cor = if ($ok) { 'Green' } else { 'Red' }
    Escrever ('  {0,-6} {1,-24} {2,8} de {3,8} arquivos' -f $(if ($ok) { 'OK' } else { 'FALTA' }),
              $it.Rotulo, ($it.Mapa.Count - $faltando.Count), $it.Mapa.Count) $cor
    foreach ($f in ($faltando | Select-Object -First 5)) { Escrever "           - $f" }
    if ($faltando.Count -gt 5) { Escrever "           ... e mais $($faltando.Count - 5)" }
    foreach ($f in $faltando) { [void]$relatorio.Add("$($it.Origem)\$f") }
}
if ($relatorio.Count) {
    $relatorio | Out-File (Join-Path $raizBackup 'arquivos-nao-copiados.txt') -Encoding UTF8
}

# ================================================================ resumo
Titulo 'RESULTADO'
$script:Linhas | Out-File (Join-Path $raizBackup 'LEIA-ME-backup.txt') -Encoding UTF8
if ($tudoOk -and -not $script:Problemas.Count) {
    Escrever 'BACKUP COMPLETO E CONFERIDO.' 'Green'
    Escrever "Pasta: $raizBackup"
    Escrever 'Antes de formatar, abra alguns arquivos no destino e siga o checklist do docs\07.'
} else {
    Escrever 'BACKUP INCOMPLETO - NAO FORMATE AINDA.' 'Red'
    if ($relatorio.Count) {
        Escrever "Arquivos que faltaram: $raizBackup\arquivos-nao-copiados.txt"
        Escrever 'Normalmente sao arquivos abertos: feche os programas e rode de novo com -Executar.'
    }
    $script:Problemas | ForEach-Object { Escrever "  - $_" }
    exit 1
}
