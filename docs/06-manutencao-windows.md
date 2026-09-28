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

Leva de 2 a 10 minutos (varre o disco inteiro). Ao final salva um relatório na
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
