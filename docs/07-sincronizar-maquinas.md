# Sincronizar as máquinas e as sessões do Claude Code

Aqui tem duas coisas para manter em dia: o **repositório** (scripts e
documentação, que vivem no GitHub) e o **pendrive** (imagens e logs, que não
vão para o Git). São caminhos diferentes.

## O que fica onde

| Conteúdo | Onde mora | Como sincroniza |
|----------|-----------|-----------------|
| Scripts, docs, `CLAUDE.md` | GitHub | `git pull` / `git push` |
| Imagens `.img`, `.iso`, `.zip` | Pendrive, partição `IMAGENS` | Cópia manual (`rsync`) |
| Logs de clonagem | Pendrive, `logs/` | Cópia manual, se quiser guardar |

As imagens estão no `.gitignore` de propósito: uma imagem de Windows 11
comprimida ocupa de 12 a 25 GB e o GitHub recusa arquivos acima de 100 MB.

## Sessões do Claude Code não conversam entre si

Uma sessão na máquina KHAOSOMNI e uma sessão no navegador não trocam mensagens
diretamente e não enxergam o disco uma da outra. O que as deixa alinhadas é o
repositório: as duas leem o mesmo `CLAUDE.md`, os mesmos scripts e a mesma
documentação assim que dão `git pull`.

Ou seja: **o que não está commitado e enviado não existe para a outra
máquina.** Terminou um trecho de trabalho, envie.

## Na máquina KHAOSOMNI (primeira vez)

```bash
git clone https://github.com/HudsonSantanna/HudsonSantanna.git kit-clonagem
cd kit-clonagem
```

O `CLAUDE.md` na raiz é lido automaticamente quando você abrir o Claude Code
nessa pasta — a sessão de lá já começa com as mesmas convenções desta.

## No começo de cada sessão

```bash
git fetch origin
git status          # confira em que branch você está
git pull origin <sua-branch>
```

Se alguém mexeu enquanto você estava fora, isso traz o trabalho de volta antes
de você criar conflito em cima dele.

## Ao terminar um trecho de trabalho

```bash
shellcheck -S info -x -P scripts scripts/*.sh scripts/lib/*.sh
for f in scripts/*.sh scripts/lib/*.sh; do bash -n "$f"; done

git add -A
git commit -m "Descrição curta do que mudou"
git push -u origin <sua-branch>
```

Rode a verificação antes do commit: é a mesma que o GitHub roda sozinho no
push, então falhar aqui é mais rápido e mais barato do que falhar lá.

## Branches

Cada sessão do Claude Code trabalha em uma branch própria, com nome no formato
`claude/<assunto>-<sufixo>`. Isso evita que duas sessões escrevam no mesmo
lugar ao mesmo tempo. O encontro acontece na `main`, pelo pull request.

Para trazer para a sua branch o que já foi aprovado na `main`:

```bash
git fetch origin main
git merge origin/main
```

## Sincronizar as imagens entre pendrives

> Se houver um servidor na rede, esta parte fica dispensável: as imagens
> ficam no servidor e o Clonezilla lê e grava direto lá. Veja
> [08-servidor-de-rede.md](08-servidor-de-rede.md).

As imagens não passam pelo Git. Com os dois pendrives montados:

```bash
sudo mount -L IMAGENS /mnt/origem
sudo mount /dev/sdX2  /mnt/destino     # o segundo pendrive
sudo rsync -ah --info=progress2 /mnt/origem/imagens/ /mnt/destino/imagens/
sync
```

Confira o resultado antes de considerar pronto:

```bash
sudo ./scripts/verificar-pendrive.sh --dispositivo /dev/sdX
```

Guarde sempre uma cópia das imagens fora do pendrive. Pendrive de campo cai,
molha e some.

## Quando o pendrive já está pronto e os scripts mudaram

Não precisa preparar o pendrive de novo. Basta atualizar os scripts que estão
na partição de dados:

```bash
sudo mount -L IMAGENS /mnt/pendrive
sudo rsync -a --delete scripts/ /mnt/pendrive/scripts/
sudo rsync -a --delete docs/    /mnt/pendrive/docs/
sudo cp README.md /mnt/pendrive/docs/
sudo chmod +x /mnt/pendrive/scripts/*.sh
sync
```

São as mesmas cópias que o `preparar-pendrive.sh` faz no final — repare nas
barras no fim dos caminhos, elas são o que mantém cada pasta no lugar certo.
O Clonezilla fica na partição 1 e não é tocado por isso, então o pendrive
continua dando boot igual.
