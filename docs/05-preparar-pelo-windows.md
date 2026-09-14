# 5. Preparar o pendrive a partir do Windows

O `scripts/preparar-pendrive.sh` roda em Linux. Se a máquina que você tem à mão
é Windows, use um dos caminhos abaixo — o pendrive resultante faz o mesmo
serviço, e os scripts de captura/restauração continuam valendo, porque eles
rodam dentro do Clonezilla Live (que é Linux).

## Caminho recomendado: Ventoy

O Ventoy instala um gerenciador de boot no pendrive e você simplesmente
**copia o ISO** para dentro dele. Aceita vários ISOs no mesmo pendrive e deixa o
espaço restante livre para as imagens.

1. Baixe o Ventoy: <https://www.ventoy.net/en/download.html> (`ventoy-x.y.z-windows.zip`)
2. Extraia e execute `Ventoy2Disk.exe` **como administrador**
3. Em `Opção` → `Estilo de Partição`, escolha **MBR** (funciona em BIOS e UEFI)
4. Selecione o pendrive e clique em **Instalar** — o dispositivo é apagado
5. Baixe o **ISO** do Clonezilla em <https://clonezilla.org/downloads/> (amd64, formato `iso`)
6. Copie o `.iso` para dentro da partição `Ventoy` que apareceu no Explorador
7. Crie nessa mesma partição as pastas `imagens`, `logs` e `scripts`
8. Copie a pasta `scripts/` deste repositório para a pasta `scripts` do pendrive

No boot, o Ventoy mostra a lista de ISOs; escolha o Clonezilla.

> A partição do Ventoy é exFAT. O Clonezilla grava imagens em exFAT sem
> problema, mas ao rodar os scripts use `--rotulo Ventoy`, porque o rótulo da
> partição não será `IMAGENS`:
>
> ```bash
> sudo mount -L Ventoy /home/partimag
> sudo /home/partimag/scripts/clonar-maquina.sh --rotulo Ventoy
> ```

## Alternativa: Rufus

Grava o ISO direto, sem menu. Mais simples, porém o pendrive fica com uma
partição só de boot — as imagens precisam ir para outro disco (HD externo).

1. Baixe o Rufus: <https://rufus.ie/>
2. Selecione o pendrive e o ISO do Clonezilla
3. Esquema de partição: **MBR**; sistema de destino: **BIOS ou UEFI**
4. Clique em **Iniciar** e, se perguntar, escolha **Gravar em modo Imagem ISO**

Depois, no Clonezilla, monte o disco externo como repositório:

```bash
sudo mount /dev/sdX1 /home/partimag
```

## Alternativa: usar o script pelo próprio Clonezilla

Se você já tem um pendrive com Clonezilla funcionando, dá para preparar o
**segundo** pendrive por ele: dê boot no Clonezilla, `Enter_shell`, conecte o
pendrive novo e rode o `preparar-pendrive.sh` a partir do primeiro — o ambiente
do Clonezilla é Linux e tem `parted`, `mkfs.vfat` e `unzip`. Use `--zip` com o
arquivo já baixado, já que ali você pode não ter internet.

## Por que não WSL

O WSL2 não enxerga discos USB por padrão — seria preciso instalar o `usbipd-win`
e anexar o dispositivo manualmente a cada uso. Funciona, mas dá mais trabalho do
que o Ventoy e falha de formas difíceis de diagnosticar. Não recomendo.
