# Contexto do projeto

Kit de clonagem de máquinas por pendrive: prepara um pendrive que dá boot
(BIOS e UEFI), captura a imagem de uma máquina modelo e restaura essa imagem
em outras máquinas. A base é o Clonezilla Live; os scripts daqui embrulham o
`ocs-sr` com travas de segurança, nomes padronizados e log.

Este arquivo é lido automaticamente por qualquer sessão do Claude Code que
abrir o repositório — na máquina KHAOSOMNI, no navegador ou em qualquer outro
computador. É por ele que todas as sessões partem das mesmas regras.

## Estrutura

| Caminho | O que é |
|---------|---------|
| `scripts/preparar-pendrive.sh`  | Particiona e monta o pendrive (roda em Linux comum) |
| `scripts/verificar-pendrive.sh` | Confere partições, boot BIOS/UEFI e repositório |
| `scripts/clonar-maquina.sh`     | Captura imagem (roda dentro do Clonezilla Live) |
| `scripts/restaurar-maquina.sh`  | Restaura imagem (roda dentro do Clonezilla Live) |
| `scripts/montar-servidor.sh`    | Monta o repositório de imagens de um servidor SMB pela rede |
| `scripts/lib/comum.sh`          | Funções compartilhadas: log, confirmação, partições |
| `scripts/windows/*.ps1`         | Diagnóstico, limpeza e mudança de dados (Windows) |
| `docs/`                         | Passo a passo numerado e checklist de campo |

## Convenções

- **Idioma:** tudo em português — código, comentários, mensagens, documentação,
  nomes de funções e variáveis, mensagens de commit e descrições de PR.
- **Shell:** `bash` com `set -euo pipefail`, indentação de 2 espaços, funções
  compartilhadas em `scripts/lib/comum.sh` em vez de código repetido.
- **Toda operação destrutiva** pede confirmação explícita, recusa disco de
  sistema e disco não removível, e aceita `--simular` para não escrever nada.
- **Todo script** aceita `--ajuda` e registra o que fez em `logs/`.
- `.editorconfig` manda: UTF-8, fim de linha LF, linha final em branco.

## Antes de commitar

```bash
shellcheck -S info -x -P scripts scripts/*.sh scripts/lib/*.sh
for f in scripts/*.sh scripts/lib/*.sh; do bash -n "$f"; done
```

É exatamente o que o workflow `.github/workflows/shellcheck.yml` roda no push
e no pull request. Rodar antes evita PR vermelho.

## Sincronizar entre máquinas

O repositório no GitHub é o ponto de encontro: nenhuma sessão fala direto com
a outra. Veja [docs/07-sincronizar-maquinas.md](docs/07-sincronizar-maquinas.md). Quando
há servidor na rede, as imagens vão por ele em vez do pendrive:
[docs/08-servidor-de-rede.md](docs/08-servidor-de-rede.md).

## Cuidados

- Imagens (`*.img`, `*.iso`, `*.zip`) ficam fora do Git — veja `.gitignore`.
  Elas moram no pendrive, nunca no repositório.
- O Clonezilla não é redistribuído aqui; é baixado da origem oficial durante
  a preparação do pendrive.
