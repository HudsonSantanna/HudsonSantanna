#!/usr/bin/env bash
#
# restaurar-maquina.sh - Restaura uma imagem do pendrive para o disco da
# maquina. Deve ser executado dentro do Clonezilla Live (Enter_shell).
#
# ATENCAO: apaga completamente o disco de destino.
#
set -euo pipefail

DIR_SCRIPT="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=lib/comum.sh
source "$DIR_SCRIPT/lib/comum.sh"

IMAGEM=""
DISCO=""
ROTULO_DADOS="IMAGENS"
REPOSITORIO="/home/partimag"
DEPOIS="choose"
PROPORCIONAL=0
ASSUMIR_SIM=0

ajuda() {
  cat <<'AJUDA'
Uso: sudo ./restaurar-maquina.sh [opcoes]

Restaura uma imagem gravada no pendrive para o disco informado.
O DISCO DE DESTINO E APAGADO POR COMPLETO.

Opcoes:
  -i, --imagem NOME       Nome da imagem (pasta dentro de imagens/).
  -d, --disco DEV         Disco de destino (ex.: /dev/sda).
  -r, --repositorio DIR   Onde estao as imagens (padrao: /home/partimag).
      --rotulo NOME       Rotulo da particao de imagens (padrao: IMAGENS).
      --proporcional      Redimensiona as particoes ao tamanho do destino (-k1).
      --depois ACAO       choose (padrao), reboot, poweroff, true.
      --listar            Apenas lista as imagens disponiveis.
      --simular           Mostra o comando do ocs-sr sem executar.
      --sim               Nao pergunta confirmacao. PERIGOSO.
  -h, --ajuda             Esta mensagem.
AJUDA
}

APENAS_LISTAR=0
while [ $# -gt 0 ]; do
  case "$1" in
    -i|--imagem)      IMAGEM="${2:-}"; shift 2 ;;
    -d|--disco)       DISCO="${2:-}"; shift 2 ;;
    -r|--repositorio) REPOSITORIO="${2:-}"; shift 2 ;;
    --rotulo)         ROTULO_DADOS="${2:-}"; shift 2 ;;
    --proporcional)   PROPORCIONAL=1; shift ;;
    --depois)         DEPOIS="${2:-}"; shift 2 ;;
    --listar)         APENAS_LISTAR=1; shift ;;
    --simular)        SIMULAR=1; shift ;;
    --sim)            ASSUMIR_SIM=1; shift ;;
    -h|--ajuda)       ajuda; exit 0 ;;
    *) erro "Opcao desconhecida: $1"; ajuda; exit 1 ;;
  esac
done
export SIMULAR ASSUMIR_SIM

precisa_root
[ "$APENAS_LISTAR" = "1" ] || if ! command -v ocs-sr >/dev/null 2>&1; then
  [ "$SIMULAR" = "1" ] || abortar "ocs-sr nao encontrado: rode este script dentro do Clonezilla Live."
  aviso "ocs-sr ausente (fora do Clonezilla Live); seguindo apenas em modo simulacao."
fi

preparar_repositorio() {
  mountpoint -q "$REPOSITORIO" 2>/dev/null && return 0
  local dev
  dev="$(dispositivo_por_rotulo "$ROTULO_DADOS")"
  [ -n "$dev" ] || abortar "Particao com rotulo '$ROTULO_DADOS' nao encontrada. Use --repositorio."
  info "Montando $dev em $REPOSITORIO"
  executar mkdir -p "$REPOSITORIO"
  executar mount "$dev" "$REPOSITORIO" || abortar "Falha ao montar $dev."
}
preparar_repositorio

DIR_IMAGENS="$REPOSITORIO/imagens"
[ -d "$DIR_IMAGENS" ] || abortar "Pasta de imagens nao encontrada: $DIR_IMAGENS"

listar_imagens() {
  local d
  for d in "$DIR_IMAGENS"/*/; do
    [ -d "$d" ] || continue
    printf '  %-40s %8s  %s\n' "$(basename "$d")" \
      "$(du -sh "$d" 2>/dev/null | cut -f1)" \
      "$(date -r "$d" '+%d/%m/%Y %H:%M' 2>/dev/null || echo '-')"
  done
}

if [ "$APENAS_LISTAR" = "1" ]; then
  info "Imagens em $DIR_IMAGENS:"; listar_imagens; exit 0
fi

if [ -z "$IMAGEM" ]; then
  echo; info "Imagens disponiveis:"; listar_imagens; echo
  printf 'Nome da imagem: '
  IFS= read -r IMAGEM || true
fi
[ -d "$DIR_IMAGENS/$IMAGEM" ] || abortar "Imagem nao encontrada: $DIR_IMAGENS/$IMAGEM"

if [ -z "$DISCO" ]; then
  echo; info "Discos detectados:"
  lsblk -dpno NAME,SIZE,MODEL,TRAN | grep -vE 'loop|/dev/sr' || true
  echo
  printf 'Disco de DESTINO (sera apagado): '
  IFS= read -r DISCO || true
fi
[ -b "$DISCO" ] || abortar "Disco invalido: $DISCO"
CURTO="$(nome_curto "$DISCO")"
[ -d "/sys/block/$CURTO" ] || abortar "$DISCO nao e um disco inteiro."

# Nunca restaurar sobre o proprio pendrive.
DEV_REPO="$(findmnt -no SOURCE "$REPOSITORIO" 2>/dev/null || true)"
if [ -n "$DEV_REPO" ] && [[ "$DEV_REPO" == "$DISCO"* ]]; then
  abortar "$DISCO e o pendrive que contem as imagens. Recusando."
fi

# Aviso de tamanho: destino menor que a origem so funciona com --proporcional.
if [ "$SIMULAR" != "1" ]; then
  # O tamanho do disco original fica registrado no arquivo *-pt.parted da imagem.
  origem_bytes="$(grep -hoE '^/dev/[a-z0-9]+:[0-9]+B' "$DIR_IMAGENS/$IMAGEM"/*-pt.parted 2>/dev/null \
    | head -1 | grep -oE '[0-9]+' | tail -1 || true)"
  origem_bytes="${origem_bytes:-0}"
  destino_bytes="$(blockdev --getsize64 "$DISCO" 2>/dev/null || echo 0)"
  if [ "$origem_bytes" -gt 0 ] && [ "$destino_bytes" -gt 0 ] && \
     [ "$destino_bytes" -lt "$origem_bytes" ] && [ "$PROPORCIONAL" = "0" ]; then
    aviso "Destino menor que a imagem original; considere --proporcional (-k1)."
  fi
fi

echo
info "Imagem ....: $DIR_IMAGENS/$IMAGEM"
info "Destino ...: $DISCO ($(tamanho_disco "$DISCO"))"
lsblk -o NAME,SIZE,FSTYPE,LABEL "$DISCO" || true
echo
aviso "TODO o conteudo de $DISCO sera APAGADO."
confirmar_digitando "RESTAURAR"

LOG="$REPOSITORIO/logs/restaurar-$IMAGEM-$CURTO-$(date +%Y%m%d-%H%M%S).log"
OPCOES=(-g auto -e1 auto -e2 -r -j2 -p "$DEPOIS")
[ "$PROPORCIONAL" = "1" ] && OPCOES+=(-k1)

info "Executando: ocs-sr ${OPCOES[*]} restoredisk $IMAGEM $CURTO"
if [ "$SIMULAR" = "1" ]; then
  ok "Modo simulacao: nada foi executado."
  exit 0
fi
executar mkdir -p "$REPOSITORIO/logs"
ocs-sr -ocsroot "$DIR_IMAGENS" "${OPCOES[@]}" restoredisk "$IMAGEM" "$CURTO" 2>&1 | tee "$LOG"
ok "Restauracao concluida (log: $LOG)"
