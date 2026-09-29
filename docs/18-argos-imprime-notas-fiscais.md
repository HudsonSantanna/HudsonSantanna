# 18. Argos imprime as notas fiscais no lugar do agente do UpSeller

Na **`HUDSONINTEGRAR`**, quem imprime a etiqueta de envio e o DANFE na BIXOLON
**`Etiqueta Fiscal`** deixa de ser o agente local do UpSeller e passa a ser o
agente Argos. O agente do UpSeller sai da inicialização do Windows.

> **Achado de 29/09 na HUDSONINTEGRAR:** lá **não existe** agente local do
> UpSeller. O `9-upseller-inicializacao.ps1` não achou nada, e hoje a etiqueta
> abre numa janela do Chrome e sai por Ctrl+P → `Etiqueta Fiscal`. Não há o
> que desligar. **Não desligue** o `Seagull Drivers V3` (driver das Bixolon)
> nem o `Argos Print` (etiqueta de estoque) que aparecem na inicialização.
> O script 9 fica para as máquinas que tiverem o agente do UpSeller.

## O que muda e o que não muda

| | Antes | Depois |
|---|---|---|
| **Emitir** a NF-e e mandar para Shopee / Mercado Livre / TikTok | site do UpSeller | **site do UpSeller (igual)** |
| **Imprimir** etiqueta de envio e DANFE | agente local do UpSeller | **agente Argos** (`argos-notas-fiscais.ps1`) |
| Agente do UpSeller no início do Windows | sobe sozinho | **desligado** (dá para religar) |
| Impressora `Etiqueta Fiscal`, fila, driver, impressora padrão | — | **intocados** |

Desligar o agente do UpSeller **não** para a emissão das notas: ela acontece
no site `app.upseller.com`, não no computador.

## Como o agente Argos imprime

```
UpSeller > Pedidos > imprimir etiqueta/DANFE > baixar PDF
        ▼  o Chrome salva em
C:\Argos\NotasFiscais\Entrada
        ▼  argos-notas-fiscais.ps1 (tarefa "ARGOS - Notas Fiscais", no logon)
BIXOLON "Etiqueta Fiscal"
        ▼
C:\Argos\NotasFiscais\Impressos\<data>\   (ou Erro\, com o motivo no log)
```

- **PDF** sai pelo **SumatraPDF** em linha de comando, sem abrir janela e sem
  mudar escala (`-AjustePdf noscale`; use `fit` se a etiqueta sair cortada).
- **ZPL / PRN / TXT** vão em RAW direto para a fila, o mesmo caminho do
  `6-configurar-etiquetadora.ps1`.
- Arquivo ainda baixando (`.crdownload`, `.part`, `.tmp`) é ignorado até
  terminar.
- Log: `%LOCALAPPDATA%\Argos\notas-fiscais.log`.

O **Chrome** precisa salvar nessa pasta. O jeito mais simples é
*Configurações › Downloads › Local* = `C:\Argos\NotasFiscais\Entrada`. Se
essa máquina baixa outras coisas pelo Chrome, ligue *"Perguntar onde salvar
cada arquivo"* e escolha a pasta só para os PDFs do UpSeller.

## Ordem de ativação: primeiro provar, depois desligar

Desligar o UpSeller **antes** de o Argos imprimir deixaria a expedição sem
etiqueta. Por isso a ordem é esta:

```powershell
cd <repositório>\scripts\windows

# 1. Ver o que do UpSeller sobe com o Windows. Não muda nada.
.\9-upseller-inicializacao.ps1

# 2. SumatraPDF (se ainda não tiver)
winget install -e --id SumatraPDF.SumatraPDF

# 3. Testar o agente Argos com UM PDF real do UpSeller:
#    baixe uma etiqueta para C:\Argos\NotasFiscais\Entrada e rode
.\argos-notas-fiscais.ps1 -UmaVez
#    -> a etiqueta saiu inteira, na Etiqueta Fiscal, sem cortar? Siga.

# 4. Instalar o agente Argos (sobe sozinho no logon)
.\argos-notas-fiscais.ps1 -Instalar

# 5. Só agora: tirar o UpSeller da inicialização (faz backup antes)
.\9-upseller-inicializacao.ps1 -Desligar -Confirmar
#    ... e fechar o que está rodando agora
.\9-upseller-inicializacao.ps1 -Desligar -Encerrar -Confirmar
```

Chave de máquina (HKLM), pasta de inicialização de todos os usuários e
serviço exigem o PowerShell **como administrador**. Sem isso, o script
lista esses itens e pula.

## Voltar atrás

```powershell
.\9-upseller-inicializacao.ps1 -Religar -Confirmar   # UpSeller volta a subir
.\argos-notas-fiscais.ps1 -Desinstalar               # remove a tarefa do Argos
```

O `-Desligar` guarda o estado anterior em
`C:\Argos-Backups\_checkpoints\<AAAA-MM-DD_HHmm>\upseller\` e o `-Religar`
usa o backup mais recente. Nada é desinstalado nem apagado.

## Testes de aceitação

- [ ] Um PDF de etiqueta do UpSeller cai na `Entrada` e sai na `Etiqueta
      Fiscal` em poucos segundos, inteiro e sem escala errada.
- [ ] O arquivo some da `Entrada` e aparece em `Impressos\<hoje>\`.
- [ ] Um arquivo `.docx` jogado na `Entrada` vai para `Erro\` com o motivo no log.
- [ ] Depois de reiniciar: a tarefa `ARGOS - Notas Fiscais` está rodando e o
      UpSeller **não** subiu sozinho.
- [ ] A etiqueta de **estoque** (ArgosPrint, `127.0.0.1:9110`) continua saindo
      na `Codigo de Barra` / `ARGOS - Codigo Estoque`.
- [ ] Uma NF-e emitida no site do UpSeller continua chegando ao marketplace.

## Quando não imprime

Siga a mesma ordem do [doc 14](14-diagnostico-etiquetadora.md): dispositivo
USB presente → spooler → fila → agente. Fila apontando para porta USB morta
**aceita o trabalho e não imprime nada**. Veja o
[doc 15](15-vigia-etiquetadoras.md) e rode o `5-diagnostico-etiquetadora.ps1`
antes de suspeitar do agente.
