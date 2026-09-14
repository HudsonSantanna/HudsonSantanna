# 1. Preparar o pendrive

## Antes de começar

- Pendrive de **32 GB ou mais** (USB 3.0 acelera muito a gravação das imagens).
- Uma máquina Linux para preparar o dispositivo.
- Todo o conteúdo do pendrive será apagado.

Instale as dependências:

```bash
# Debian / Ubuntu
sudo apt install parted dosfstools gdisk syslinux-common unzip curl rsync
# Fedora / RHEL
sudo dnf install parted dosfstools gdisk syslinux unzip curl rsync
```

## Identificar o dispositivo certo

```bash
lsblk -o NAME,SIZE,TRAN,MODEL,MOUNTPOINT
```

Procure a linha com `TRAN=usb` e o tamanho do seu pendrive — por exemplo
`sdb   57,3G  usb  SanDisk Ultra`. O alvo é o **disco inteiro** (`/dev/sdb`),
nunca uma partição (`/dev/sdb1`).

> Errar o dispositivo aqui destrói os dados do disco escolhido. O script recusa
> discos não removíveis e o disco onde o sistema está rodando, mas a conferência
> final é sua.

## Executar

```bash
sudo ./scripts/preparar-pendrive.sh --dispositivo /dev/sdb
```

O script:

1. valida o dispositivo (USB, removível, não é o disco do sistema);
2. pede que você digite `/dev/sdb` para confirmar;
3. baixa a última versão estável do Clonezilla Live e confere o SHA256;
4. cria a tabela de partições MBR (compatível com BIOS **e** UEFI);
5. formata `CLONEZILLA` (FAT32) e `IMAGENS` (ext4);
6. extrai o Clonezilla e instala o boot legado com `makeboot.sh`/syslinux;
7. copia `scripts/` e `docs/` para a partição de imagens.

Veja o que aconteceria sem escrever nada:

```bash
sudo ./scripts/preparar-pendrive.sh --dispositivo /dev/sdb --simular
```

## Opções úteis

| Opção | Para quê |
|-------|----------|
| `--zip arquivo.zip` | Usar um `clonezilla-live-*.zip` já baixado (sem internet) |
| `--versao 3.2.0-5` | Fixar uma versão específica do Clonezilla |
| `--tamanho-boot 4GiB` | Reservar mais espaço para o Clonezilla e utilitários |
| `--fs-dados ntfs` | Ler as imagens também no Windows |
| `--fs-dados exfat` | Compatível com Windows e macOS |
| `--esquema gpt` | Pendrive só para máquinas UEFI |
| `--sem-verificacao` | Pular a conferência de SHA256 |
| `--permitir-nao-removivel` | Usar um HD/SSD externo em vez de pendrive |
| `--simular` | Ensaio, sem escrever no disco |

Sem internet na máquina de preparo, baixe o zip antes em
<https://clonezilla.org/downloads/> (escolha `amd64` / formato `zip`) e use
`--zip`.

## Conferir o resultado

```bash
sudo ./scripts/verificar-pendrive.sh --dispositivo /dev/sdb
```

Saída esperada:

```
[ ok ] Particao de boot em FAT32 (encontrado: vfat)
[ ok ] kernel live/vmlinuz presente
[ ok ] live/filesystem.squashfs presente
[ ok ] boot UEFI (EFI/boot/bootx64.efi)
[ ok ] boot BIOS/legado (ldlinux.sys)
[ ok ] pasta imagens/
[ ok ] Pendrive verificado sem problemas.
```

## Atualizar o Clonezilla depois

Rodar o preparo de novo apaga as imagens guardadas. Para atualizar só o boot,
copie as imagens para outro lugar antes, ou monte a partição `CLONEZILLA` e
substitua o conteúdo manualmente pelo zip novo (mantendo `syslinux/`).
