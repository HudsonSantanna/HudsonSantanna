---
description: Verifica as rotinas (agentes agendados) do servidor; com "ativar", religa as essenciais desligadas
argument-hint: "[ativar]"
---

Verifique as rotinas agendadas do servidor KHAOSOMNI com o script
`verificar-agentes.ps1`.

Argumento recebido: `$ARGUMENTS`

## 1. Achar o script

Use o primeiro que existir:

1. `$env:USERPROFILE\Scripts\verificar-agentes.ps1`
2. `scripts\windows\verificar-agentes.ps1` dentro do repositório aberto

A lista de rotinas essenciais é o `rotinas-essenciais.txt` na mesma pasta do
script. Se nenhum dos dois existir, pare e diga onde procurou.

## 2. Rodar

- Argumento vazio → **só verificar**:
  `powershell -NoProfile -ExecutionPolicy Bypass -File "<script>"`
- Argumento `ativar` → **verificar e religar as essenciais desligadas**:
  `powershell -NoProfile -ExecutionPolicy Bypass -File "<script>" -Ativar`
- Qualquer outro argumento → não rode nada; diga que os usos são
  `/verificar-agentes` e `/verificar-agentes ativar`.

Se o script parar com "PARE: esta maquina e ..., nao o servidor KHAOSOMNI",
**não** repita com `-Forcar` por conta própria: avise e pergunte.

## 3. Entregar o relatório

O script imprime o relatório e salva uma cópia na Área de Trabalho. Leia a
saída inteira e responda em português, curto, nesta ordem:

1. **Veredito** em uma linha: tudo certo, ou quantos problemas.
2. **Tabela das rotinas essenciais**: nome, estado, última execução e
   resultado, próxima execução, e `OK` / o problema.
3. **Religadas** (só no modo `ativar`): quais voltaram, confirmadas pela
   leitura de volta do script, e o caminho do checkpoint XML de cada uma.
   Rotina que o script recusou religar (arquivo da ação não existe) ou que
   o Windows não deixou (falta de administrador) vai aqui com o motivo.
4. **Outras rotinas desligadas** fora da lista: só cite, e pergunte se
   alguma deveria entrar em `rotinas-essenciais.txt`.
5. Caminho do relatório salvo.

## Regras

- Religar é a **única** alteração permitida, e só pelo script com `-Ativar`.
  Nunca crie, apague, rode, renomeie ou altere gatilho/ação de tarefa, nem
  religue à mão algo que não está na lista.
- Não invente estado: tudo que você disser tem de estar na saída do script.
- Última execução com falha (resultado diferente de `0x0`) ou arquivo da ação
  inexistente: aponte, mas não conserte sem eu pedir.
