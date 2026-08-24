# 2. Criar a imagem mestre

A imagem mestre é a fotografia da máquina modelo — sistema instalado,
programas, políticas e ajustes prontos. Quanto melhor preparada, menos trabalho
manual em cada máquina restaurada.

## Preparar a máquina modelo

### Windows

1. Instale o sistema, os drivers genéricos, atualizações e os programas padrão.
2. Faça a limpeza: `Limpeza de Disco`, esvaziar a lixeira, remover perfis de
   teste e arquivos temporários.
3. Desative a hibernação (libera vários GB e evita `hiberfil.sys` na imagem):
   ```cmd
   powercfg /h off
   ```
4. Desligue o BitLocker, ou a imagem ficará com dados cifrados e inúteis para
   restauração em outro hardware.
5. **Generalize com o Sysprep** — obrigatório para restaurar em máquinas
   diferentes (gera novo SID, remove o vínculo com o hardware):
   ```cmd
   C:\Windows\System32\Sysprep\sysprep.exe /generalize /oobe /shutdown
   ```
   A máquina desliga sozinha. **Não ligue de novo no Windows** antes de clonar.
6. Desfragmente antes do sysprep se o disco for HDD (não faça em SSD).

> Licenciamento: chaves OEM são vinculadas ao equipamento de origem e não podem
> ser transferidas por clonagem. Para parques de máquinas, use licenciamento por
> volume (KMS/MAK) e um `unattend.xml` no sysprep.

### Linux

1. Instale o sistema e os pacotes padrão; remova caches:
   `sudo apt clean` ou `sudo dnf clean all`.
2. Zere o `machine-id`, senão todas as máquinas clonadas terão a mesma
   identidade (DHCP, systemd, logs):
   ```bash
   sudo truncate -s 0 /etc/machine-id
   sudo rm -f /var/lib/dbus/machine-id
   sudo ln -s /etc/machine-id /var/lib/dbus/machine-id
   ```
3. Remova chaves de host do SSH — elas serão recriadas no primeiro boot:
   ```bash
   sudo rm -f /etc/ssh/ssh_host_*
   ```
4. Use `UUID=` ou `LABEL=` no `/etc/fstab` (o Clonezilla preserva os UUIDs, mas
   isso evita surpresas se você recriar partições).
5. Limpe históricos, chaves privadas, tokens e regras `udev` de rede fixadas por
   MAC (`/etc/udev/rules.d/70-persistent-net.rules`, se existir).

### Zerar o espaço livre (imagem menor)

O Clonezilla ignora blocos não usados, então o ganho vem de arquivos apagados
mas ainda gravados no disco:

```bash
# Linux
sudo dd if=/dev/zero of=/zerar bs=1M status=progress; sudo rm -f /zerar
```
```cmd
:: Windows (Sysinternals)
sdelete64 -z C:
```

## Capturar

1. Desligue a máquina modelo e ligue-a com o pendrive conectado.
2. Acesse o menu de boot (F12/F10/F2/Esc conforme o fabricante) e escolha o
   pendrive. Se a máquina for UEFI, prefira a entrada `UEFI: <pendrive>`.
3. No menu do Clonezilla escolha `Clonezilla live (Default settings, VGA 1024x768)`.
4. Escolha idioma, mapa de teclado e depois **`Enter_shell`**.
5. Execute:

```bash
sudo mount -L IMAGENS /home/partimag
sudo /home/partimag/scripts/clonar-maquina.sh
```

O script lista os discos, pergunta a origem, sugere um nome baseado no modelo da
máquina (`latitude-5420-20260824-1030`) e pede a confirmação `SALVAR`.

### Opções

```bash
# nome e disco explícitos, desligar ao terminar
sudo /home/partimag/scripts/clonar-maquina.sh -d /dev/nvme0n1 -n padrao-win11 --depois poweroff

# só as partições do sistema
sudo /home/partimag/scripts/clonar-maquina.sh -p "nvme0n1p1 nvme0n1p2 nvme0n1p3"

# compressão máxima (imagem menor, captura mais lenta)
sudo /home/partimag/scripts/clonar-maquina.sh -c -z9p

# ver o comando do ocs-sr sem executar
sudo /home/partimag/scripts/clonar-maquina.sh -d /dev/sda --simular
```

Por padrão a imagem é conferida depois de gravada; `--sem-verificar-imagem`
pula essa etapa e economiza tempo quando você tem pressa.

## Depois da captura

- A imagem fica em `imagens/<nome>/` e o log em `logs/clonar-<nome>.log`.
- Anote o que aquela imagem contém — um `imagens/<nome>/NOTAS.txt` com data,
  sistema, programas e senha do usuário administrador poupa muita dúvida depois.
- **Teste a restauração em uma máquina antes de sair a campo.** Uma imagem que
  nunca foi restaurada não é um backup, é uma esperança.
- Guarde uma cópia das imagens fora do pendrive: pendrives falham.
