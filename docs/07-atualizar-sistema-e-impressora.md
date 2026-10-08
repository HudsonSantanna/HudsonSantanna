# Atualizar o sistema e a impressora de código de barras

Scripts para PowerShell no Windows, continuação dos passos de
[manutenção](06-manutencao-windows.md). Abra o **PowerShell como administrador**
(Windows + X → **Terminal (Admin)**) e vá até a pasta dos scripts:

```powershell
cd "$env:USERPROFILE\Downloads\manutencao"
```

## Passo 4 — Atualizar o sistema

Primeiro só liste o que está pendente — **não instala nada**:

```powershell
powershell -ExecutionPolicy Bypass -File .\4-atualizar-sistema.ps1
```

Mostra as atualizações do Windows (marcando quais são **drivers**), os programas
com versão nova no `winget` e a data das assinaturas do antivírus.

Para instalar de verdade:

```powershell
powershell -ExecutionPolicy Bypass -File .\4-atualizar-sistema.ps1 -Executar
```

Ele cria um ponto de restauração, instala as atualizações do Windows (inclusive
drivers, que é por onde muitas vezes chega o driver novo da impressora de
etiquetas), atualiza os programas e o Defender. No fim avisa se precisa
reiniciar — **reinicie e rode de novo**, porque às vezes aparecem mais
atualizações depois.

| Parâmetro | O que faz |
|---|---|
| `-SemDrivers` | Não instala drivers pelo Windows Update (use se o driver atual da impressora foi instalado à mão e está funcionando bem) |
| `-SemProgramas` | Não atualiza programas pelo winget |

> Feche o programa de etiquetas (Bartender, ZebraDesigner, sistema de vendas)
> antes de rodar com `-Executar`.

## Passo 5 — Impressora de código de barras

Diagnóstico (só lê):

```powershell
powershell -ExecutionPolicy Bypass -File .\5-impressora-etiquetas.ps1
```

Reconhece as marcas mais comuns (Zebra, Bixolon, Elgin, Argox, TSC, Honeywell,
Datamax, Gainscha...) e mostra para cada uma:

- driver e **versão do driver**, e o site do fabricante para baixar a versão nova
- porta: se for **USB**, se o aparelho está conectado; se for **rede**, se o IP responde
- **fila de impressão** travada
- se está marcada como **"Usar impressora offline"**
- **cópias duplicadas** (`Impressora (Cópia 1)`), que aparecem quando o cabo USB
  muda de porta — causa clássica de "mandei imprimir e não saiu"

Se a impressora não for reconhecida, informe o nome exato que aparece na lista:

```powershell
.\5-impressora-etiquetas.ps1 -Impressora "ZDesigner GC420t"
```

### Destravar

```powershell
.\5-impressora-etiquetas.ps1 -Corrigir
```

Reinicia o serviço de impressão, esvazia a fila travada e tira a impressora do
modo offline. **Atenção:** descarta os trabalhos pendentes de todas as
impressoras — mande imprimir de novo depois.

### Duas impressoras iguais: quem é quem

```powershell
.\5-impressora-etiquetas.ps1 -Identificar
```

Manda **uma etiqueta por porta USB**, escrita com o número da porta (ex.: `USB003`)
e o nome das filas que usam essa porta. Veja em qual impressora cada uma saiu.
Porta sem impressora: o script avisa "NAO SAIU" e tira o trabalho da fila, para
não sair de surpresa depois. Útil quando há duas impressoras do mesmo modelo
(ex.: duas Bixolon) e o Windows troca as portas depois de reiniciar.

### Etiqueta de teste

```powershell
.\5-impressora-etiquetas.ps1 -ImprimirTeste
```

Imprime **uma** etiqueta com "TESTE DE IMPRESSAO", nome da máquina, data e um
código de barras. Envia os comandos direto para a impressora, então serve para
separar problema de **impressora** de problema do **programa de etiquetas**.
Não muda nenhuma configuração da impressora.

A linguagem é escolhida pela marca:

| Marca | Linguagem |
|---|---|
| Zebra (ZDesigner) | `ZPL` |
| Bixolon com driver "BPL-Z" (ex.: XD3-40t) | `ZPL` |
| Zebra LP/TLP 2844, drivers "(EPL)", PPLB | `EPL` |
| Elgin L42, Argox | `PPLA` (sai só o texto, sem código de barras) |
| TSC, Gainscha | `TSPL` |

Se não reconhecer, ou se a etiqueta sair em branco/com texto estranho, force
outra: `-ImprimirTeste -Linguagem ZPL` (ou `EPL`, `PPLA`, `TSPL`).
Brother QL e DYMO não usam essas linguagens — teste pela página de teste do
driver.

## Atualizar o driver da impressora

1. Rode o passo 4 com `-Executar` — o Windows Update traz drivers de várias marcas.
2. Se não vier por lá, baixe do site que o passo 5 indica em **"Driver novo em"**.
3. **Antes de instalar o driver novo, anote as configurações** da impressora
   (tamanho da etiqueta, velocidade, escurecimento/temperatura): o driver novo
   pode voltar tudo ao padrão.
4. Depois de instalar, rode `.\5-impressora-etiquetas.ps1 -ImprimirTeste` e
   imprima uma etiqueta real pelo programa de sempre.

## Problemas comuns

| Sintoma | O que fazer |
|---|---|
| Não sai nada | `-Corrigir`; confira se a fila esvaziou e se não está offline |
| Sai em branco | Ribbon (fita) acabou/invertido, ou papel térmico do lado errado; ou linguagem errada no teste |
| Pula etiquetas ou corta no meio | Calibre: segure o botão FEED até piscar, ou "Calibrar" nas preferências do driver |
| Impressão fraca | Aumente o escurecimento (Darkness) nas preferências do driver |
| Funcionava e parou depois de trocar o cabo de porta | Veja "CÓPIAS DUPLICADAS" no relatório |
