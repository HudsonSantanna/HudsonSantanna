# Arquivar pastas no HD externo

Para quando o disco interno está cheio e a pergunta é *"o que dessas pastas dá
para tirar daqui?"*.

O script `scripts/windows/4-arquivar-pastas.ps1` faz três coisas:

1. **Mede** cada pasta e mostra tamanho, quantidade de arquivos e data da última
   alteração — para você decidir com número, não com achismo
2. **Arquiva** no HD externo só o que você nomear: copia → confere por **hash
   SHA256** → e só então apaga a origem
3. **Deixa o caminho de volta**: um atalho no lugar da pasta que saiu, mais um
   índice em CSV com o que foi para onde

## Por que não "recortar e colar"

Recortar entre discos é um `Move`. Se ele falhar no meio — cabo solto, HD que
desconecta, disco cheio — sobra metade de cada lado e ninguém percebe na hora.
O script nunca move: ele copia, compara o hash de **cada arquivo** dos dois
lados e só apaga quando todos batem. Se um único hash não bater, ele avisa e
**não apaga nada**.

## Passo 1 — Ver o mapa

```powershell
.\scripts\windows\4-arquivar-pastas.ps1 -Origem "C:\Users\hudso\Desktop\Argos"
```

Somente leitura. Sai uma tabela ordenada da maior para a menor:

```
Pasta                              Tamanho  Arquivos       Ultima  Sugestao
--------------------------------------------------------------------------
Instaladores                      12,40 GB      1893   03/11/2024  ARQUIVAR  - instalador se baixa de novo
backup HD                          8,10 GB      6122   14/02/2025  ARQUIVAR  - backup nao precisa estar no disco
ArgosOmni                          2,30 GB      9841   26/08/2026  MANTER    - projeto ativo
                                   ^^ contem: .git,node_modules - projeto de codigo, NAO arquive sem pensar
```

A coluna **Sugestao** é chute a partir do nome da pasta. Ela não decide nada —
o script só age sobre pastas que você nomear explicitamente.

O aviso `contem: .git, node_modules` aparece quando a pasta é projeto de código.
Não é proibição, é um "olhe duas vezes".

## Passo 2 — Ensaiar

```powershell
.\scripts\windows\4-arquivar-pastas.ps1 -Origem "C:\Users\hudso\Desktop\Argos" `
    -Pastas "Instaladores","backup HD","todas as pastas 2306"
```

Mostra quanto seria liberado e se cabe no HD. **Não copia nem apaga nada.**

## Passo 3 — Executar

```powershell
.\scripts\windows\4-arquivar-pastas.ps1 -Origem "C:\Users\hudso\Desktop\Argos" `
    -Pastas "Instaladores","backup HD" -Confirmar
```

Uma pasta de cada vez, em quatro etapas visíveis: copiar → conferir por hash →
apagar → criar o atalho. A conferência por hash lê os dois lados inteiros, então
é a parte demorada: conte alguns minutos por GB.

O destino padrão é `E:\Backup HUDSON_SANTANA`. Se a letra do HD for outra:

```powershell
... -Destino "F:\Backup HUDSON_SANTANA"
```

## Passo 4 — Achar depois o que foi arquivado

```powershell
.\scripts\windows\4-arquivar-pastas.ps1 -Origem "C:\Users\hudso\Desktop\Argos" `
    -Procurar "nota fiscal"
```

Procura no HD e devolve o caminho completo. Além disso:

- no lugar de cada pasta que saiu fica um **atalho** `Nome (no HD E).lnk` — dois
  cliques com o HD ligado e a pasta abre
- o índice fica em `Desktop\indice-arquivados.csv` e uma cópia vai para
  `E:\Backup HUDSON_SANTANA\_indice-arquivados.csv`, para o caso de o disco
  interno se perder

## O que o script recusa arquivar

Lista **fechada** — nomes que ele nunca move, mesmo se você pedir:

`Windows`, `Program Files`, `Program Files (x86)`, `ProgramData`, `AppData`,
`Argos-Cerebro`, `Scripts`, `.git`, `.codex`, `.claude`, `.agents`,
`node_modules`, `dist`, `build`, `win-unpacked`

E qualquer caminho que passe por **OneDrive** — mover de lá apaga da nuvem e de
todas as outras máquinas.

## Se a pasta já existir no HD

O script pula e avisa, em vez de misturar duas versões da mesma pasta. Resolva a
mão qual das duas fica.

## Limites conhecidos

- Caminho com mais de 260 caracteres pode falhar no cálculo do hash. O script
  registra o arquivo como ilegível, a conferência não passa e **nada é apagado** —
  falha do lado seguro
- Arquivo aberto por outro programa não é copiado; feche tudo antes
- O hash é lido do disco recém-escrito, não do cache — mas se o HD externo estiver
  com defeito, nenhum script salva você. Veja a saúde dele em
  [docs/06-manutencao-windows.md](06-manutencao-windows.md), passo 1
