# Usar o servidor da rede em vez do pendrive

Com um servidor Windows na mesma rede, o pendrive continua sendo quem dá boot,
mas as imagens não precisam mais morar nele. O Clonezilla grava e lê direto da
pasta compartilhada — e o repositório de scripts pode ficar espelhado lá para
as máquinas sem internet.

Duas coisas passam a viajar pela rede:

| O quê | Onde fica no servidor | Como chega na máquina |
|-------|-----------------------|-----------------------|
| Imagens de clonagem | pasta compartilhada, ex.: `D:\Clonagem` | montada em `/home/partimag` |
| Espelho do repositório Git | `D:\Clonagem\kit-clonagem.git` | `git clone` pelo caminho de rede |

O pendrive não fica obsoleto: ele é o que dá boot, e continua sendo o plano B
quando a rede cai ou a máquina não tem cabo.

## Parte 1 — Preparar o servidor Windows (uma vez)

### Conta dedicada

Crie uma conta **local** no servidor só para isso — não use a sua conta
pessoal nem conta Microsoft. Em um PowerShell como administrador:

```powershell
New-LocalUser -Name clonagem -Description "Acesso as imagens de clonagem"
```

O Windows 10 e o 11 desabilitam acesso de convidado por padrão, então uma
conta real é obrigatória — não existe compartilhamento anônimo.

### Pasta e compartilhamento

```powershell
New-Item -ItemType Directory -Path D:\Clonagem -Force
New-SmbShare -Name imagens -Path D:\Clonagem -FullAccess clonagem
```

Confirme que a permissão NTFS também deixa a conta escrever:

```powershell
icacls D:\Clonagem /grant clonagem:(OI)(CI)M
```

Compartilhamento e NTFS são duas travas separadas: a mais restritiva vence.
Passar só por uma das duas é o motivo mais comum de "montou mas não escreve".

### Rede e firewall

```powershell
Get-NetConnectionProfile                     # precisa estar como Private
Set-NetConnectionProfile -NetworkCategory Private
Enable-NetFirewallRule -DisplayGroup "Compartilhamento de Arquivos e Impressoras"
ipconfig | Select-String IPv4                # anote o IP do servidor
```

Em rede marcada como *Public* o Windows bloqueia o compartilhamento inteiro,
por mais correta que esteja a permissão.

### Espaço

Cada imagem de Windows 11 comprimida ocupa de 12 a 25 GB. Dez modelos de
máquina passam facilmente de 200 GB — confira o disco antes.

## Parte 2 — Montar o servidor no Clonezilla Live

Dê boot pelo pendrive, escolha `Clonezilla live` → `Enter_shell`, e monte o
compartilhamento:

```bash
sudo mount -L IMAGENS /mnt/pendrive
sudo /mnt/pendrive/scripts/montar-servidor.sh -s 192.168.0.10 -c imagens -u clonagem
```

A senha é perguntada na hora e vai para um arquivo temporário com permissão
600 — nunca para a linha de comando, onde qualquer um veria com `ps`.

O script monta em `/home/partimag`, testa a escrita de verdade antes de
devolver o controle e mostra o espaço livre. Testar a escrita agora evita
descobrir que a pasta era somente leitura vinte minutos depois, no meio de
uma captura.

Para ver o comando sem montar nada: acrescente `--simular`.

### Alternativa: pelo menu do próprio Clonezilla

Se preferir não usar o script, o Clonezilla tem essa opção nativa. No menu
`Mount Clonezilla image directory`, escolha `samba_server` e informe IP,
domínio (deixe em branco), conta e a pasta. Ele monta no mesmo
`/home/partimag`. O script existe para deixar isso repetível e para conferir
a escrita, não porque o menu não funcione.

## Parte 3 — Clonar e restaurar pela rede

Nada muda nos comandos. `clonar-maquina.sh` e `restaurar-maquina.sh` detectam
que `/home/partimag` já é um ponto de montagem e usam o que estiver lá:

```bash
sudo /mnt/pendrive/scripts/clonar-maquina.sh                     # captura para o servidor
sudo /mnt/pendrive/scripts/restaurar-maquina.sh --listar         # imagens do servidor
sudo /mnt/pendrive/scripts/restaurar-maquina.sh -i NOME -d /dev/sda
```

Ao terminar, desmonte antes de desligar — dado em trânsito para a rede se
perde igual a dado em trânsito para o pendrive:

```bash
sudo /mnt/pendrive/scripts/montar-servidor.sh --desmontar
```

### Quanto tempo leva

Em rede cabeada de 1 Gbps, espere de 60 a 100 MB/s reais: uma imagem de 20 GB
leva algo entre 4 e 6 minutos. **Use cabo.** Em Wi-Fi a mesma imagem pode
levar mais de uma hora e uma queda no meio invalida a captura.

O ganho aparece no lote: restaurar dez máquinas do servidor dispensa dez
cópias para pendrive. Se as máquinas puderem restaurar ao mesmo tempo, a rede
vira o gargalo — vá de três ou quatro por vez e meça.

## Parte 4 — Espelho do repositório no servidor

Para as máquinas pegarem scripts e documentação sem internet. No servidor,
uma vez:

```powershell
cd D:\Clonagem
git clone --mirror https://github.com/HudsonSantanna/HudsonSantanna.git kit-clonagem.git
```

Para atualizar o espelho depois de qualquer mudança no GitHub:

```powershell
git -C D:\Clonagem\kit-clonagem.git remote update --prune
```

Nas outras máquinas da rede:

```powershell
git clone \\SERVIDOR\imagens\kit-clonagem.git kit-clonagem     # Windows
```

```bash
sudo mount -t cifs //SERVIDOR/imagens /mnt/servidor -o username=clonagem
git clone /mnt/servidor/kit-clonagem.git kit-clonagem          # Linux
```

**O espelho é uma cópia de leitura, não a fonte da verdade.** A fonte continua
sendo o GitHub: o trabalho vai para lá por `git push`, e só depois o espelho é
atualizado com o `remote update` acima. Fazer `push` para o espelho cria uma
divergência que ninguém percebe até doer.

Se o Git reclamar de `dubious ownership` ao usar o caminho de rede:

```powershell
git config --global --add safe.directory "%(prefix)///SERVIDOR/imagens/kit-clonagem.git"
```

## Problemas comuns

| Sintoma | Causa provável |
|---------|----------------|
| `mount error(13): Permission denied` | Senha errada, ou conta sem permissão em uma das duas travas (compartilhamento **e** NTFS) |
| `mount error(112): Host is down` | Quase sempre é versão de SMB: tente `--versao 2.1` |
| `mount error(115): Operation now in progress` | Firewall bloqueando, ou perfil de rede como *Public* no servidor |
| Montou, mas não escreve | Permissão NTFS ausente — o script avisa antes de você perder tempo |
| `mount.cifs` não encontrado | Fora do Clonezilla Live: `sudo apt install cifs-utils` |
| Cópia lenta demais | Wi-Fi, ou negociação em 100 Mbps: confira o cabo e a porta do switch |

Quando a rede estiver fora do ar, o caminho do pendrive continua valendo
inteiro — veja [07-sincronizar-maquinas.md](07-sincronizar-maquinas.md).
