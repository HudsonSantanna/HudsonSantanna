#!/usr/bin/env bash
#
# restaurar-maquina.sh - Restaura uma imagem para o disco da maquina. As
# imagens vem do servidor da rede do escritorio (o "cerebro") ou do pendrive.
# Deve ser executado dentro do Clonezilla Live (Enter_shell).
#
# ATENCAO: apaga completamente o disco de destino.
#
set -euo pipefail

DIR_SCRIPT="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=lib/comum.sh
source "$DIR_SCRIPT/lib/comum.sh"
# shellcheck source=lib/rede.sh
source "$DIR_SCRIPT/lib/rede.sh"

IMAGEM=""
DISCO=""
ROTULO_DADOS="IMAGENS"
REPOSITORIO="/home/partimag"
DEPOIS="choose"
PROPORCIONAL=0
ASSUMIR_SIM=0
MODO_LOCAL=0
MODO_RO=0
ARQUIVO_CONFIG=""
REPO_REMOTO=0
DIR_LOGS=""

# Preenchidas pelas opcoes de rede; vencem o que estiver no rede.conf.
CLI_SERVIDOR=""; CLI_PROTOCOLO=""; CLI_CAMINHO=""; CLI_USUARIO=""
CLI_PORTA=""; CLI_CREDENCIAIS=""; CLI_DOMINIO=""; CLI_OPCOES=""; CLI_INTERFACE=""

ajuda() {
  cat <<'AJUDA'
Uso: sudo ./restaurar-maquina.sh [opcoes]

Restaura uma imagem do repositorio (servidor da rede ou pendrive) para o
disco informado. O DISCO DE DESTINO E APAGADO POR COMPLETO.

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
      --somente-leitura   Monta o repositorio como so leitura (log fica local).
      --local             Ignora a rede e le do pendrive.

Sem servidor configurado, o comportamento e o de sempre: pendrive.
AJUDA
}

APENAS_LISTAR=0
# shellcheck disable=SC2034  # as CLI_* sao lidas por rede_aplicar_cli (lib/rede.sh).
while [ $# -gt 0 ]; do
  case "$1" in
    -i|--imagem)      IMAGEM="${2:-}"; shift 2 ;;
    -d|--disco)       DISCO="${2:-}"; shift 2 ;;
    -r|--repositorio) REPOSITORIO="${2:-}"; shift 2 ;;
    --rotulo)         ROTULO_DADOS="${2:-}"; shift 2 ;;
    --proporcional)   PROPORCIONAL=1; shift ;;
    --depois)         DEPOIS="${2:-}"; shift 2 ;;
    --listar)         APENAS_LISTAR=1; shift ;;
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
    --somente-leitura) MODO_RO=1; shift ;;
    --local)          MODO_LOCAL=1; shift ;;
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

  local modo="rw"
  [ "$MODO_RO" = "1" ] && modo="ro"
  info "Cerebro na rede: $(rede_alvo)"
  rede_subir
  rede_testar_servidor || abortar "Servidor $REDE_SERVIDOR inacessivel. Confira a rede ou use --local."
  rede_montar_repositorio "$REPOSITORIO" "$modo"
  rede_conferir_repositorio "$REPOSITORIO" "$modo" \
    || abortar "Repositorio do servidor nao esta gravavel (use --somente-leitura)."
  REPO_REMOTO=1
  ORIGEM_REPO="servidor $(rede_alvo)"
  trap soltar_repositorio EXIT
}
ORIGEM_REPO=""
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
info "Repositorio: $ORIGEM_REPO"
info "Imagem ....: $DIR_IMAGENS/$IMAGEM"
info "Destino ...: $DISCO ($(tamanho_disco "$DISCO"))"
lsblk -o NAME,SIZE,FSTYPE,LABEL "$DISCO" || true
echo
aviso "TODO o conteudo de $DISCO sera APAGADO."
confirmar_digitando "RESTAURAR"

# Com o repositorio so para leitura o log nao pode ir para o servidor.
if [ "$MODO_RO" = "1" ]; then
  DIR_LOGS="/tmp/kit-clonagem/logs"
else
  DIR_LOGS="$REPOSITORIO/logs"
fi
LOG="$DIR_LOGS/restaurar-$IMAGEM-$CURTO-$(date +%Y%m%d-%H%M%S).log"
OPCOES=(-g auto -e1 auto -e2 -r -j2 -p "$DEPOIS")
[ "$PROPORCIONAL" = "1" ] && OPCOES+=(-k1)

info "Executando: ocs-sr ${OPCOES[*]} restoredisk $IMAGEM $CURTO"
if [ "$SIMULAR" = "1" ]; then
  ok "Modo simulacao: nada foi executado."
  exit 0
fi
executar mkdir -p "$DIR_LOGS"
ocs-sr -ocsroot "$DIR_IMAGENS" "${OPCOES[@]}" restoredisk "$IMAGEM" "$CURTO" 2>&1 | tee "$LOG"
ok "Restauracao concluida (log: $LOG)"
