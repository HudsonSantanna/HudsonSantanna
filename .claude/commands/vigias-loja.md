---
description: Diagnostica os vigias do Argos na máquina da loja (UpSeller, Ações, TikTok); com "reparar", destrava e religa
argument-hint: "[reparar]"
---

Faça a manutenção dos vigias do Argos na máquina da loja (`HUDSONINTEGRAR`)
com o script `vigias-loja.ps1`.

Argumento recebido: `$ARGUMENTS`

## 1. Achar o script

Use o primeiro que existir:

1. `$env:USERPROFILE\Scripts\vigias-loja.ps1`
2. `scripts\windows\vigias-loja.ps1` dentro do repositório aberto

Se nenhum dos dois existir, pare e diga onde procurou.

## 2. Rodar

- Argumento vazio → **só diagnosticar**:
  `powershell -NoProfile -ExecutionPolicy Bypass -File "<script>"`
- Argumento `reparar` → **diagnosticar e aplicar o plano**:
  `powershell -NoProfile -ExecutionPolicy Bypass -File "<script>" -Reparar`
- Qualquer outro argumento → não rode nada; diga que os usos são
  `/vigias-loja` e `/vigias-loja reparar`.

O diagnóstico pode levar uns 5 minutos quando o Windows está travado: cada
teste espera até o limite dele antes de ser encerrado. Não interrompa.

Se o script parar com "PARE: esta maquina e ..., nao a HUDSONINTEGRAR",
**não** repita com `-Forcar` por conta própria: avise e pergunte.

## 3. Entregar o relatório

Leia a saída inteira e responda em português, curto, nesta ordem:

1. **Veredito** em uma linha.
2. **O Windows está respondendo?** WMI, Agendador (WMI e COM), spooler,
   impressoras. Diga qual das três suspeitas o resultado confirma: rodada
   presa (IgnoreNew), spooler travado ou WMI travado.
3. **Tabela dos vigias**: nome, estado, última vez e resultado, limite de
   tempo, e `OK` / o problema.
4. **Chrome aberto à mão no perfil do vigia**: se aparecer, peça para a pessoa
   fechar aquela janela. Você não fecha.
5. **Plano** (modo diagnóstico) ou **o que foi reparado e confirmado** (modo
   `reparar`), com o caminho do checkpoint.
6. **Pendências** que não são do script: SMTP não configurado, WMI que só
   volta reiniciando a máquina.
7. Caminho do relatório salvo.

## Regras

- Toda alteração passa pelo script com `-Reparar`. Não pare processo, não
  reinicie serviço e não mexa em tarefa à mão.
- Nunca reinicie a máquina sem a pessoa mandar: a loja pode estar no meio da
  expedição.
- Não abra o UpSeller nem o TikTok, não emita nota, não programe envio.
- Não invente estado: tudo que você disser tem de estar na saída do script.
- SMTP: nunca peça, escreva ou mostre senha. Só diga o que falta.
