# 16. Verificar e religar os agentes do servidor

Rotina desligada não avisa ninguém: o Windows desliga tarefa em atualização,
alguém desliga "só para testar", e a automação para em silêncio. O
`/verificar-agentes` confere as rotinas do Agendador de Tarefas do
**KHAOSOMNI** e, se você mandar, religa as essenciais.

## Dentro do Claude

| Comando | O que faz |
|---|---|
| `/verificar-agentes` | Só verifica e entrega o relatório. Não muda nada. |
| `/verificar-agentes ativar` | Verifica e religa as rotinas **essenciais** que estiverem desligadas. |

O comando chama o `scripts/windows/verificar-agentes.ps1`, lê a saída e responde
com: veredito, tabela das essenciais (estado, última e próxima execução,
resultado), o que foi religado e as outras rotinas desligadas fora da lista.

## O que conta como "essencial"

A lista **fechada** `scripts/windows/rotinas-essenciais.txt`: um nome de tarefa
por linha, aceita curinga `*` e pasta (`\Argos\*`). Só o que casa com ela é
religado. Tarefa desligada fora da lista aparece no relatório e fica como está.

A lista tem os **nomes exatos** das 22 rotinas essenciais do KHAOSOMNI (do
relatório de 27/09 às 21h04) mais o agente `ARGOS - Cerebro no GitHub`. Evite
curinga: o servidor tem 7 lembretes `Argos - ...` desligados **de propósito**
(Alarme Live ×3, Defesa Shopee Intergrar 24-08, Lembrete Servidor 24-08,
Lembrete Terminar BIOS 26-08, Retomar Demanda Sol 26-08), e um `Argos*`
religaria todos. Com nome exato, o script também avisa quando uma rotina
**sumiu** (foi apagada ou renomeada).

Rotina nova que não pode parar? Acrescente o nome exato numa linha.

## O que o script confere

- rotina essencial **desligada**;
- ligada mas **sem próxima execução** (gatilho vencido). Rotina que roda por
  evento, como a `Argos - Tailscale no logon`, não tem horário e não entra nessa conta;
- **execuções perdidas** (máquina desligada ou dormindo no horário);
- **última execução com falha** (resultado diferente de `0x0`);
- ação que chama um **arquivo que não existe** mais.

## O que o `ativar` faz, e o que não faz

- Antes de religar, exporta o XML da tarefa para
  `C:\Argos-Backups\_checkpoints\<AAAA-MM-DD_HHmm>\`. Toda alteração tem volta.
- Depois, **lê o estado de volta**: só diz `[OK]` se o Windows confirmar.
- **Não religa** rotina cuja ação chama arquivo inexistente, porque ela passaria
  de "desligada" para "falhando todo dia". Conserte o arquivo primeiro.
- Nunca cria, apaga, roda nem altera gatilho ou ação de tarefa.
- Tarefa de outro usuário ou do SYSTEM pode exigir o Claude aberto como
  administrador. O relatório avisa quando for isso.

Assim como o `4-atualizar-claude.ps1`, ele **recusa rodar fora do KHAOSOMNI**
(as automações têm dono único). Para rodar em outra máquina, use o script direto
com `-Forcar`.

## Instalar no servidor

O comando funciona sozinho quando o Claude está aberto **nesta pasta do
repositório** (`.claude/commands/verificar-agentes.md`). Para ter o
`/verificar-agentes` em qualquer pasta do KHAOSOMNI:

```powershell
# a partir da raiz do repositório clonado no servidor
Copy-Item .claude\commands\verificar-agentes.md "$env:USERPROFILE\.claude\commands\"
New-Item -ItemType Directory "$env:USERPROFILE\Scripts" -Force | Out-Null
Copy-Item scripts\windows\verificar-agentes.ps1, scripts\windows\rotinas-essenciais.txt "$env:USERPROFILE\Scripts\"
```

O comando procura o script primeiro em `%USERPROFILE%\Scripts\` e depois em
`scripts\windows\` do repositório aberto.

## Direto no PowerShell, sem o Claude

```powershell
powershell -ExecutionPolicy Bypass -File .\verificar-agentes.ps1          # só verifica
powershell -ExecutionPolicy Bypass -File .\verificar-agentes.ps1 -Ativar  # religa as essenciais
```

O relatório sai na tela e numa cópia na Área de Trabalho. O código de saída é
`0` quando está tudo certo e `1` quando ficou algum problema pendente, então dá
para agendar o próprio verificador.
