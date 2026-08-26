# 3. Restaurar em lote

## Fluxo por máquina

1. Ligue a máquina com o pendrive e entre no menu de boot.
2. `Clonezilla live` → idioma → teclado → **`Enter_shell`**.
3. Execute:

```bash
sudo mount -L IMAGENS /home/partimag
sudo /home/partimag/scripts/restaurar-maquina.sh
```

O script lista as imagens disponíveis, pergunta qual usar e para qual disco,
mostra o que será apagado e exige a confirmação `RESTAURAR`.

Modo direto, para repetir em várias máquinas sem perguntas na tela:

```bash
sudo /home/partimag/scripts/restaurar-maquina.sh \
  -i padrao-win11 -d /dev/nvme0n1 --depois poweroff
```

Ver o que há no pendrive sem restaurar nada:

```bash
sudo /home/partimag/scripts/restaurar-maquina.sh --listar
```

## Discos de tamanhos diferentes

- **Destino maior que a origem**: funciona; sobra espaço não alocado no fim do
  disco. Expanda a última partição depois (Gerenciamento de Disco no Windows,
  `growpart`/GParted no Linux).
- **Destino menor que a origem**: só funciona com `--proporcional`, que
  redimensiona as partições na mesma proporção (`-k1` do Clonezilla), e desde que
  os dados realmente caibam. O script avisa quando detecta esse caso.

```bash
sudo /home/partimag/scripts/restaurar-maquina.sh -i padrao-win11 -d /dev/sda --proporcional
```

## Depois de restaurar cada máquina

### Windows
- Se a imagem passou por `sysprep /generalize`, o primeiro boot roda o OOBE:
  defina nome da máquina, ingresso no domínio e ative a licença.
- Instale os drivers específicos daquele modelo.

### Linux
- Ajuste o hostname (`hostnamectl set-hostname`) e confirme que o `machine-id`
  foi recriado (`cat /etc/machine-id` não pode ser igual em duas máquinas).
- Confira `/etc/fstab` se você recriou ou redimensionou partições.

## Ritmo de trabalho e paralelismo

Uma imagem de 20 GB comprimida gravada de um pendrive USB 3.0 leva tipicamente
de 8 a 20 minutos por máquina, limitada pela leitura do pendrive.

Para escalar:

- **Vários pendrives**: prepare 3 ou 4 iguais e restaure em paralelo. É a saída
  mais simples e não depende de rede.
- **HD/SSD externo USB**: use `--permitir-nao-removivel` no preparo; a leitura é
  muito mais rápida que a de um pendrive comum.
- **Multicast pela rede**: para dezenas de máquinas ao mesmo tempo, o caminho é
  o [DRBL](https://drbl.org/) com Clonezilla SE, que restaura todas as máquinas
  simultaneamente a partir de um servidor. Este kit cobre o cenário
  pendrive-a-pendrive; o pendrive continua útil como ferramenta de resgate.

## Registro

Cada restauração grava um log em `logs/restaurar-<imagem>-<disco>-<data>.log` na
partição `IMAGENS`. Mantenha também uma planilha simples com patrimônio, modelo,
imagem usada e data — é o que responde "essa máquina recebeu qual versão?".
