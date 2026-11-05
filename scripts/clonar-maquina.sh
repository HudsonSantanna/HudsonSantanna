#!/usr/bin/env bash
#
# clonar-maquina.sh - Captura a imagem de um disco para o repositorio do
# pendrive. Deve ser executado dentro do Clonezilla Live (opcao Enter_shell).
#
set -euo pipefail

DIR_SCRIPT="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=lib/comum.sh
source "$DIR_SCRIPT/lib/comum.sh"

DISCO=""
NOME=""
ROTULO_DADOS="IMAGENS"
REPOSITORIO="/home/partimag"
COMPRESSAO="-z1p"          # zstd paralelo: bom equilibrio tamanho x tempo
DEPOIS="choose"            # choose | reboot | poweroff | true
PARTICOES=""
VERIFICAR_IMAGEM=1
ASSUMIR_SIM=0

ajuda() {
  cat <<'AJUDA'
Uso: sudo ./clonar-maquina.sh [opcoes]

Captura a imagem de um disco inteiro (ou de particoes especificas) e grava
no repositorio de imagens do pendrive.

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
AJUDA
}

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
preparar_repositorio() {
  if mountpoint -q "$REPOSITORIO" 2>/dev/null; then
    info "Repositorio ja montado em $REPOSITORIO"
    return 0
  fi
  local dev
  dev="$(dispositivo_por_rotulo "$ROTULO_DADOS")"
  [ -n "$dev" ] || abortar "Particao com rotulo '$ROTULO_DADOS' nao encontrada. Use --repositorio."
  info "Montando $dev em $REPOSITORIO"
  executar mkdir -p "$REPOSITORIO"
  executar mount "$dev" "$REPOSITORIO" || abortar "Falha ao montar $dev."
}
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
ok "Imagem gravada em $DIR_IMAGENS/$NOME (log: $LOG)"
