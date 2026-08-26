# 9. Liberar espaço da máquina mandando para o HD

Regra que manda aqui, tirada da nota `MANUTENCAO - laudo do notebook` do Cérebro:

> **"não exclua, envia para uma pasta de backup no HD externo, tem muito espaço lá"**

Destino: `E:\_Quarentena-Argos\<AAAA-MM-DD>\`. **HD desligado = não limpa.**

Nada é apagado sem o hash bater. O protocolo é sempre o mesmo, nesta ordem:

```
COPIA  →  CONFERE SHA-256  →  só então APAGA
```

Mover direto entre volumes é copiar e apagar sem conferir — por isso os scripts
nunca fazem isso.

## A ordem dos três passos

Cada um tem um papel diferente. Rodar fora de ordem é o que faz apagar o que não
devia ou mover o que nem estava ocupando espaço.

| # | Script | O que faz | Apaga? |
|---|--------|-----------|--------|
| 1 | `1-diagnostico.ps1` | Mede o disco de verdade e mostra quem está ocupando | não |
| 2 | `2-limpeza.ps1` | Cache e temporário — o que o Windows **recria sozinho** | sim, com `-Executar` |
| 3 | `5-quarentena-hd.ps1` | Material do usuário que não é usado aqui → vai para o HD | só depois de conferir |

Cache não vai para o HD: não faz sentido guardar o que o sistema refaz. Para
isso é o passo 2. O HD recebe o que **você pode precisar de novo um dia**.

## Passo a passo

```powershell
# 1. Ver onde o disco está
powershell -ExecutionPolicy Bypass -File .\scripts\windows\1-diagnostico.ps1

# 2. Limpar o descartável (simula por padrão)
.\scripts\windows\2-limpeza.ps1              # mostra o que faria
.\scripts\windows\2-limpeza.ps1 -Executar    # limpa de verdade

# 3. Analisar o que pode sair da máquina (NÃO move nada)
.\scripts\windows\5-quarentena-hd.ps1

# 4. Copiar para o HD e conferir hash (ainda NÃO apaga)
.\scripts\windows\5-quarentena-hd.ps1 -Executar

# 5. Só depois de ler o relatório, liberar o espaço
.\scripts\windows\5-quarentena-hd.ps1 -Executar -Remover
```

Os passos 4 e 5 são separados de propósito: entre um e outro você lê o relatório
e decide. Um item cujo hash não bateu **não é apagado** — o script segue para o
próximo e avisa no resumo.

## "Se precisar é só buscar no HD"

Cada rodada grava um `MANIFESTO.csv` na pasta do dia e acrescenta as linhas ao
`E:\_Quarentena-Argos\INDICE.csv`: o que saiu, de onde saiu, quando, quantos
arquivos e o tamanho.

```powershell
# o que já está no HD
.\scripts\windows\5-quarentena-hd.ps1 -Listar

# trazer de volta para o lugar de origem
.\scripts\windows\5-quarentena-hd.ps1 -Restaurar "Videos-2024" -Executar
```

Restaurar **copia** de volta: o material continua no HD. Você decide depois se
manda embora de lá.

## O que nunca sai da máquina

O script recusa estes, e diz o motivo no relatório:

| Item | Por quê |
|------|---------|
| `claudevm.bundle`, `.claude` | VM e skills do Claude Code, em uso |
| `hiberfil.sys` | é ela que salva o trabalho quando a bateria acaba |
| `pagefile.sys`, `swapfile.sys` | memória virtual do Windows |
| `Windows`, `Program Files` | sistema e programas |
| `Argos-Cerebro` | é a fonte da verdade |
| `ArgosPrint`, `catalogo_argos`, `impressora_argos` | agente de etiquetas em produção |
| `07-Financeiro`, `espionagem` | sigilo — decisão manual, nunca automática |

## A armadilha de medição (não cair de novo)

`Get-ChildItem | Measure-Object Length` devolve o tamanho **lógico**. Arquivo do
OneDrive que está só na nuvem aparece com o tamanho cheio e **não ocupa disco
nenhum**. Foi assim que um OneDrive de "49,5 GB" virou 8,89 GB reais, e uma
pasta de "32 GB" ocupava 10 MB.

Quem está só na nuvem tem o atributo `FILE_ATTRIBUTE_RECALL_ON_DATA_ACCESS`
(`0x400000`). Os scripts deste kit descontam esses arquivos ao medir — se você
escrever qualquer medição nova, desconte também.

## Critérios que o passo 3 usa

Só entra na lista o que é, ao mesmo tempo:

- maior que `-MinimoMB` (padrão 200 MB), e
- sem alteração há mais de `-DiasParado` dias (padrão 60), e
- fora da lista de protegidos, e
- não é placeholder de nuvem.

Pastas varridas: `Downloads`, `Videos`, `Documents`, `Pictures`, `Desktop`.
Para incluir outra: `-Incluir "D:\Projetos-antigos"`. Para afrouxar:
`-MinimoMB 50 -DiasParado 30`.

## Se o disco continuar cheio

Os grandes de sempre, na ordem em que costumam aparecer:

- **cache do Chrome** — vários GB quando há muitos perfis; o Cérebro tem o
  `chrome-cache-quarentena.ps1`, que manda o cache para o HD sem tocar em
  senha, favorito, histórico ou cookie. Chrome fechado, senão o cache está em uso;
- **pagefile e hiberfil** — juntos passam fácil de 25 GB. Não são lixo. Só mexa
  com decisão consciente (`-DesativarHibernacao` no `2-limpeza.ps1`);
- **backups antigos** — `mover-backups.ps1` do kit do servidor mantém os 5 mais
  recentes no `C:` e manda o resto para o HD, com hash;
- **WinSxS** — `2-limpeza.ps1 -Executar -LimparComponentes` (demora).
