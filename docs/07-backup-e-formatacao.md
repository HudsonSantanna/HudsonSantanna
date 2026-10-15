# Backup completo, duplicados e formatação

Roteiro para quando a máquina vai ser formatada: liberar espaço, conferir o
acesso ao servidor, copiar tudo que importa para a unidade `E:`, limpar os
duplicados **na cópia** e só então formatar.

> Regra de ouro: **nada é apagado da máquina antes de o backup estar conferido.**
> Duplicados se removem da cópia no `E:`, nunca do original antes da formatação.

Abra o **PowerShell como administrador** (Windows + X → **Terminal (Admin)**) e
vá até a pasta dos scripts, como no [guia de manutenção](06-manutencao-windows.md).

## Ordem

| # | Script | Para quê |
|---|--------|----------|
| 1 | `1-diagnostico.ps1` | Ver o que ocupa espaço e se o disco está saudável |
| 2 | `2-limpeza.ps1 -Executar` | Recuperar os ~10 GB de caches, temporários e hibernação |
| 3 | `5-backup-formatacao.ps1` | Testar o servidor, copiar tudo para `E:` e conferir |
| 4 | `4-duplicados.ps1` | Tirar os duplicados **da cópia** no `E:` |
| 5 | Checklist abaixo | Conferir antes de formatar |

## 1 e 2 — Diagnóstico e espaço

```powershell
.\1-diagnostico.ps1
.\2-limpeza.ps1                                           # simula
.\2-limpeza.ps1 -Executar -EsvaziarLixeira -DesativarHibernacao
```

Temporários, cache do Windows Update e `hiberfil.sys` costumam somar 10 GB ou
mais. Se ainda faltar espaço, mova pastas grandes com o `3-mover-para-hd.ps1`.

## 3 — Servidor e backup para a unidade E:

Primeiro **simule**. Troque o caminho pelo compartilhamento real do servidor da
KhaosOmni:

```powershell
.\5-backup-formatacao.ps1 -Servidor "\\khaosomni\backup"
```

A simulação não copia nada e mostra:

- **unidades de rede mapeadas** e para onde cada uma aponta (inclusive se o `E:`
  é o servidor ou um HD externo)
- se o servidor **responde**, se a **porta SMB 445** está aberta e se dá para
  **ler e gravar** no compartilhamento
- o espaço livre no `E:` e o tamanho do backup
- pastas fora do seu perfil (ex.: `C:\Projetos`, `D:\Fotos`) que **não** entram
  sozinhas: inclua com `-Extras`

Se o servidor recusar o acesso, mapeie a unidade com usuário e senha:

```powershell
net use E: \\khaosomni\backup /user:DOMINIO\seu.usuario /persistent:yes
```

Tudo certo? **Feche navegadores e o Outlook** e rode de verdade:

```powershell
.\5-backup-formatacao.ps1 -Servidor "\\khaosomni\backup" -Executar -Extras "C:\Projetos"
```

### O que vai para o backup

`E:\Backup-<COMPUTADOR>-<data>\`

| Pasta | Conteúdo |
|-------|----------|
| `Usuario\` | Área de Trabalho, Documentos, Imagens, Vídeos, Músicas, Downloads, Favoritos e demais pastas do seu perfil |
| `Navegadores\` | Perfis do Chrome, Edge, Brave e Firefox (favoritos, senhas salvas, extensões), sem os caches |
| `Outlook\` | Arquivos `.pst` e assinaturas |
| `Extras\` | O que você passou em `-Extras` |
| `_sistema\` | Lista de programas, `winget-programas.json`, drivers, impressoras, unidades de rede, perfis Wi-Fi, chave OEM do Windows |
| `LEIA-ME-backup.txt` | Relatório completo da execução |
| `arquivos-nao-copiados.txt` | Só aparece se faltou algo |

O script confere **arquivo por arquivo** (caminho e tamanho). Se terminar com
`BACKUP INCOMPLETO`, normalmente são arquivos que estavam abertos: feche os
programas e rode o mesmo comando de novo. O robocopy só copia o que faltou.

Opções:

| Parâmetro | O que faz |
|-----------|-----------|
| `-Destino "F:\"` | Usa outra unidade (padrão `E:\`) |
| `-Extras "C:\A","D:\B"` | Inclui pastas fora do perfil |
| `-IncluirOneDrive` | Copia também o OneDrive (por padrão fica de fora, já está na nuvem) |
| `-WifiComSenha` | Exporta as senhas Wi-Fi em texto. **Não use se o `E:` for um servidor compartilhado** |

## 4 — Duplicados (na cópia)

```powershell
# relatório (abre no Excel): mostra qual cópia fica e quais sobram
.\4-duplicados.ps1 -Pasta "E:\Backup-PC-20261015"

# mover as sobras para uma quarentena
.\4-duplicados.ps1 -Pasta "E:\Backup-PC-20261015" -Quarentena "E:\Duplicados"
```

Ele compara pelo conteúdo (SHA-256), não pelo nome: `foto (1).jpg` e
`foto - Cópia.jpg` iguais à original são detectadas; arquivos com o mesmo nome
mas conteúdo diferente **não**. De cada grupo fica a cópia de caminho mais curto.
Confira a quarentena e depois apague a pasta, ou use `-Apagar` direto.

Por padrão ignora `Windows`, `Program Files`, `ProgramData`, `AppData`,
`node_modules` e `.git`, e arquivos menores que 100 KB (`-MinimoKB` muda isso).

## 5 — Checklist antes de formatar

- [ ] `5-backup-formatacao.ps1` terminou com **BACKUP COMPLETO E CONFERIDO**
- [ ] Abri alguns arquivos direto do `E:` (foto, planilha, PDF) e abrem normalmente
- [ ] Senhas: o navegador está sincronizado com a conta Google/Microsoft, ou exportei as senhas
- [ ] Contas e licenças anotadas: Office, antivírus, programas pagos (veja `_sistema\programas-instalados.csv`)
- [ ] Chave de recuperação do **BitLocker** salva, se o script avisou que está ativo
- [ ] Autenticador (2FA) e certificados digitais (e-CNPJ, e-CPF, token) com cópia ou acesso por outro aparelho
- [ ] WhatsApp Desktop, Teams e outros apps com histórico local: backup feito pelo próprio app
- [ ] Pendrive de instalação do Windows pronto (ou imagem do Clonezilla, ver [docs 02](02-criar-imagem-mestre.md))
- [ ] Driver de rede/Wi-Fi à mão (`_sistema\drivers`), para não ficar sem internet depois

## Depois de formatar

```powershell
# programas (os que existem no winget)
winget import -i "E:\Backup-PC-20261015\_sistema\winget-programas.json"

# drivers
pnputil /add-driver "E:\Backup-PC-20261015\_sistema\drivers\*.inf" /subdirs /install

# Wi-Fi (um por arquivo)
netsh wlan add profile filename="E:\Backup-PC-20261015\_sistema\wifi\Wi-Fi-MinhaRede.xml"
```

Arquivos pessoais: copie de volta de `Usuario\` para as pastas do novo perfil.
Navegadores: prefira entrar na conta e sincronizar; se não usava sincronização,
copie a pasta do perfil de volta **com o navegador fechado**.
