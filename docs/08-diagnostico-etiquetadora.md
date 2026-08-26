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
cd $env:USERPROFILE\Desktop
iwr 'https://raw.githubusercontent.com/HudsonSantanna/HudsonSantanna/main/scripts/windows/5-diagnostico-etiquetadora.ps1' -OutFile 5-diagnostico-etiquetadora.ps1 -UseBasicParsing
Unblock-File .\5-diagnostico-etiquetadora.ps1
powershell -ExecutionPolicy Bypass -File .\5-diagnostico-etiquetadora.ps1
```

> Enquanto o script ainda não estiver na `main`, troque `main` na URL pelo nome do
> branch — por exemplo `claude/etiquetadora-diagnostics-dnxnjd`.

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
| `-Saida` | Área de Trabalho | Caminho do relatório |

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
- **Cabeçalho `Access-Control-Allow-Private-Network`** na resposta do `/status`:
  sem ele o Chrome bloqueia a chamada, mesmo com o agente rodando perfeitamente
- **Driver `Generic / Text Only`**: sem ele não existe caminho ZPL/RAW
