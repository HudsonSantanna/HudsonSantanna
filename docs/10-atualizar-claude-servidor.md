# Atualizar o Claude Code do servidor (KHAOSOMNI)

O `4-atualizar-claude.ps1` cuida das quatro coisas que definem como o Claude
Code trabalha na máquina:

| Parte | Onde mora | O que é |
|---|---|---|
| **Comandos** | `~\.claude\commands\*.md` | as barras — `/conciliacao`, `/equipe-argos` |
| **Agentes** | `~\.claude\agents\*.md` | subagentes que o Claude chama sozinho |
| **Skills** | `~\.claude\skills\<nome>\SKILL.md` | as habilidades que disparam pela descrição |
| **Hooks** | chave `hooks` do `~\.claude\settings.json` | comandos que o Claude roda em eventos |

> ⚠️ **As seis "Hooks" do Cérebro** (`hook-radar`, `hook-cacador`, `hook-motor`,
> `hook-vigia`, `hook-vitrine`, `hook-escoador`) **não são hooks do
> `settings.json`** — são *skills* com esse nome. O relatório separa as duas
> coisas, para você não procurar no lugar errado.

## O que o script não faz

- **Não apaga nada.** A cópia é `robocopy` sem `/MIR`; arquivo que só existe no
  servidor é listado como `SO AQUI (preservado)` e fica onde está.
- **Não toca em credencial.** `.credentials.json` e `.claude.json` não entram na
  conta. Nem sessões, `projects`, `plugins` ou o venv de `security`.
- **Não sobrescreve o `settings.json` inteiro.** Troca **apenas** a chave
  `hooks`; `permissions` e o resto do arquivo continuam como estavam.
- **Não grava sem você mandar.** Sem `-Executar` ele só lê e mostra.

## Passo 1 — Ver o que está instalado (só lê)

No **KHAOSOMNI**:

```powershell
powershell -ExecutionPolicy Bypass -File .\4-atualizar-claude.ps1
```

Sai um relatório na Área de Trabalho com o inventário (comandos, agentes,
skills, hooks) e uma **conferência** que aponta, por exemplo:

- pasta de skill sem `SKILL.md` — o Claude simplesmente não carrega
- `SKILL.md` sem `description`, ou com `description` curta demais — a skill
  nunca dispara sozinha
- `name` do frontmatter diferente do nome da pasta/arquivo
- comando sem `description` — não aparece no `/help`
- o mesmo nome existindo como skill **e** como comando (o `/nome` fica ambíguo)
- hook chamando um `.ps1` que não existe mais na máquina
- `settings.json` com JSON inválido — nesse caso o Claude ignora o arquivo
  inteiro, hooks e permissões junto

## Passo 2 — Comparar com a origem da atualização

A origem é a pasta `claude` do pendrive do kit do servidor, o share, ou
qualquer cópia do `.claude` que você queira usar como referência:

```powershell
.\4-atualizar-claude.ps1 -Origem "D:\ARGOS-SERVIDOR\dados\claude"
```

Cada arquivo é comparado por **SHA-256**, e sai classificado:

```
NOVO       skills\conciliacao\SKILL.md
DIFERENTE  commands\equipe-argos.md
SO AQUI    skills\espiao\SKILL.md   (preservado)
```

Ainda não gravou nada. Leia a lista antes de seguir.

## Passo 3 — Aplicar

```powershell
.\4-atualizar-claude.ps1 -Origem "D:\ARGOS-SERVIDOR\dados\claude" -Executar
```

Antes de escrever qualquer coisa, tudo que vai ser tocado é copiado para

```
C:\Argos-Backups\_checkpoints\<AAAA-MM-DD_HHmm>\
```

Deu errado? A volta é copiar de lá para dentro do `.claude` de novo.

Depois de aplicar, abra o Claude Code e rode `/help` (os comandos aparecem?) e
`/doctor` (a configuração carregou?).

## A trava de dono

O script **recusa rodar fora do KHAOSOMNI**:

```
PARE: esta maquina e NOTEBOOK-HUDSON, nao o servidor KHAOSOMNI.
```

É proposital — as automações têm dono único, e aplicar a mesma atualização nas
duas máquinas deixa as duas com configurações divergentes, em silêncio. Se for
mesmo no notebook que você quer rodar, repita com `-Forcar`.

## Parâmetros

| Parâmetro | Padrão | Para que serve |
|---|---|---|
| `-Origem` | — | Pasta com o `.claude` de referência. Sem ela, o script só inventaria |
| `-Executar` | desligado | Grava de verdade. Sem isso, só simula |
| `-Forcar` | desligado | Deixa rodar fora do `KHAOSOMNI` |
| `-Claude` | `~\.claude` | Outra configuração, se você tiver mais de uma |
| `-Servidor` | `KHAOSOMNI` | Nome da máquina que a trava de dono aceita |
| `-Checkpoints` | `C:\Argos-Backups\_checkpoints` | Onde fica a cópia de segurança |
| `-Log` | Área de Trabalho | Caminho do relatório |

## Se der "não é possível carregar o arquivo... não está assinado digitalmente"

O `-ExecutionPolicy Bypass` do comando já contorna. Se ainda reclamar:

```powershell
Get-ChildItem .\*.ps1 | Unblock-File
```
