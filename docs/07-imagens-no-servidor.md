# 7. Imagens no servidor (rede do escritório)

O pendrive continua sendo o que dá boot e o que roda os scripts. O que muda
aqui é **onde ficam as imagens**: em vez de caberem na segunda partição do
pendrive, elas ficam em um servidor da rede do escritório — o "cérebro" —
e todas as máquinas gravam e leem do mesmo lugar.

Ganhos: uma imagem só, sempre atualizada, sem copiar pendrive a pendrive;
espaço limitado apenas pelo disco do servidor; várias máquinas restaurando ao
mesmo tempo, cada uma com seu pendrive de boot.

O pendrive segue funcionando sozinho: sem servidor configurado — ou com
`--local` — nada muda em relação ao fluxo antigo.

## Como os scripts decidem onde gravar

Na ordem:

1. `--local` → usa a partição `IMAGENS` do pendrive e para por aí.
2. `--servidor` na linha de comando → usa o servidor informado.
3. `rede.conf` com `SERVIDOR=` → usa o servidor do arquivo.
4. Nada disso → pendrive, como sempre.

O primeiro `rede.conf` encontrado vence, nesta ordem:

```
scripts/rede.conf             # junto dos scripts, no pendrive
/home/partimag/rede.conf      # raiz da partição IMAGENS
/etc/kit-clonagem/rede.conf   # máquina fixa de manutenção
```

Ou aponte um arquivo específico com `--config /caminho/rede.conf`.

## Preparar o servidor

O servidor precisa de uma pasta com as subpastas `imagens/` e `logs/`, e de um
usuário com permissão de escrita nela. Reserve espaço: cada imagem de Windows
11 comprimida ocupa de 12 a 25 GB.

```bash
sudo mkdir -p /srv/clonagem/{imagens,logs}
sudo useradd -r -d /srv/clonagem -s /usr/sbin/nologin clonagem 2>/dev/null || true
sudo chown -R clonagem:clonagem /srv/clonagem
```

Escolha **um** protocolo:

### SSH (mais simples, já vem no Clonezilla)

Nada a instalar no servidor além do `openssh-server`. Gere uma chave e leve a
parte privada no pendrive, para não digitar senha em cada máquina:

```bash
ssh-keygen -t ed25519 -f ~/chave-clonagem -N ''
ssh-copy-id -i ~/chave-clonagem.pub clonagem@192.168.0.10
sudo cp ~/chave-clonagem /home/partimag/chave-clonagem   # com o pendrive montado
sudo chmod 600 /home/partimag/chave-clonagem
```

É o mais lento dos três, porque tudo passa por criptografia. Para lotes
grandes, prefira NFS.

### NFS (mais rápido em rede cabeada)

No servidor (Debian/Ubuntu):

```bash
sudo apt install nfs-kernel-server
echo '/srv/clonagem 192.168.0.0/24(rw,sync,no_subtree_check,all_squash,anonuid=1001,anongid=1001)' \
  | sudo tee -a /etc/exports
sudo exportfs -ra
```

Troque `anonuid`/`anongid` pelo id do usuário `clonagem`
(`id -u clonagem`). Não há senha: a proteção é a faixa de IP do export.

### SMB (quando o servidor é Windows ou já existe um compartilhamento)

Compartilhe a pasta com permissão de escrita para um usuário de serviço. No
pendrive, guarde as credenciais em arquivo — nunca na linha de comando, que
fica visível para qualquer processo da máquina:

```bash
sudo tee /home/partimag/credenciais-smb >/dev/null <<'FIM'
username=clonagem
password=SUA-SENHA
domain=ESCRITORIO
FIM
sudo chmod 600 /home/partimag/credenciais-smb
```

## Configurar o pendrive

Na preparação, já saindo apontado para o servidor:

```bash
sudo ./scripts/preparar-pendrive.sh -d /dev/sdb \
  --servidor 192.168.0.10 --caminho /srv/clonagem --usuario clonagem
```

Isso grava um `rede.conf` na raiz da partição `IMAGENS`. Em um pendrive já
pronto, copie o modelo e edite:

```bash
sudo mount -L IMAGENS /home/partimag
sudo cp /home/partimag/scripts/rede.conf.exemplo /home/partimag/rede.conf
sudo nano /home/partimag/rede.conf
```

Exemplo de `rede.conf` para SSH com chave:

```ini
SERVIDOR=192.168.0.10
PROTOCOLO=ssh
CAMINHO=/srv/clonagem
USUARIO=clonagem
CREDENCIAIS=/home/partimag/chave-clonagem
```

Use **o IP** do servidor, não o nome: dentro do Clonezilla Live nem sempre há
DNS ou WINS respondendo.

## Usar no dia a dia

Boot pelo pendrive → `Clonezilla live` → `Enter_shell`. Depois:

```bash
sudo mount -L IMAGENS /home/partimag        # scripts e rede.conf

# 1. Conferir a rede antes de qualquer coisa
sudo /home/partimag/scripts/verificar-rede.sh

# 2. Capturar a imagem da máquina modelo direto no servidor
sudo /home/partimag/scripts/clonar-maquina.sh -n padrao-win11

# 3. Restaurar em outra máquina, lendo do servidor
sudo /home/partimag/scripts/restaurar-maquina.sh -i padrao-win11 -d /dev/nvme0n1
```

Os scripts sobem a rede (DHCP por padrão), testam o servidor, montam o
repositório em `/home/partimag`, trabalham e desmontam no fim. Como o
`ocs-sr` grava direto no servidor, não há segunda cópia depois.

Para não deixar ninguém apagar ou sobrescrever imagem do servidor por engano
durante um lote de restauração:

```bash
sudo /home/partimag/scripts/restaurar-maquina.sh --somente-leitura -i padrao-win11 -d /dev/sda
```

Nesse modo o log da operação fica em `/tmp/kit-clonagem/logs`.

Passar por cima do `rede.conf` em uma máquina específica:

```bash
sudo /home/partimag/scripts/clonar-maquina.sh --servidor 192.168.0.11 --protocolo nfs \
  --caminho /srv/clonagem
```

## Quando não há rede

Máquina fora do escritório, switch sem porta livre, servidor em manutenção:
acrescente `--local` e o pendrive volta a ser o repositório.

```bash
sudo /home/partimag/scripts/clonar-maquina.sh --local -n cliente-x
```

Depois, de volta ao escritório, mande a imagem para o servidor:

```bash
sudo /home/partimag/scripts/sincronizar-imagens.sh --enviar cliente-x
```

E o caminho inverso, para levar uma imagem do servidor no pendrive antes de
sair para campo:

```bash
sudo /home/partimag/scripts/sincronizar-imagens.sh --baixar padrao-win11
sudo /home/partimag/scripts/sincronizar-imagens.sh --listar   # os dois lados
```

A cópia é conferida com `rsync -c` antes de qualquer coisa ser apagada; com
`--apagar-origem`, a origem só some depois dessa conferência passar.

## Desempenho

Uma imagem de 20 GB em rede cabeada de 1 Gb/s leva de 5 a 10 minutos por
máquina, contra 3 a 5 minutos no pendrive USB 3.0. Vale medir na sua rede.

- Gigabit e cabo. Wi-Fi funciona, mas triplica o tempo e cai no meio.
- NFS é mais rápido que SMB, que é mais rápido que SSHFS.
- Restaurações simultâneas dividem a banda do servidor: acima de 4 ou 5
  máquinas ao mesmo tempo, compensa levar a imagem em pendrives.
- Disco do servidor também é gargalo: HD mecânico segura bem menos máquinas
  simultâneas que SSD.

## Problemas comuns

| Sintoma | Causa provável | O que fazer |
|---------|----------------|-------------|
| `Nenhuma interface de rede com cabo conectado` | cabo solto, switch desligado, placa sem driver | conferir cabo; `--interface` para forçar a placa certa |
| `A maquina nao recebeu endereco IP` | sem DHCP na tomada | usar IP fixo no `rede.conf` (`IP=`, `GATEWAY=`, `DNS=`) |
| `Servidor ... nao responde na porta` | firewall ou serviço parado | liberar a porta (22/2049/445) e conferir o serviço no servidor |
| `Falha ao montar por SSH` | chave sem permissão ou usuário errado | `chmod 600` na chave; testar `ssh -i chave clonagem@servidor` |
| `Falha ao montar por NFS` | IP da máquina fora da faixa do export | ajustar `/etc/exports` e rodar `sudo exportfs -ra` |
| `Repositorio do servidor nao esta gravavel` | dono/permissão da pasta no servidor | `chown` da pasta para o usuário de serviço |
| `Comandos ausentes para o protocolo ...` | utilitário fora da imagem do Clonezilla | usar outro protocolo, ou `--local` e sincronizar depois |
| Cópia muito lenta | Wi-Fi, 100 Mb/s ou SSHFS | cabo gigabit e NFS |

Nome do servidor não resolve dentro do Clonezilla? Use o IP. É a solução para
a maior parte dos "não acha o servidor".
