#!/usr/bin/env bash
#
# clonar-maquina.sh - Captura a imagem de um disco para o repositorio de
# imagens: o pendrive ou o servidor da rede do escritorio (o "cerebro").
# Deve ser executado dentro do Clonezilla Live (opcao Enter_shell).
#
set -euo pipefail

DIR_SCRIPT="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=lib/comum.sh
source "$DIR_SCRIPT/lib/comum.sh"
# shellcheck source=lib/rede.sh
source "$DIR_SCRIPT/lib/rede.sh"

DISCO=""
NOME=""
ROTULO_DADOS="IMAGENS"
REPOSITORIO="/home/partimag"
COMPRESSAO="-z1p"          # zstd paralelo: bom equilibrio tamanho x tempo
DEPOIS="choose"            # choose | reboot | poweroff | true
PARTICOES=""
VERIFICAR_IMAGEM=1
ASSUMIR_SIM=0
MODO_LOCAL=0
ARQUIVO_CONFIG=""
REPO_REMOTO=0

# Preenchidas pelas opcoes de rede; vencem o que estiver no rede.conf.
CLI_SERVIDOR=""; CLI_PROTOCOLO=""; CLI_CAMINHO=""; CLI_USUARIO=""
CLI_PORTA=""; CLI_CREDENCIAIS=""; CLI_DOMINIO=""; CLI_OPCOES=""; CLI_INTERFACE=""

ajuda() {
  cat <<'AJUDA'
Uso: sudo ./clonar-maquina.sh [opcoes]

Captura a imagem de um disco inteiro (ou de particoes especificas) e grava
no repositorio de imagens: o servidor da rede do escritorio, quando houver um
configurado, ou o proprio pendrive.

Opcoes:
  -d, --disco DEV         Disco de origem (ex.: /dev/nvme0n1). Padrao: perguntar.
  -n, --nome NOME         Nome da imagem. Padrao: modelo-AAAAMMDD-HHMM.
  -p, --particoes "a b"   Salva so estas particoes (ex.: "sda1 sda2").
  -r, --repositorio DIR   Onde gravar (padrao: /home/partimag).
      --rotulo NOME       Rotulo da particao de imagens (padrao: IMAGENS).
  -c, --compressao FLAG   -z1p (zstd, padrao), -z9p (zstd forte), -z0 (sem).
      --depois ACAO       choose (padrao), reboot, poweroff, true.
      --sem-verificar-imagem  Nao conferir a imagem apos gravar (mais rapido).
      --simular           Mostra o comando do ocs-sr sem executar.
      --sim               Nao pergunta confirmacao.
  -h, --ajuda             Esta mensagem.

Repositorio na rede do escritorio (o "cerebro" no servidor):
  -s, --servidor HOST     Servidor das imagens (IP ou nome). Ativa o modo rede.
      --protocolo P       ssh (padrao), nfs ou smb.
      --caminho CAMINHO   Caminho exportado (ssh/nfs) ou compartilhamento (smb).
  -u, --usuario NOME      Usuario no servidor.
      --porta N           Porta, quando nao for a padrao (22/2049/445).
      --credenciais ARQ   Chave SSH ou arquivo de credenciais do smb.
      --dominio NOME      Dominio Windows (smb).
      --opcoes-montagem O Opcoes extras de montagem, separadas por virgula.
      --interface IFACE   Interface de rede a usar (vazio: cabo conectado).
      --config ARQUIVO    rede.conf a usar (padrao: procura nos locais de sempre).
      --local             Ignora a rede e grava no pendrive.

Sem servidor configurado, o comportamento e o de sempre: pendrive.
AJUDA
}

# shellcheck disable=SC2034  # as CLI_* sao lidas por rede_aplicar_cli (lib/rede.sh).
while [ $# -gt 0 ]; do
  case "$1" in
    -d|--disco)       DISCO="${2:-}"; shift 2 ;;
    -n|--nome)        NOME="${2:-}"; shift 2 ;;
    -p|--particoes)   PARTICOES="${2:-}"; shift 2 ;;
    -r|--repositorio) REPOSITORIO="${2:-}"; shift 2 ;;
    --rotulo)         ROTULO_DADOS="${2:-}"; shift 2 ;;
    -c|--compressao)  COMPRESSAO="${2:-}"; shift 2 ;;
    --depois)         DEPOIS="${2:-}"; shift 2 ;;
    --sem-verificar-imagem) VERIFICAR_IMAGEM=0; shift ;;
    -s|--servidor)    CLI_SERVIDOR="${2:-}"; shift 2 ;;
    --protocolo)      CLI_PROTOCOLO="${2:-}"; shift 2 ;;
    --caminho)        CLI_CAMINHO="${2:-}"; shift 2 ;;
    -u|--usuario)     CLI_USUARIO="${2:-}"; shift 2 ;;
    --porta)          CLI_PORTA="${2:-}"; shift 2 ;;
    --credenciais)    CLI_CREDENCIAIS="${2:-}"; shift 2 ;;
    --dominio)        CLI_DOMINIO="${2:-}"; shift 2 ;;
    --opcoes-montagem) CLI_OPCOES="${2:-}"; shift 2 ;;
    --interface)      CLI_INTERFACE="${2:-}"; shift 2 ;;
    --config)         ARQUIVO_CONFIG="${2:-}"; shift 2 ;;
    --local)          MODO_LOCAL=1; shift ;;
    --simular)        SIMULAR=1; shift ;;
    --sim)            ASSUMIR_SIM=1; shift ;;
    -h|--ajuda)       ajuda; exit 0 ;;
    *) erro "Opcao desconhecida: $1"; ajuda; exit 1 ;;
  esac
done
export SIMULAR ASSUMIR_SIM

precisa_root
if ! command -v ocs-sr >/dev/null 2>&1; then
  [ "$SIMULAR" = "1" ] || abortar "ocs-sr nao encontrado: rode este script dentro do Clonezilla Live."
  aviso "ocs-sr ausente (fora do Clonezilla Live); seguindo apenas em modo simulacao."
fi

# ---------------------------------------------------------- repositorio
montar_pendrive() {
  local dev
  dev="$(dispositivo_por_rotulo "$ROTULO_DADOS")"
  [ -n "$dev" ] || abortar "Particao com rotulo '$ROTULO_DADOS' nao encontrada. Use --repositorio."
  info "Montando $dev em $REPOSITORIO"
  executar mkdir -p "$REPOSITORIO"
  executar mount "$dev" "$REPOSITORIO" || abortar "Falha ao montar $dev."
  ORIGEM_REPO="pendrive ($dev)"
}

soltar_repositorio() {
  [ "$REPO_REMOTO" = "1" ] || return 0
  rede_desmontar "$REPOSITORIO"
}

preparar_repositorio() {
  if mountpoint -q "$REPOSITORIO" 2>/dev/null; then
    info "Repositorio ja montado em $REPOSITORIO"
    ORIGEM_REPO="$(findmnt -no SOURCE "$REPOSITORIO" 2>/dev/null || echo "$REPOSITORIO")"
    return 0
  fi

  if [ "$MODO_LOCAL" = "1" ]; then
    montar_pendrive
    return 0
  fi

  rede_carregar_config "$ARQUIVO_CONFIG" || true
  rede_aplicar_cli
  if ! rede_configurada; then
    montar_pendrive
    return 0
  fi

  info "Cerebro na rede: $(rede_alvo)"
  rede_subir
  rede_testar_servidor || abortar "Servidor $REDE_SERVIDOR inacessivel. Confira a rede ou use --local."
  rede_montar_repositorio "$REPOSITORIO" rw
  rede_conferir_repositorio "$REPOSITORIO" rw \
    || abortar "Repositorio do servidor nao esta gravavel."
  REPO_REMOTO=1
  ORIGEM_REPO="servidor $(rede_alvo)"
  trap soltar_repositorio EXIT
}
ORIGEM_REPO=""
preparar_repositorio

DIR_IMAGENS="$REPOSITORIO/imagens"
executar mkdir -p "$DIR_IMAGENS" "$REPOSITORIO/logs"

# --------------------------------------------------------------- origem
listar_discos() {
  lsblk -dpno NAME,SIZE,MODEL,TRAN | grep -vE 'loop|/dev/sr' || true
}

if [ -z "$DISCO" ]; then
  echo; info "Discos detectados:"; listar_discos; echo
  printf 'Disco de origem (ex.: /dev/nvme0n1): '
  IFS= read -r DISCO || true
fi
[ -b "$DISCO" ] || abortar "Disco invalido: $DISCO"

CURTO="$(nome_curto "$DISCO")"
[ -d "/sys/block/$CURTO" ] || abortar "$DISCO nao e um disco inteiro."

# Evita capturar o proprio pendrive.
DEV_REPO="$(findmnt -no SOURCE "$REPOSITORIO" 2>/dev/null || true)"
if [ -n "$DEV_REPO" ] && [[ "$DEV_REPO" == "$DISCO"* ]]; then
  abortar "$DISCO e o proprio pendrive de trabalho. Escolha o disco interno."
fi

# ----------------------------------------------------------------- nome
if [ -z "$NOME" ]; then
  modelo=""
  if command -v dmidecode >/dev/null 2>&1; then
    modelo="$(dmidecode -s system-product-name 2>/dev/null | head -1 || true)"
  fi
  modelo="$(printf '%s' "$modelo" | tr '[:upper:] ' '[:lower:]-' | tr -cd 'a-z0-9._-')"
  [ -n "$modelo" ] || modelo="maquina"
  NOME="${modelo}-$(date +%Y%m%d-%H%M)"
fi
# ocs-sr nao aceita espacos nem caracteres especiais no nome da imagem.
NOME="$(printf '%s' "$NOME" | tr ' ' '-' | tr -cd 'a-zA-Z0-9._-')"
[ -n "$NOME" ] || abortar "Nome de imagem invalido."
[ -e "$DIR_IMAGENS/$NOME" ] && abortar "Ja existe uma imagem chamada '$NOME'."

# --------------------------------------------------------- espaco livre
if [ "$SIMULAR" != "1" ]; then
  tam_origem="$(blockdev --getsize64 "$DISCO" 2>/dev/null || echo 0)"
  livre="$(df -B1 --output=avail "$DIR_IMAGENS" | tail -1 | tr -d ' ')"
  if [ "$tam_origem" -gt 0 ] && [ "$livre" -lt $(( tam_origem / 3 )) ]; then
    aviso "Espaco livre ($(numfmt --to=iec "$livre")) pode ser insuficiente para clonar $(numfmt --to=iec "$tam_origem")."
  fi
fi

echo
info "Origem .....: $DISCO ($(tamanho_disco "$DISCO"))"
info "Repositorio : $ORIGEM_REPO"
info "Imagem .....: $DIR_IMAGENS/$NOME"
info "Compressao .: $COMPRESSAO"
[ -n "$PARTICOES" ] && info "Particoes ..: $PARTICOES"
echo
aviso "A leitura e somente-leitura no disco de origem, mas confirme o alvo."
confirmar_digitando "SALVAR"

# ---------------------------------------------------------------- salvar
LOG="$REPOSITORIO/logs/clonar-$NOME.log"
COMUNS=(-q2 -j2 -sfsck -senc -p "$DEPOIS" "$COMPRESSAO" -i 4096)
[ "$VERIFICAR_IMAGEM" = "1" ] || COMUNS+=(-scs)

if [ -n "$PARTICOES" ]; then
  # shellcheck disable=SC2086
  set -- saveparts "$NOME" $PARTICOES
else
  set -- savedisk "$NOME" "$CURTO"
fi

info "Executando: ocs-sr ${COMUNS[*]} $*"
if [ "$SIMULAR" = "1" ]; then
  ok "Modo simulacao: nada foi executado."
  exit 0
fi
ocs-sr -ocsroot "$REPOSITORIO/imagens" "${COMUNS[@]}" "$@" 2>&1 | tee "$LOG"
sync
ok "Imagem gravada em $DIR_IMAGENS/$NOME (log: $LOG)"
[ "$REPO_REMOTO" = "1" ] && ok "A imagem ja esta no servidor: nao ha nada a copiar depois."
