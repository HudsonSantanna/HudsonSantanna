# Prompt para o Claude Code da máquina cheia

Copie **tudo** o que está entre as linhas e cole no Claude Code da `Hudson_Santana`.

---

```
Preciso liberar espaço no disco C: desta máquina. Contexto do que já foi feito hoje
(26/08), para você NÃO refazer:

ESTADO: C: com 101,6 GB, apenas ~3,5 GB livres (3,5%). Abaixo de 5% o Windows já
falha em update e arquivo temporário.

O HD externo está conectado nesta máquina agora. Nele, na pasta \Argos-Arquivo\,
estão 4 ferramentas JÁ PRONTAS E TESTADAS. Use-as, não escreva outras:

  Arquivar-Para-HD.ps1   move arquivo grande e parado para o HD.
                         COPIA -> confere por HASH -> só então apaga. Ensaio por padrão.
                         Já rodou: liberou 241 MB.

  Achar-Duplicatas.ps1   acha arquivos idênticos por HASH (nunca por nome) e apaga as
                         cópias, mantendo sempre um. Já rodou: 17 cópias, 719 MB.
                         Segunda passada não achou mais nada acima de 10 MB.

  Limpar-Sistema.ps1     temp, cache do Update, lixeira, hibernação, Windows.old.
                         Medido aqui: ~1.000 MB, tudo seguro. Esta máquina NÃO tem
                         hiberfil.sys nem Windows.old.

  Liberar-OneDrive.ps1   marca arquivo como "somente online" (mantém na nuvem).
                         🔴 FALHOU nesta máquina: 0 de 14, sem erro nenhum. Funciona
                         no servidor KHAOSOMNI. CAUSA NÃO IDENTIFICADA — se você
                         descobrir por quê, isso vale mais que o espaço.

O QUE FALTA DESCOBRIR: já recuperamos ~2 GB de lixo, mas o disco tem ~97 GB usados.
O resto são DADOS. Ninguém mapeou o disco inteiro ainda — só o perfil do usuário e o
OneDrive.

SUA TAREFA, nesta ordem:

1. MAPEIE o disco: as 20 maiores pastas de C:\ com tamanho, incluindo fora do perfil
   (Program Files, ProgramData, C:\ raiz, pontos de restauração via vssadmin).
   Mostre o mapa ANTES de propor qualquer coisa.

2. Rode Limpar-Sistema.ps1 -Confirmar (ganho garantido de ~1 GB, sem custo).

3. Com o mapa na mão, me diga onde estão os 97 GB e o que dá para tirar.

4. Só depois de eu aprovar item por item, mova o que eu autorizar para o HD usando
   Arquivar-Para-HD.ps1 -Destino <letra do HD>:\Argos-Arquivo -Confirmar

REGRAS QUE NÃO PODEM SER QUEBRADAS (são da casa, custaram caro):

- NUNCA mova ou apague sem me mostrar a lista antes. Ensaio primeiro, sempre.
- COPIA -> VERIFICA POR HASH -> só então apaga. Move-Item que falha no meio corrompe
  dos dois lados e a pessoa descobre meses depois.
- NUNCA toque em: Windows, Program Files, AppData, .git, node_modules, dist, build,
  win-unpacked, .codex, .claude, .agents, C:\Users\hudso\Argos-Cerebro, e
  C:\Users\hudso\Scripts. Arquivo grande e antigo NEM SEMPRE é lixo — hoje o script
  listou o runtime do Codex (236 MB) e o executável do Cérebro (188 MB) como
  "arquivo morto". Lista de exclusão FECHADA, nunca heurística.
- OneDrive: mover de lá APAGA DA NUVEM e de todas as máquinas. Só toque com
  autorização explícita minha, item por item.
- Todo .ps1 que você escrever ou alterar: rode o parser ANTES de entregar —
  [System.Management.Automation.Language.Parser]::ParseFile(...). E lembre que este
  é PowerShell 5.1: NÃO existe operador ternário (? :), ?? nem ?. (errei isso 3x hoje).
- .ps1 PRECISA de BOM UTF-8. .cmd NÃO PODE ter BOM. Regras opostas.
- Depois de qualquer escrita, LEIA DE VOLTA e prove. "Mandei fazer" não é "fez".

Comece pelo passo 1 (o mapa) e me mostre o resultado antes de agir.
```

---

## Depois que ele terminar

Traga o HD de volta e me diga o que ele achou — principalmente **o mapa do disco**.
Se o problema for dado de verdade (e não lixo), a conversa muda: uma máquina de
101 GB em 2026 pode simplesmente estar pequena demais para o uso, e aí é decisão de
hardware, não de limpeza.

Criado por Hudson Santana · Argos
