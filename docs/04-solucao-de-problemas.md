# 4. Solução de problemas

## O pendrive não aparece no menu de boot

- Ative o boot por USB no setup (F2/Del) e coloque-o à frente na ordem de boot.
- Máquinas antigas: ative `Legacy Boot`/`CSM`.
- Máquinas novas: desative **Secure Boot** (o Clonezilla padrão não é assinado
  pela Microsoft) ou baixe a versão com suporte a Secure Boot.
- Desative `Fast Boot` — ele pula a enumeração de dispositivos USB.
- Teste outra porta, de preferência USB 2.0 traseira em desktops.

## Inicia em UEFI mas não em BIOS legado (ou o contrário)

Rode `sudo ./scripts/verificar-pendrive.sh -d /dev/sdb`:

- Falta `EFI/boot/bootx64.efi` → o zip extraído está incompleto; refaça o preparo.
- Falta `ldlinux.sys` → o boot legado não foi instalado. Instale o syslinux
  (`sudo apt install syslinux-common syslinux-utils`) e refaça o preparo.
- Máquina só UEFI e sem CSM → prepare com `--esquema gpt`.

## `Não consegui desmontar /dev/sdb1`

Alguma coisa está usando a partição. Feche o gerenciador de arquivos e:

```bash
sudo fuser -vm /dev/sdb1     # quem está usando
sudo umount -l /dev/sdb1     # desmonta assim que liberar
```

## O download do Clonezilla falha

Baixe manualmente em <https://clonezilla.org/downloads/> (arquitetura `amd64`,
formato `zip`) e passe o arquivo:

```bash
sudo ./scripts/preparar-pendrive.sh -d /dev/sdb --zip ~/Downloads/clonezilla-live-3.2.0-5-amd64.zip
```

Se o espelho estiver fora do ar mas você quiser tentar outra versão:
`--versao 3.1.3-1`.

## `ocs-sr: command not found`

`clonar-maquina.sh` e `restaurar-maquina.sh` só funcionam dentro do Clonezilla
Live. Em um Linux comum, use `--simular` para ver o comando que seria executado.

## O Clonezilla não enxerga o disco interno

- Troque o modo do controlador de `RAID`/`Intel RST` para **AHCI** no setup.
  (No Windows, mudar depois exige boot em modo de segurança para carregar o
  driver certo — faça isso *antes* de criar a imagem mestre.)
- Discos com criptografia ativa (BitLocker, LUKS) aparecem, mas a imagem sai
  cifrada. Desative a criptografia na máquina modelo antes de capturar.

## Espaço insuficiente ao salvar

- Comprima mais: `-c -z9p` (zstd nível alto).
- Zere o espaço livre na máquina modelo antes de capturar (veja o guia 2).
- Salve só as partições do sistema com `--particoes`.
- Apague imagens antigas de `imagens/` — `restaurar-maquina.sh --listar` mostra
  o tamanho de cada uma.

## Restaurei e a máquina não inicia

- **Windows, tela azul `INACCESSIBLE_BOOT_DEVICE`**: modo do controlador
  diferente do da máquina modelo (AHCI × RAID) ou imagem sem `sysprep`.
- **Modo de boot trocado**: a imagem de uma máquina UEFI/GPT não inicia em uma
  máquina configurada como BIOS/MBR. Alinhe o modo no setup.
- **Linux sem grub**: com o pendrive, entre em `Enter_shell` e reinstale:
  ```bash
  sudo mount /dev/sda2 /mnt && sudo mount /dev/sda1 /mnt/boot/efi
  sudo mount --bind /dev /mnt/dev && sudo mount --bind /sys /mnt/sys && sudo mount --bind /proc /mnt/proc
  sudo chroot /mnt grub-install /dev/sda && sudo chroot /mnt update-grub
  ```

## A imagem restaura, mas todas as máquinas têm o mesmo nome/IP

Faltou generalizar a imagem mestre: `sysprep /generalize` no Windows,
`machine-id` zerado no Linux. Veja o guia 2 e refaça a imagem — corrigir
máquina por máquina depois custa muito mais caro.

## O pendrive ficou lento ou com erros de leitura

Pendrives baratos degradam rápido sob escrita intensa. Confira com
`sudo badblocks -sv -c 4096 /dev/sdb` (destrutivo se usar `-w`) e, para uso
frequente, prefira um SSD externo USB.
