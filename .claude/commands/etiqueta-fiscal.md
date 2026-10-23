---
description: Diagnostica a impressora Etiqueta Fiscal na máquina da loja (spooler, porta USB, fila, agente de notas); com "reparar", destrava e religa
argument-hint: "[reparar]"
---

Descubra por que a **Etiqueta Fiscal** da máquina da loja (`HUDSONINTEGRAR`)
não imprime, ou por que o guardião avisa que "não conseguiu ler as
impressoras", com o script `etiqueta-fiscal.ps1`.

Argumento recebido: `$ARGUMENTS`

## 1. Achar o script

Use o primeiro que existir:

1. `$env:USERPROFILE\Scripts\etiqueta-fiscal.ps1`
2. `scripts\windows\etiqueta-fiscal.ps1` dentro do repositório aberto

Se nenhum dos dois existir, pare e diga onde procurou.

## 2. Rodar

- Argumento vazio → **só diagnosticar**:
  `powershell -NoProfile -ExecutionPolicy Bypass -File "<script>"`
- Argumento `reparar` → **diagnosticar e aplicar o plano** (o PowerShell
  precisa estar **como administrador** para reiniciar o spooler e mudar a porta):
  `powershell -NoProfile -ExecutionPolicy Bypass -File "<script>" -Reparar`
- Qualquer outro argumento → não rode nada; diga que os usos são
  `/etiqueta-fiscal` e `/etiqueta-fiscal reparar`.

Com o Windows travado, o diagnóstico pode levar uns 4 minutos: cada teste
espera até o limite dele antes de ser encerrado. Não interrompa.

Se o script parar com "PARE: esta maquina e ..., nao a HUDSONINTEGRAR",
**não** repita com `-Forcar` por conta própria: avise e pergunte.

## 3. Entregar o relatório

Leia a saída inteira e responda em português, curto, nesta ordem:

1. **Veredito** em uma linha: está imprimindo ou não, e por quê.
2. **Causa**, uma destas, pelo que a saída mostra: spooler travado, fila em
   porta morta, fila pausada/offline/em erro, trabalho parado, agente parado,
   ou só o WMI travado (a impressão pode estar normal e só o guardião não
   consegue ler).
3. **Fila**: porta, estado e trabalhos parados, com a idade de cada um.
4. **Agente de notas fiscais**: estado da tarefa, arquivos esperando na
   `Entrada` e arquivos em `Erro` nas últimas 24 h.
5. **Plano** (modo diagnóstico) ou **o que foi reparado e confirmado** (modo
   `reparar`).
6. **O que é com a pessoa**: impressora desligada ou cabo solto, papel/ribbon,
   decidir sobre trabalho parado, reimprimir o que foi para `Erro`, rodar o
   `7-nomear-impressoras.ps1 -Identificar` quando a porta for ambígua,
   reiniciar a máquina quando só o WMI travou.
7. Caminho do relatório salvo.

## Regras

- Toda alteração passa pelo script com `-Reparar`. Não reinicie serviço, não
  mude porta, não pare processo à mão.
- **Nunca apague trabalho de impressão**: pode ser a etiqueta de um pedido
  já faturado. Quem decide é a pessoa, olhando a fila.
- Nunca remova nem renomeie fila, nem mude a impressora padrão.
- Nunca reinicie a máquina sem a pessoa mandar: a loja pode estar no meio da
  expedição.
- Não abra o UpSeller, não emita nota, não reimprima nada por conta própria.
- Não invente estado: tudo que você disser tem de estar na saída do script.
