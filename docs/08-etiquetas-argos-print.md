# 8. Estação de etiquetas: Bixolon XD3-40t + Argos Print

Roteiro para deixar a **`HUDSONINTEGRAR`** imprimindo etiqueta de código de
barras direto do Argos Estoque, sem encostar na Bixolon **fiscal** do UpSeller
que já existe naquela máquina.

Tudo aqui vem das notas do Cérebro — não é suposição:

- `05-Recursos/ARGOS PRINT - agente local de etiqueta (imprimir direto do sistema).md`
- `05-Recursos/IMPRESSORA ETIQUETAS - Bixolon XD3-40t (ZPL) Argos Estoque.md`

A máquina alcança essas notas pelo próprio cérebro em rede
(`\\KHAOSOMNI\ArgosCerebro$`). **Elas são a fonte da verdade**; este arquivo é
o resumo operacional.

## As três regras que já custaram caro

1. **O agente roda NA máquina da impressora.** Ele escuta só em `127.0.0.1`
   de propósito — nunca foi feito para imprimir pela rede. Decisão de 05/08:
   abrir o Argos Estoque na máquina onde a Bixolon está. `\\HUDSON_SANTANA\BXS`
   e `\\HUDSONINTEGRAR` deram "acesso negado" porque o caminho estava errado,
   não porque faltava permissão.
2. **O ShareName não é sempre `BXS`.** Na `HUDSONINTEGRAR` a fila de estoque é
   **`ARGOS - Codigo Estoque`**, justamente porque lá já existe a Bixolon
   **FISCAL do UpSeller**, que **não pode** ser renomeada nem desinstalada.
3. **Antes de suspeitar de driver, buffer ou script, confira se o dispositivo
   USB está presente.** Duas vezes o "não imprime" era a impressora fisicamente
   ausente ou em outra máquina. O teste responde em 2 segundos.

## Como o conjunto funciona

```
navegador (softwareargos.org)  →  botão 🏷️
        ▼
http://127.0.0.1:9110/imprimir?codigos=ARG004232&qtd=2
        ▼  ArgosPrint.exe (agente local, console minimizado)
ZPL cru por canal RAW  →  \\localhost\ARGOS - Codigo Estoque
        ▼
BIXOLON XD3-40t desenha o Code128 ela mesma
```

Endpoints: `GET /status` → `{ok, impressora, catalogo, catalogo_origem}` e
`GET /imprimir?codigos=<COD>&qtd=<N>`.

## Ficha técnica

| Item | Valor |
|------|-------|
| Impressora | BIXOLON **XD3-40t** — térmica 4", 203 dpi (8 pontos/mm) |
| Linguagem | **ZPL II** (Smart Switch); a impressora desenha o Code128 |
| Driver no Windows | **Generic / Text Only**, DataType **RAW** |
| Mídia | **transferência (ribbon)** → `^MTT`; sensor de gap `^MNY` |
| Etiqueta | **50 × 30 mm**, gap 2 mm, **2 colunas** (liner ~102 mm) |
| ZPL | `^PW816` · `^LL240` · coluna 1 em x=16, coluna 2 em x=432 |
| Agente | ArgosPrint **1.1**, `.exe` PyInstaller (~7,5 MB), sem Python |
| Porta | `127.0.0.1:9110` — nunca `0.0.0.0` |
| Catálogo | `catalogo_argos.json` (5.338 variações) |
| Leitor | Pistola **C3TECH LB-50BK** — `HID\VID_0483&PID_0011` |

O papel configurado no driver é irrelevante: no caminho ZPL/RAW o page setup
é ignorado.

## O destino da impressão é configurável (não recompile nada)

O `etiquetas_bixolon.py` resolve o destino **na hora de cada envio**, nesta
ordem:

```
1. variável de ambiente  ARGOS_IMPRESSORA
2. arquivo  impressora_argos.txt   (na pasta do .exe)     ← use este
3. padrão embutido       \\localhost\BXS
```

Então, na `HUDSONINTEGRAR`, basta criar ao lado do `ArgosPrint.exe`:

```
impressora_argos.txt
    \\localhost\ARGOS - Codigo Estoque
```

Trocar de impressora **não exige reiniciar o agente**. Cuidado com o BOM do
Bloco de Notas — já foi testado e é tolerado, mas prefira salvar como UTF-8
sem BOM.

Mesma lógica no catálogo: um `catalogo_argos.json` **na pasta do executável**
vence o embutido, para que "cadastrou produto novo? reexporte o catálogo"
continue valendo sem recompilar. O `/status` devolve `catalogo_origem`
(`externo` / `embutido`) para conferir.

## Instalação na HUDSONINTEGRAR

1. **Fotografe o estado atual** antes de mexer:
   `powershell -ExecutionPolicy Bypass -File .\scripts\windows\4-etiquetas-argos.ps1`
   Guarde o relatório: é a prova de como a fila fiscal estava.
2. **Confirme a Bixolon de etiqueta no USB da máquina** (`VID_1504`). Se ela
   não estiver plugada aí, pare — o resto não adianta.
3. **Crie a fila** com driver **Generic / Text Only** na porta USB da XD3-40t.
   Não reaproveite nem duplique a fila fiscal.
4. **Compartilhe** a fila nova como **`ARGOS - Codigo Estoque`**. A fiscal do
   UpSeller fica como está — nome, compartilhamento e condição de padrão do
   Windows intocados.
5. **Copie o kit** do pendrive (`KIT-UERICK`): `ArgosPrint.exe`,
   `catalogo_argos.json` e o `impressora_argos.txt` apontando para o share do
   passo 4.
6. **Atalho na pasta Inicializar** (`shell:startup`), para o agente subir
   minimizado com o Windows. Também há o `Imprimir-Etiqueta.cmd` para quem
   preferir sem navegador (bipa a pistola → quantas → imprime).
7. **SmartScreen:** `.exe` sem assinatura mostra "protegeu o computador" →
   *Mais informações* → *Executar assim mesmo*.
8. **Pistola:** ligue e teste. Ela é um teclado; precisa mandar **Enter** no
   fim. Sem isso, configure o sufixo CR lendo o código do manual dela.

## Ordem oficial de diagnóstico

Sempre nesta sequência — a causa mais comum é a mais boba:

| # | Teste | Como |
|---|-------|------|
| 1 | Dispositivo USB presente | `Get-PnpDevice -PresentOnly` procurando `VID_1504` |
| 2 | Spooler rodando | `Get-Service Spooler` |
| 3 | Compartilhamento existe | `Get-Printer \| Where-Object Shared` |
| 4 | Agente no ar | `http://127.0.0.1:9110/status` |
| 5 | Navegador alcança o agente | selo "🖨️ Etiquetadora conectada" no site |
| 6 | Fila sem job preso | `Get-PrintJob` — já houve job travado desde dias antes |

O script `4-etiquetas-argos.ps1` roda de 1 a 6 e entrega o resultado pronto.

## O header que faz tudo funcionar

Chrome e Edge aplicam **Private Network Access**: um site HTTPS público
(`softwareargos.org`) falando com `127.0.0.1` só passa se a resposta trouxer

```
Access-Control-Allow-Private-Network: true
```

CORS normal **não basta**. Isso já quase foi entregue quebrado: PowerShell e
`curl` provam que o servidor responde, **não** que o navegador deixa chamar.

> **Teste de integração com navegador tem que ser NO NAVEGADOR.**

## Testes de aceitação

- [ ] `Get-PnpDevice` mostra a XD3-40t presente (`VID_1504`).
- [ ] `http://127.0.0.1:9110/status` responde `200`, com
      `impressora: \\localhost\ARGOS - Codigo Estoque` e
      `catalogo_origem: externo`.
- [ ] `/imprimir?codigos=<código real>&qtd=2` → `{ok:true, etiquetas:2}`, a
      fila esvazia e sai etiqueta nítida, parando no picote.
- [ ] **No Chrome logado no sistema**, o selo "🖨️ Etiquetadora conectada"
      aparece verde e o botão 🏷️ imprime sem abrir diálogo.
- [ ] A pistola lê a etiqueta impressa e o código chega ao sistema com Enter.
- [ ] Uma nota fiscal de teste continua saindo na Bixolon fiscal.
- [ ] A impressora **padrão** do Windows continua sendo a fiscal.
- [ ] Depois de reiniciar, o agente volta sozinho.
- [ ] Nenhuma etiqueta em branco: número ímpar de códigos repete o último para
      fechar a linha de 2 colunas.

## Comando para o Claude Code da HUDSONINTEGRAR

```
/cerebro Ative o cérebro e leia, antes de qualquer coisa, as notas
"ARGOS PRINT - agente local de etiqueta (imprimir direto do sistema)" e
"IMPRESSORA ETIQUETAS - Bixolon XD3-40t (ZPL) Argos Estoque" em 05-Recursos.

Tarefa nesta máquina (HUDSONINTEGRAR): instalar a impressora de etiquetas
BIXOLON XD3-40t + o agente ArgosPrint e configurar a pistola de código de
barras, SEM tocar na Bixolon FISCAL do UpSeller que já existe aqui — ela não
pode ser renomeada, descompartilhada nem deixar de ser a impressora padrão.

Pontos que as notas já resolveram e que você NÃO deve redescobrir:
- o agente roda NESTA máquina e escuta só em 127.0.0.1:9110; ele nunca
  imprime pela rede;
- aqui o ShareName da fila de estoque é "ARGOS - Codigo Estoque", não "BXS";
- o destino é configurável: crie impressora_argos.txt na pasta do
  ArgosPrint.exe com \\localhost\ARGOS - Codigo Estoque — não recompile nada;
- driver "Generic / Text Only" com DataType RAW; o ZPL é que desenha o
  Code128 (50x30mm, gap 2mm, 2 colunas, ^MTT com ribbon);
- catalogo_argos.json na pasta do .exe vence o catálogo embutido;
- a pistola C3TECH LB-50BK é um teclado e precisa mandar Enter no fim.

Faça nesta ordem:
1. Rode primeiro o diagnóstico e me mostre o resultado, antes de mudar nada.
2. Siga a ordem oficial de teste: dispositivo USB (VID_1504) → spooler →
   compartilhamento → agente 9110 → navegador.
3. Me diga o que falta, proponha o plano e espere eu aprovar.
4. Depois de aprovado, instale e valide os testes de aceitação — inclusive o
   teste NO CHROME logado no sistema (PowerShell não prova o PNA).
5. Salve a sessão no cérebro, como manda a REGRA-MEMORIA-CLAUDE.
```

Se a máquina ainda não tiver o cérebro em rede, primeiro o passo de cliente:
`2-INSTALAR-CLIENTE.cmd` do `CEREBRO-REDE-5-MAQUINAS`, respondendo
**`KHAOSOMNI`** (192.168.15.138) quando perguntar o nome do servidor — foi
digitar outro nome que colocou um notebook no servidor errado em 24/08.
