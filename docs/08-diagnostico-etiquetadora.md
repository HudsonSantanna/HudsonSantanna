# Diagnóstico da etiquetadora (Argos Estoque)

Quando a etiqueta não sai, a pergunta não é "o que está quebrado?" — é **em qual
dos seis elos parou**. O script `scripts/windows/5-diagnostico-etiquetadora.ps1`
percorre os seis na ordem certa e escreve um relatório.

Ele é **somente leitura**: não instala, não renomeia, não compartilha, não limpa
fila e não encosta em impressora nenhuma — inclusive a **BIXOLON FISCAL do
UpSeller**, que fica intocada.

## A ordem dos elos

| # | Elo | O que o script olha |
|---|---|---|
| 1 | Dispositivo USB | BIXOLON XD3-40t (`VID_1504`) e a pistola C3TECH LB-50BK (`VID_0483&PID_0011`) presentes agora |
| 2 | Spooler | serviço rodando e modo de inicialização |
| 3 | Impressoras | driver, porta, compartilhamento, padrão do Windows, status |
| 4 | Filas | job preso (job preso = não imprimiu) |
| 5 | Agente ArgosPrint | processo, pasta, `impressora_argos.txt`, `catalogo_argos.json`, porta 9110 e `/status` |
| 6 | Navegador | o que dá para ler do registro; a prova mesmo é no Chrome |

A causa mais comum é a mais boba: o **teste 1 responde em 2 segundos**. Impressora
desligada ou cabo USB fora derruba tudo o que vem depois.

## Como rodar

No **PowerShell** da máquina do estoque (não precisa ser administrador):

```powershell
[Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12
$pasta = [Environment]::GetFolderPath('Desktop')
if (-not $pasta -or -not (Test-Path -LiteralPath $pasta)) { $pasta = $env:USERPROFILE }
Set-Location -LiteralPath $pasta
iwr 'https://raw.githubusercontent.com/HudsonSantanna/HudsonSantanna/main/scripts/windows/5-diagnostico-etiquetadora.ps1' -OutFile 5-diagnostico-etiquetadora.ps1 -UseBasicParsing
Unblock-File .\5-diagnostico-etiquetadora.ps1
powershell -ExecutionPolicy Bypass -File .\5-diagnostico-etiquetadora.ps1
```

> **Não troque as duas primeiras linhas por `cd $env:USERPROFILE\Desktop`.** Com
> OneDrive ligado essa pasta não existe — a Área de Trabalho vira
> `...\OneDrive\Área de Trabalho`. O `cd` falha, o download cai em outra pasta e o
> `-File .\5-diagnostico-etiquetadora.ps1` da última linha não acha o arquivo. As
> linhas acima perguntam ao Windows onde a Área de Trabalho está de verdade e caem
> no perfil do usuário se nem isso responder.

> Enquanto o script ainda não estiver na `main`, troque `main` na URL pelo nome do
> branch — por exemplo `claude/etiquetadora-diagnostics-j5w35f`.

Roda em segundos. Ao final salva na Área de Trabalho um arquivo
`diagnostico-etiquetadora-AAAAMMDD-HHMM.txt`.

> A Área de Trabalho com OneDrive não é `%USERPROFILE%\Desktop` — é
> `...\OneDrive\Área de Trabalho`. O script pergunta ao Windows onde ela está de
> verdade; se nem assim conseguir gravar, salva na pasta `%TEMP%` e diz na tela
> onde ficou.

### Parâmetros

| Parâmetro | Padrão | Para que serve |
|---|---|---|
| `-Porta` | `9110` | Porta do agente ArgosPrint, se um dia mudar |
| `-Origem` | `https://estoque.argos.app.br` | Endereço do Argos Estoque, usado no preflight PNA do elo 5 |
| `-Saida` | Área de Trabalho | Caminho do relatório |

Se o endereço do Argos Estoque não for o do padrão, passe o de verdade — senão o
teste de PNA pergunta por uma origem que o agente não conhece:

```powershell
powershell -ExecutionPolicy Bypass -File .\5-diagnostico-etiquetadora.ps1 -Origem 'https://SEU.ENDERECO'
```

## Como ler o relatório

Cada linha vem marcada:

- `[OK]` — o elo respondeu
- `[FALTA]` — o elo **não** respondeu; entra na lista numerada do RESUMO
- `[!]` — aviso, ou **teste que não foi feito** (cmdlet indisponível nesta versão
  do Windows). Teste não realizado **não** é falta — o script diz isso com todas
  as letras em vez de acusar aparelho ausente

Vá ao **RESUMO** no fim do arquivo: ele lista o que faltou **na ordem dos elos**.
Resolva de cima para baixo — o primeiro item costuma explicar todos os outros.

## O que o script não prova

O elo 6. O PowerShell não aplica *Private Network Access*: ele prova que o agente
responde, não que o Chrome deixa o site chamar o agente. A prova de verdade é no
Chrome logado no Argos Estoque (F12 → Console):

```js
await ArgosPrint.disponivel()      // tem que dar true
```

e o selo verde **"Etiquetadora conectada"** aparecendo na tela.

## Dar nome próprio às duas BIXOLON

As duas se chamam `BIXOLON XD3-40t - BPL` e `BIXOLON XD3-40t - BPL-Z #2` — só
diferem por um sufixo de driver. Na hora do `Ctrl+P` a escolha vira palpite, e a
etiqueta sai na impressora errada. O `scripts/windows/7-nomear-impressoras.ps1`
troca esses nomes por `Codigo de Barra` e `Etiqueta Fiscal`.

**Identifique antes de renomear.** Sem número de série, o Windows só distingue as
duas pela porta USB — e porta USB troca de lugar. Nomear por palpite grava o erro
em vez de corrigi-lo.

```powershell
# 1. manda um papel por fila, com o nome da fila impresso. Não altera nada.
powershell -ExecutionPolicy Bypass -File .\7-nomear-impressoras.ps1 -Identificar

# 2. com os dois papéis na mão, renomeia
powershell -ExecutionPolicy Bypass -File .\7-nomear-impressoras.ps1 `
    -DeCodigoDeBarra 'BIXOLON XD3-40t - BPL-Z #2' `
    -DeEtiquetaFiscal 'BIXOLON XD3-40t - BPL' -Confirmar
```

Sem `-Confirmar` ele só mostra o plano. Recusa renomear fila com job pendente
(renomear aí perde o trabalho de alguém) e recusa dois nomes novos iguais.

Renomear troca só o rótulo, **não** o caminho: a porta USB continua a mesma. Se
alguém mudar os cabos de porta, o nome passa a mentir — identifique de novo.

Depois disso o `6-configurar-etiquetadora.ps1` fica direto, e a proteção da fiscal
passa a funcionar sozinha, porque `Etiqueta Fiscal` casa com a regra do nome:

```powershell
powershell -ExecutionPolicy Bypass -File .\6-configurar-etiquetadora.ps1 -ImpressoraEstoque 'Codigo de Barra'
```

## Configurar (depois de ler o relatório)

O `scripts/windows/6-configurar-etiquetadora.ps1` monta o caminho ZPL/RAW: limpa
job preso, cria a fila `Generic / Text Only` na porta da BIXOLON de estoque,
compartilha como `ARGOS - Codigo Estoque`, grava o `impressora_argos.txt` ao lado
do `ArgosPrint.exe`, reinicia o agente e manda uma etiqueta de teste.

**Por padrão ele só mostra o plano.** Para aplicar, `-Confirmar`. Precisa de
PowerShell como Administrador.

```powershell
[Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12
$pasta = [Environment]::GetFolderPath('Desktop')
if (-not $pasta -or -not (Test-Path -LiteralPath $pasta)) { $pasta = $env:USERPROFILE }
Set-Location -LiteralPath $pasta
iwr 'https://raw.githubusercontent.com/HudsonSantanna/HudsonSantanna/main/scripts/windows/6-configurar-etiquetadora.ps1' -OutFile 6-configurar-etiquetadora.ps1 -UseBasicParsing
Unblock-File .\6-configurar-etiquetadora.ps1
powershell -ExecutionPolicy Bypass -File .\6-configurar-etiquetadora.ps1
```

### A impressora fiscal não é tocada

Isto não é uma promessa de comportamento, é como o script foi construído: ele
**não altera nenhuma impressora que já exista** na máquina. Tudo o que escreve
acontece numa fila **nova**, criada por ele. A única exceção é apagar job preso —
e só em fila BIXOLON que não seja fiscal.

A trava importa porque as duas BIXOLON desta instalação **não têm número de
série** (uma reporta `0000000000000001`, a outra nenhum). Sem serial, o Windows
só as distingue pela porta USB — e porta USB troca de lugar quando alguém muda o
cabo ou liga as duas numa ordem diferente. Script que "adivinha" qual é qual
acaba reconfigurando a fiscal no meio do despacho.

Se o script achar mais de uma BIXOLON não-fiscal, ele **para e pergunta** em vez
de escolher. E se a porta indicada for a da fiscal, ele recusa.

### Se a etiqueta de teste sair na impressora errada

Rode de novo com a outra porta:

```powershell
powershell -ExecutionPolicy Bypass -File .\6-configurar-etiquetadora.ps1 -Confirmar -PortaUsb USB002
```

Só a fila nova muda de porta. É reversível quantas vezes precisar, e nenhuma
impressora existente entra na jogada.

### Parâmetros

| Parâmetro | Padrão | Para que serve |
|---|---|---|
| `-Confirmar` | desligado | Sem ele, só mostra o plano |
| `-ImpressoraEstoque` | descoberta | Nome da impressora existente cuja porta é a do estoque |
| `-Proteger` | — | Nomes que nunca devem ser tocados, além da fiscal e da padrão |
| `-PortaUsb` | descoberta | Força a porta (`USB001`, `USB002`) |
| `-FilaArgos` | `ARGOS - Codigo Estoque` | Nome e compartilhamento da fila |
| `-SemTeste` | desligado | Não manda a etiqueta de teste |

### Depois

Confira com os olhos que a etiqueta `ARGOS TESTE` saiu na etiquetadora do
estoque, prove o elo 6 no Chrome e rode o `5-diagnostico-etiquetadora.ps1` de
novo para o relatório final.

## O caso da HUDSONINTEGRAR (26/08/2026)

Vale como referência porque as duas falhas envolvidas **não dão erro nenhum**.

O Argos Estoque exibia o selo verde *Etiquetadora conectada* e, a cada clique,
respondia `✅ 2 etiqueta(s) impressa(s) na etiquetadora`. Nada saía. O agente
estava certo, o navegador estava certo, e mesmo assim não havia papel.

A lista de impressoras contava a história:

```
ARGOS - Codigo Estoque             porta=LPT3:    driver=BIXOLON XD3-40t - BPL-Z
BIXOLON XD3-40t - BPL-Z            porta=USB002   driver=BIXOLON XD3-40t - BPL-Z
BIXOLON XD3-40t - BPL-Z #2         porta=LPT3:    driver=BIXOLON XD3-40t - BPL-Z
BIXOLON XD3-40t - BPL-Z (Copiar 1) porta=USB005   driver=BIXOLON XD3-40t - BPL-Z
BIXOLON XD3-40t - BPL-Z (Copiar 2) porta=USB001   driver=BIXOLON XD3-40t - BPL-Z
```

**A fila existia e apontava para `LPT3:`** — uma porta paralela que a máquina não
tem. Fila em porta morta aceita o trabalho, o spooler não reclama, o agente
recebe OK e o site anuncia sucesso. O papel simplesmente não existe em lugar
nenhum. Só duas das cinco portas tinham impressora ligada: `USB001` e `USB002`;
`LPT3:` e `USB005` eram restos de instalações antigas.

**E o driver era o da BIXOLON, não o `Generic / Text Only`.** Mesmo na porta
certa, o ZPL cru teria passado por um driver que tenta renderizá-lo como
documento — etiqueta em branco ou embolada.

Duas falhas somadas, nenhuma delas com mensagem de erro. Por isso o
`6-configurar-etiquetadora.ps1` hoje **recusa** porta sem impressora ligada (ele
lê o `instance id` de cada `USBPRINT`, que termina no nome da porta) e corrige o
driver de fila que já existe, não só a porta.

A correção final foi uma linha:

```powershell
.\6-configurar-etiquetadora.ps1 -PortaUsb USB002 -Confirmar
```

### O que sobrou para limpar

`BIXOLON XD3-40t - BPL-Z #2` (`LPT3:`) e `BIXOLON XD3-40t - BPL-Z (Copiar 1)`
(`USB005`) são filas órfãs apontando para portas mortas. Elas não quebram nada
sozinhas, mas é delas que vem a confusão: aparecem no `Ctrl+P` com nome quase
idêntico ao das boas, e trabalho enviado para elas some calado. Remover é
decisão de quem opera — confira antes que nenhuma tem job pendente.

## Antes de instalar qualquer coisa

**Mande o arquivo inteiro.** Ele foi feito para caber numa mensagem e responder
de uma vez o que normalmente leva dez idas e vindas. Instalar, recompartilhar ou
reinstalar driver antes de ler o relatório costuma criar um problema novo em cima
do antigo.

## Detalhes que o relatório checa e passam batido no olho

- **Renomeação pendente**: se a máquina já foi renomeada mas ainda não reiniciou,
  o relatório avisa qual nome ela vai assumir — confira a grafia **antes** do
  reboot, porque o compartilhamento `\\localhost\...` do agente depende dele
- **`impressora_argos.txt` vazio** conta como ausente: o agente cai no padrão
  `\\localhost\BXS`, que nesta máquina está errado — aqui a fila é
  `ARGOS - Codigo Estoque`
- **Cabeçalho `Access-Control-Allow-Private-Network`**: sem ele o Chrome bloqueia
  a chamada, mesmo com o agente rodando perfeitamente. Esse cabeçalho só aparece
  na resposta ao **preflight** (um `OPTIONS` com
  `Access-Control-Request-Private-Network: true`), nunca num `GET` comum — por
  isso o script refaz o preflight em vez de cobrar o cabeçalho na resposta do
  `/status`. Agente que não responde a `OPTIONS` fora do navegador vira
  `[!] TESTE NAO REALIZADO`, não `[FALTA]`
- **Driver `Generic / Text Only`**: sem ele não existe caminho ZPL/RAW
