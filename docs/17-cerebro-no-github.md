# 17. Cérebro no GitHub, sozinho

## O problema

O Claude na nuvem, o notebook fora da rede e qualquer máquina que não alcança
o `\\KHAOSOMNI` só enxergam o Cérebro pelo **GitHub**. Até hoje, o envio para
lá era **manual** ("o Claude faz ao fechar marco"). Quando ninguém fecha
marco, o GitHub para no tempo: em 28/09 ele ainda estava em **07/09**, e todo
mundo que lia por ele trabalhava com três semanas de memória a menos, sem
perceber.

## O agente

O `scripts/windows/cerebro-no-github.ps1` roda no **KHAOSOMNI** como tarefa
agendada (`ARGOS - Cerebro no GitHub`), a cada 30 minutos. Em cada rodada:

1. `git add -A`. O `.gitignore` do Cérebro já segura financeiro, espião,
   credenciais, `_travas` e as cópias `*.do-notebook-*`.
2. **Travas**. Se qualquer uma disparar, o script desfaz o `add` e não envia nada:
   - caminho com cara de segredo (`credencia`, `senha`, `token`, `.env`,
     `.pem`, `SERVIDOR-CONFIG`…);
   - linha nova com cara de chave (`sk-ant-`, `ghp_`, `AKIA`,
     `PRIVATE KEY`…). O valor **não** vai para o log;
   - mais de 400 arquivos de uma vez, como a enxurrada de 3.290 `_travas` de 07/09.
3. `commit`, `fetch` e `merge` do que outra máquina tenha enviado.
   **Conflito** faz o script desfazer o merge e parar: conflito se resolve à mão.
4. `push`, e depois confere se o GitHub ficou igual ao local.

Ele nunca usa `--force`, nunca faz rebase e nunca apaga arquivo. Também recusa
rodar fora do KHAOSOMNI, porque ter um escritor só evita duas máquinas brigando
em merge.

O log fica em `%LOCALAPPDATA%\Argos\cerebro-no-github.log`, **fora** do
Cérebro, para o próprio log não virar mudança a enviar.

## Instalar (uma vez, no KHAOSOMNI)

```powershell
# 1. copiar o script para a pasta de scripts do servidor
Copy-Item scripts\windows\cerebro-no-github.ps1 "$env:USERPROFILE\Scripts\"
cd "$env:USERPROFILE\Scripts"

# 2. ensaio: mostra o que enviaria, não grava nada
powershell -ExecutionPolicy Bypass -File .\cerebro-no-github.ps1 -Simular

# 3. uma rodada de verdade: a primeira leva as três semanas atrasadas
powershell -ExecutionPolicy Bypass -File .\cerebro-no-github.ps1

# 4. instalar a tarefa (a cada 30 min)
powershell -ExecutionPolicy Bypass -File .\cerebro-no-github.ps1 -Instalar
```

A **primeira rodada** é a que importa ler. Se ela parar numa trava, é sinal de
que existe algo no Cérebro que não devia ir ao GitHub: coloque no `.gitignore`
do Cérebro e rode de novo. Não aumente o limite só para passar.

A tarefa roda com o usuário logado (`Interactive`), porque é ele quem tem a
credencial do GitHub guardada no Windows. Se o push começar a falhar por
credencial, rode um `git push` à mão em `C:\Users\hudso\Argos-Cerebro` e digite
a senha ou o token uma vez.

## Quem vigia o vigia

A tarefa entrou em `rotinas-essenciais.txt` com o nome exato. Então o
`/verificar-agentes` acusa se ela:

- estiver **desligada**, e religa com `ativar`;
- tiver **sumido**;
- tiver a **última execução com falha**, que é o caso de trava ou conflito
  esperando você.

## A outra ponta: a nuvem

Numa sessão do Claude Code na nuvem, o Cérebro é baixado do GitHub
(`HudsonSantanna/argos-cerebro`) para `/home/user/argos-cerebro`. Com o agente
rodando, o que chega ali tem no máximo 30 minutos de atraso em relação ao
servidor.
