# CLAUDE.md

Orientações para o Claude Code trabalhar neste repositório.

## O que é

Kit de clonagem de máquinas por pendrive, baseado no Clonezilla Live, mais um
conjunto de scripts de manutenção para Windows. Todo o conteúdo (código,
mensagens, documentação, commits) é em **português do Brasil**.

## Estrutura

```
scripts/
  preparar-pendrive.sh    # Linux comum: particiona, formata, instala Clonezilla, copia o kit
  verificar-pendrive.sh   # Linux comum: confere partições e boot BIOS/UEFI
  clonar-maquina.sh       # Dentro do Clonezilla Live: captura imagem (embrulha ocs-sr)
  restaurar-maquina.sh    # Dentro do Clonezilla Live: restaura imagem
  lib/comum.sh            # Funções compartilhadas (log, confirmação, partições)
  windows/
    1-diagnostico.ps1     # Só lê: espaço, SMART, maiores pastas/arquivos
    2-limpeza.ps1         # Caches e temporários; simula sem -Executar
    3-mover-para-hd.ps1   # Copia, confere e só apaga a origem com -Remover
docs/                     # Guias numerados 01–06 + checklist.md
.github/workflows/shellcheck.yml
```

Layout do pendrive: partição 1 FAT32 `CLONEZILLA` (boot), partição 2 ext4
`IMAGENS` (montada em `/home/partimag` com `imagens/`, `scripts/`, `docs/`, `logs/`).

## Convenções dos scripts Bash

- Cabeçalho `#!/usr/bin/env bash` + `set -euo pipefail`; carregam a biblioteca com
  `# shellcheck source=lib/comum.sh` e `source "$DIR_SCRIPT/lib/comum.sh"`.
- Use as funções de `lib/comum.sh`: `info`, `ok`, `aviso`, `erro`, `abortar`,
  `executar` (respeita `SIMULAR`), `precisa_root`, `checar_dependencias`,
  `nome_particao`, `confirmar_digitando`, `desmontar_disco`.
- Todo comando que escreve em disco passa por `executar` para funcionar com `--simular`.
- Opções longas em português (`--dispositivo`, `--simular`, `--sim`, `-h|--ajuda`),
  com função `ajuda()` em heredoc. Opção desconhecida → `erro` + `ajuda` + `exit 1`.
- Comentários e mensagens sem acentos dentro dos `.sh` (ASCII); a documentação em
  Markdown usa acentuação normal.
- Indentação de 2 espaços, LF, UTF-8 (ver `.editorconfig`).

## Convenções dos scripts PowerShell

- Arquivos em UTF-8 **com BOM** (necessário para acentos no Windows PowerShell 5.1)
  e `#Requires -Version 5.1`.
- Parâmetros em PascalCase português (`-Executar`, `-Remover`, `-Origem`, `-Destino`).
- Padrão seguro: sem a chave explícita (`-Executar`, `-Remover`) apenas simula.
- Relatório/log gravado na Área de Trabalho com carimbo `yyyyMMdd-HHmm`.

## Segurança — prioridade máxima

Os scripts **apagam discos**. Qualquer alteração deve preservar as travas:
recusar discos não removíveis e o disco do sistema, exigir que o operador digite
o dispositivo para confirmar, e manter o modo simulação funcionando. Nunca remova
uma verificação para "simplificar".

## Verificação antes de commitar

Mesmas checagens do CI:

```bash
shellcheck -S info -x -P scripts scripts/*.sh scripts/lib/*.sh
for f in scripts/*.sh scripts/lib/*.sh; do bash -n "$f"; done
```

Não há testes automatizados; para exercitar um script sem tocar em disco use
`--simular`. Os `.ps1` não são checados no CI.

## Documentação

Ao adicionar ou mudar um script, atualize a tabela **Scripts** do `README.md` e o
guia correspondente em `docs/`. Novos guias seguem a numeração (`07-...md`) e
entram na lista **Documentação** do README.
