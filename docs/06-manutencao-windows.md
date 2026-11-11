# Manutenção da máquina — 3 passos

Scripts para PowerShell no Windows. **Nada é apagado sem você mandar.**

## Antes de começar

1. Ligue o HD externo (o passo 3 vai precisar dele)
2. Abra o **PowerShell como administrador**: Windows + X → **Terminal (Admin)**
3. Vá até a pasta onde salvou estes arquivos:
   ```powershell
   cd "$env:USERPROFILE\Downloads\manutencao"
   ```

## Passo 1 — Diagnóstico (só lê, não mexe em nada)

```powershell
powershell -ExecutionPolicy Bypass -File .\1-diagnostico.ps1
```

Varre o disco inteiro, lendo direto pelo .NET (bem mais rápido que o
Get-ChildItem). Ao final salva um relatório na
Área de Trabalho com:

- espaço livre e uso de cada volume
- **saúde física dos discos** (SMART: horas ligado, desgaste, erros) — se algum
  aparecer diferente de `Healthy`, pare tudo e faça backup antes de qualquer limpeza
- as 20 maiores pastas e os 30 maiores arquivos
- **candidatos a mover**: arquivos grandes sem alteração há mais de um ano
- quanto dá para recuperar em caches e temporários
- programas instalados por tamanho e o que inicia com o Windows

Leia o relatório antes de seguir. Marque o que não pode sumir.

## Passo 2 — Limpeza (caches e temporários)

Primeiro simule — este comando **não apaga nada**, só mostra quanto liberaria:

```powershell
powershell -ExecutionPolicy Bypass -File .\2-limpeza.ps1
```

Gostou dos números? Execute de verdade:

```powershell
powershell -ExecutionPolicy Bypass -File .\2-limpeza.ps1 -Executar
```

Opções extras:

| Parâmetro | O que faz | Quando usar |
|---|---|---|
| `-EsvaziarLixeira` | Esvazia a Lixeira | Depois de conferir o que tem lá dentro |
| `-DesativarHibernacao` | Remove o `hiberfil.sys` | Libera vários GB; a suspensão continua funcionando |
| `-LimparComponentes` | DISM no WinSxS | Libera bastante, mas demora ~20 min e impede desinstalar atualizações antigas |

Exemplo completo:

```powershell
.\2-limpeza.ps1 -Executar -EsvaziarLixeira -DesativarHibernacao
```

O script **não toca** em Documentos, Fotos, Vídeos nem na pasta Downloads.

## Passo 3 — Tirar arquivos grandes para o HD externo

Pegue no relatório do passo 1 as pastas grandes e antigas. Para cada uma:

```powershell
# copia e confere (não apaga nada da origem)
.\3-mover-para-hd.ps1 -Origem "C:\Users\hudso\Videos\Antigos" -Destino "E:\Arquivo"
```

Ele copia com robocopy, depois **confere tamanho e quantidade de arquivos**.
Se não bater, avisa e não apaga nada.

Confira os arquivos no HD externo. Só então libere o espaço:

```powershell
.\3-mover-para-hd.ps1 -Origem "C:\Users\hudso\Videos\Antigos" -Destino "E:\Arquivo" -Remover
```

Ele pede que você digite `APAGAR` para confirmar.

> Troque `E:` pela letra do seu HD externo, e o caminho de origem pelo que
> aparecer no relatório.

## Máquina lenta: memória perto de 90% e disco em 100%

Quando o Gerenciador de Tarefas mostra **Memória acima de 90% e Disco em 100%**
ao mesmo tempo, a RAM acabou e o Windows passou a usar o disco como memória.
Tudo fica lento, inclusive os passos acima. Alivie a memória **antes** do
diagnóstico:

```powershell
# só mostra o que ocupa memória e disco, e o que desligaria
powershell -ExecutionPolicy Bypass -File .\aliviar-memoria.ps1

# desliga de verdade
powershell -ExecutionPolicy Bypass -File .\aliviar-memoria.ps1 -Executar
```

O relatório mostra:

- RAM total e livre (com aviso se a máquina tiver 8 GB ou menos)
- os 20 programas que mais ocupam memória, somando os processos de cada um
  (o Chrome, por exemplo, abre dezenas)
- quem está lendo/escrevendo no disco, medido por 5 segundos. Se o primeiro
  for `System` ou `Memory Compression`, é o Windows trocando memória com o
  disco: falta RAM

Com `-Executar` ele **desliga só uma lista fechada**:

| Desliga | Por quê |
|---|---|
| SysMain (Superfetch) | Pré-carrega programas na RAM; com pouca memória e disco a 100% só atrapalha |
| Windows Search (indexador) | Lê o disco o tempo todo. A busca continua funcionando, só mais devagar (a pesquisa do Outlook também) |
| Telemetria, relatório de erros, mapas offline, fax, Xbox, modo demo de loja, componentes de IA | Não fazem falta numa máquina de trabalho |
| Widgets, Vincular ao Celular, Xbox Game Bar, Cortana, Skype (só fecha) | Ficam abertos em segundo plano sem uso |

**Nunca mexe** em Chrome, Edge, node, python e PowerShell (os vigias usam),
spooler e impressoras, Windows Update, antivírus e Agendador de Tarefas. O
Chrome aparece no relatório, mas quem decide fechar abas é você.

> **Não espere muito dos serviços.** Na primeira máquina testada (memória a
> 92%), desligar todos eles liberou só uns 0,1 GB. A parte que mais ajuda é o
> **relatório**: ele mostra que quem ocupa a memória são os programas abertos
> (Chrome com dezenas de abas, app do ChatGPT, WebView2). Fechar esses programas
> libera mais do que todos os serviços juntos. E se a RAM livre fica abaixo de
> 1 GB com o uso normal, a solução é mais memória. Veja em Gerenciador de
> Tarefas › Desempenho › Memória quantos **slots** estão em uso.

Os serviços ficam desativados também depois de reiniciar. A configuração
original fica guardada em `C:\ProgramData\Manutencao\servicos-originais.json`,
e para voltar tudo como era:

```powershell
powershell -ExecutionPolicy Bypass -File .\aliviar-memoria.ps1 -Desfazer
```

Se a máquina tem 8 GB ou menos e continua acima de 85% depois disso, a
solução de verdade é **mais um pente de memória**. Se o relatório do passo 1
mostrar disco `HDD`, um **SSD** é o que tira o disco dos 100%.

## Se o diagnóstico parecer travado

O WMI já travou nesta máquina (veja `docs/20-manutencao-vigias.md`, caso de
15/10). O `1-diagnostico.ps1` não depende mais dele para sistema, volumes e
inicialização. Saúde dos discos e pontos de restauração só existem pelo WMI,
então rodam à parte com limite de 60 s. Se o WMI não responder, o relatório
diz "WMI travado" e segue em frente. Reinicie a máquina fora do expediente e
rode de novo para ter esses dados.

## Se der "não é possível carregar o arquivo... não está assinado digitalmente"

É a política de execução do PowerShell. O `-ExecutionPolicy Bypass` nos comandos
acima já contorna isso. Se ainda assim reclamar, desbloqueie os arquivos:

```powershell
Get-ChildItem .\*.ps1 | Unblock-File
```

## Ordem de segurança

1. Diagnóstico primeiro — **nunca limpe sem olhar o relatório**
2. Se algum disco não estiver `Healthy`, faça backup antes de qualquer coisa
3. Limpeza só depois de simular
4. Mover arquivos: copiar → conferir → só então apagar

## O que ainda melhora a máquina (manual, 5 minutos)

- **Ctrl + Shift + Esc** → aba *Aplicativos de Inicialização*: desative o que
  você não usa (o relatório lista tudo que inicia com o Windows)
- **Configurações → Sistema → Armazenamento → Sensor de Armazenamento**: ligue
  para limpar temporários sozinho daqui pra frente
- Se o disco for **HDD** (não SSD), rode a desfragmentação; se for SSD, **não
  desfragmente** — o Windows já faz TRIM sozinho
