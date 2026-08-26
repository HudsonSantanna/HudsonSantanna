# Kit de clonagem de máquinas por pendrive

Ferramentas para transformar um pendrive comum em uma estação portátil de
clonagem: um único dispositivo que **inicializa** (BIOS e UEFI), **captura** a
imagem de uma máquina modelo e **restaura** essa imagem em quantas máquinas
forem necessárias.

A base é o [Clonezilla Live](https://clonezilla.org/) — os scripts aqui cuidam
da preparação do pendrive e embrulham o `ocs-sr` com travas de segurança,
nomes de imagem padronizados e registro de log.

## Layout do pendrive

| Partição | Sistema de arquivos | Rótulo       | Conteúdo                                   |
|----------|---------------------|--------------|--------------------------------------------|
| 1        | FAT32 (2 GiB)       | `CLONEZILLA` | Clonezilla Live, boot BIOS (syslinux) + UEFI |
| 2        | ext4 (restante)     | `IMAGENS`    | `imagens/`, `scripts/`, `docs/`, `logs/`     |

Separar boot e dados permite atualizar o Clonezilla sem perder as imagens, e
guardar as imagens no mesmo pendrive que dá boot — sem rede, sem servidor.

## Uso rápido

```bash
git clone https://github.com/HudsonSantanna/HudsonSantanna.git kit-clonagem
cd kit-clonagem

# 1. Preparar o pendrive (APAGA o dispositivo informado)
sudo ./scripts/preparar-pendrive.sh --dispositivo /dev/sdb

# 2. Conferir o resultado
sudo ./scripts/verificar-pendrive.sh --dispositivo /dev/sdb
```

Confira o dispositivo correto antes de tudo com `lsblk -o NAME,SIZE,TRAN,MODEL`.
O script recusa discos não removíveis e o disco do sistema em execução, e exige
que você digite o caminho do dispositivo para confirmar.

Depois, com a máquina modelo pronta, dê boot pelo pendrive e no menu escolha
`Clonezilla live` → `Enter_shell`:

```bash
sudo mount -L IMAGENS /home/partimag
sudo /home/partimag/scripts/clonar-maquina.sh          # captura a imagem
sudo /home/partimag/scripts/restaurar-maquina.sh       # grava em outra máquina
```

## Scripts

| Script | Onde roda | Função |
|--------|-----------|--------|
| `scripts/preparar-pendrive.sh`   | Linux comum      | Particiona, formata, instala o Clonezilla e copia os scripts |
| `scripts/verificar-pendrive.sh`  | Linux comum      | Confere partições, arquivos de boot BIOS/UEFI e repositório |
| `scripts/clonar-maquina.sh`      | Clonezilla Live  | Captura a imagem de um disco para `imagens/` |
| `scripts/restaurar-maquina.sh`   | Clonezilla Live  | Restaura uma imagem para o disco de destino |
| `scripts/lib/comum.sh`           | —                | Funções compartilhadas (log, confirmações, partições) |
| `scripts/windows/1-diagnostico.ps1`   | Windows     | Relatório de espaço, saúde dos discos, maiores pastas e arquivos |
| `scripts/windows/2-limpeza.ps1`       | Windows     | Libera caches e temporários (simula por padrão) |
| `scripts/windows/3-mover-para-hd.ps1` | Windows     | Copia para HD externo, confere e só então apaga a origem |
| `scripts/windows/5-diagnostico-etiquetadora.ps1` | Windows (estoque) | Diagnóstico somente leitura da etiquetadora BIXOLON, do agente ArgosPrint e da pistola |

Todos aceitam `--ajuda` e `--simular` (mostra o que seria feito sem escrever nada) —
menos o `5-diagnostico-etiquetadora.ps1`, que é somente leitura por natureza e não
tem o que simular; ele aceita `-Porta` e `-Saida`.

## Documentação

1. [Preparar o pendrive](docs/01-preparar-pendrive.md)
2. [Criar a imagem mestre](docs/02-criar-imagem-mestre.md)
3. [Restaurar em lote](docs/03-restaurar-em-lote.md)
4. [Solução de problemas](docs/04-solucao-de-problemas.md)
5. [Preparar o pendrive pelo Windows](docs/05-preparar-pelo-windows.md)
6. [Manutenção da máquina no Windows](docs/06-manutencao-windows.md)
7. [Diagnóstico da etiquetadora](docs/08-diagnostico-etiquetadora.md)
8. [Checklist de campo](docs/checklist.md)

## Requisitos

Os scripts de preparo rodam em **Linux**. Se você só tem Windows à mão, veja
[docs/05-preparar-pelo-windows.md](docs/05-preparar-pelo-windows.md) — o caminho
por lá é o Ventoy, e os scripts de captura e restauração continuam funcionando
normalmente, porque rodam dentro do Clonezilla Live.

Na máquina onde o pendrive é preparado (Debian/Ubuntu):

```bash
sudo apt install parted dosfstools gdisk syslinux-common unzip curl rsync
```

Fedora/RHEL: `sudo dnf install parted dosfstools gdisk syslinux unzip curl rsync`

Pendrive de 32 GB ou mais é o mínimo prático: uma instalação Windows 11
comprimida costuma ocupar de 12 a 25 GB por imagem.

## Avisos

- Os scripts **apagam discos**. Confira o dispositivo duas vezes.
- Clonar Windows entre máquinas exige `sysprep /generalize` e licenciamento
  adequado (OEM não é transferível). Veja
  [docs/02-criar-imagem-mestre.md](docs/02-criar-imagem-mestre.md).
- Máquinas com Secure Boot precisam do Clonezilla assinado ou do Secure Boot
  desativado no setup.
- Clonezilla é software livre (GPL); este repositório não o redistribui, apenas
  baixa a versão oficial durante a preparação.
