# Impressora de código de barras (Bixolon verde) — etiqueta sai em branco

Sintoma: a impressora **avança a etiqueta mas não imprime nada**.

| Nome no Windows | Porta | Impressora |
|---|---|---|
| Etiqueta Fiscal | USB006 | Bixolon fiscal — **única** para etiqueta de envio |
| Codigo de Barra | USB003 | Bixolon verde |
| ARGOS - Codigo Estoque | USB003 | Bixolon verde |

> O script desta página **recusa** a USB006 e qualquer impressora com
> "Fiscal" no nome. Etiqueta de envio nunca sai pela verde.

Faça na ordem: os passos 1 e 2 dizem se o problema é físico ou do Windows.

## 1. Autoteste (sem computador)

A impressora imprime a própria configuração, sem passar pelo Windows.

1. Desligue a impressora.
2. Segure o botão **FEED** e ligue.
3. Solte quando começar a imprimir (na maioria dos Bixolon, 1 a 2 segundos;
   se não funcionar, veja o manual do modelo na etiqueta de baixo).

| Resultado | Significa |
|---|---|
| Autoteste **impresso** | Cabeça e papel OK — o problema está no Windows/driver. Vá ao passo 3. |
| Autoteste **em branco** | Problema físico: papel, ribbon ou cabeça. Faça o passo 2. |

Guarde o papel do autoteste: ele mostra **Print Method** (Direct/Thermal
Transfer), **Darkness/Density** e **Emulation/Language** (ZPL, EPL, SLCS).

## 2. Teste da unha (o papel é térmico?)

Risque a etiqueta com a unha, com força.

- **Ficou preto** → papel térmico direto: **não usa ribbon**. A impressora
  precisa estar em *Direct Thermal*. Confira também se o lado brilhante está
  virado para a cabeça (para cima, na maioria dos modelos).
- **Não marcou** → papel de transferência: **precisa de ribbon**, com o lado
  da tinta encostado na etiqueta. Sem ribbon, ou com o ribbon invertido, sai
  em branco.

Se estiver tudo certo e ainda sair em branco: limpe a cabeça com álcool
isopropílico (cotonete, impressora desligada e fria) e confira se a tampa
fecha até travar.

## 3. Diagnóstico no Windows (só leitura)

PowerShell na pasta dos scripts:

```powershell
powershell -ExecutionPolicy Bypass -File .\4-impressora-codigo-barras.ps1
```

Mostra a porta e o driver de cada impressora, o status, a fila e as
propriedades do driver (as linhas com `<<<` são modo de impressão, escuridão
e mídia). Salva um relatório na Área de Trabalho. **Não imprime nada.**

Fila travada com trabalhos antigos:

```powershell
.\4-impressora-codigo-barras.ps1 -LimparFila
```

## 4. Etiqueta de teste

```powershell
.\4-impressora-codigo-barras.ps1 -Imprimir -Escuro 25
```

Envia **uma** etiqueta direto para a impressora (sem o driver): tarja preta,
texto `TESTE ARGOS` e código de barras `123456`. A escuridão e o modo valem só
para essa etiqueta; nada fica gravado na impressora.

| Saiu | Fazer |
|---|---|
| Tudo nítido | Impressora OK. Ajuste o **driver**: Painel de Controle → Impressoras → *Codigo de Barra* → Preferências de impressão → modo **Térmica direta** (se o papel passou no teste da unha) e escuridão alta. Repita em *ARGOS - Codigo Estoque*. |
| Claro/falhado | Repita com `-Escuro 30`. Continuando claro: limpe a cabeça. |
| Símbolos ou texto estranho | A impressora não está em ZPL. Veja a linguagem no autoteste. |
| Em branco | Não é software. Volte aos passos 1 e 2. |

Usa ribbon (papel não marcou com a unha)? Teste em modo transferência:

```powershell
.\4-impressora-codigo-barras.ps1 -Imprimir -Escuro 25 -Modo Transferencia
```

## Causa mais comum

Driver ou impressora em **Thermal Transfer** com etiqueta **térmica direta**
e sem ribbon: a etiqueta avança, a cabeça aquece pouco e nada aparece. A
correção é mudar para **Direct Thermal** nas preferências do driver.
