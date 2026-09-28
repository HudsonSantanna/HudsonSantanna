#!/usr/bin/env bash
#
# sincronizar-imagens.sh - Copia imagens entre o pendrive e o repositorio no
# servidor do escritorio (o "cerebro"), nos dois sentidos.
#
# Serve para: subir uma imagem capturada em campo (sem rede) para o servidor,
# ou levar no pendrive uma imagem do servidor para uma maquina fora da rede.
#
set -euo pipefail

DIR_SCRIPT="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=lib/comum.sh
source "$DIR_SCRIPT/lib/comum.sh"
# shellcheck source=lib/rede.sh
source "$DIR_SCRIPT/lib/rede.sh"

ACAO=""
IMAGEM=""
LOCAL="/home/partimag"
ROTULO_DADOS="IMAGENS"
PONTO="/mnt/cerebro"
ARQUIVO_CONFIG=""
APAGAR_DEPOIS=0
ASSUMIR_SIM=0

CLI_SERVIDOR=""; CLI_PROTOCOLO=""; CLI_CAMINHO=""; CLI_USUARIO=""
CLI_PORTA=""; CLI_CREDENCIAIS=""; CLI_DOMINIO=""; CLI_OPCOES=""; CLI_INTERFACE=""

ajuda() {
  cat <<'AJUDA'
Uso: sudo ./sincronizar-imagens.sh --enviar NOME | --baixar NOME | --listar

Move imagens entre o pendrive e o servidor da rede do escritorio.

Acoes:
      --enviar NOME       Copia a imagem do pendrive para o servidor.
      --baixar NOME       Copia a imagem do servidor para o pendrive.
      --listar            Mostra o que existe dos dois lados.

Opcoes:
  -l, --local DIR         Repositorio local (padrao: /home/partimag).
      --rotulo NOME       Rotulo da particao de imagens (padrao: IMAGENS).
      --ponto DIR         Onde montar o servidor (padrao: /mnt/cerebro).
      --apagar-origem     Apaga a imagem na origem apos a copia ser conferida.
      --config ARQUIVO    rede.conf a usar.
      --simular           Mostra o que seria copiado, sem copiar.
      --sim               Nao pergunta confirmacao.
  -h, --ajuda             Esta mensagem.

Opcoes de rede (--servidor, --protocolo, --caminho, --usuario, --porta,
--credenciais, --dominio, --opcoes-montagem, --interface) funcionam como nos
demais scripts e vencem o que estiver no rede.conf.
AJUDA
}

# shellcheck disable=SC2034  # as CLI_* sao lidas por rede_aplicar_cli (lib/rede.sh).
while [ $# -gt 0 ]; do
  case "$1" in
    --enviar)         ACAO="enviar"; IMAGEM="${2:-}"; shift 2 ;;
    --baixar)         ACAO="baixar"; IMAGEM="${2:-}"; shift 2 ;;
    --listar)         ACAO="listar"; shift ;;
    -l|--local)       LOCAL="${2:-}"; shift 2 ;;
    --rotulo)         ROTULO_DADOS="${2:-}"; shift 2 ;;
    --ponto)          PONTO="${2:-}"; shift 2 ;;
    --apagar-origem)  APAGAR_DEPOIS=1; shift ;;
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
    --simular)        SIMULAR=1; shift ;;
    --sim)            ASSUMIR_SIM=1; shift ;;
    -h|--ajuda)       ajuda; exit 0 ;;
    *) erro "Opcao desconhecida: $1"; ajuda; exit 1 ;;
  esac
done
export SIMULAR ASSUMIR_SIM

[ -n "$ACAO" ] || { erro "Escolha --enviar, --baixar ou --listar."; ajuda; exit 1; }
precisa_root
checar_dependencias rsync

# ------------------------------------------------------- repositorio local
if ! mountpoint -q "$LOCAL" 2>/dev/null; then
  dev="$(dispositivo_por_rotulo "$ROTULO_DADOS")"
  if [ -n "$dev" ]; then
    info "Montando $dev em $LOCAL"
    executar mkdir -p "$LOCAL"
    executar mount "$dev" "$LOCAL" || abortar "Falha ao montar $dev."
  else
    [ -d "$LOCAL" ] || abortar "Repositorio local nao encontrado: $LOCAL"
    aviso "Usando $LOCAL como repositorio local (nao e um ponto de montagem)."
  fi
fi
executar mkdir -p "$LOCAL/imagens"

# ---------------------------------------------------- repositorio remoto
rede_carregar_config "$ARQUIVO_CONFIG" || true
rede_aplicar_cli
rede_configurada || abortar "Nenhum servidor configurado. Informe --servidor ou crie um rede.conf."

limpar() { rede_desmontar "$PONTO"; }
trap limpar EXIT

rede_subir
rede_testar_servidor || abortar "Servidor $REDE_SERVIDOR inacessivel."
rede_montar_repositorio "$PONTO" rw
rede_conferir_repositorio "$PONTO" rw || abortar "Repositorio do servidor nao esta gravavel."
executar mkdir -p "$PONTO/imagens"

listar_lado() {
  local titulo="$1" dir="$2" d
  info "$titulo"
  for d in "$dir"/*/; do
    [ -d "$d" ] || continue
    printf '  %-40s %8s\n' "$(basename "$d")" "$(du -sh "$d" 2>/dev/null | cut -f1)"
  done
}

if [ "$ACAO" = "listar" ]; then
  echo
  listar_lado "Pendrive ($LOCAL/imagens):" "$LOCAL/imagens"
  echo
  listar_lado "Servidor ($(rede_alvo)):" "$PONTO/imagens"
  exit 0
fi

[ -n "$IMAGEM" ] || abortar "Informe o nome da imagem."
IMAGEM="$(basename "$IMAGEM")"

case "$ACAO" in
  enviar) ORIGEM="$LOCAL/imagens/$IMAGEM";  DESTINO="$PONTO/imagens" ;;
  baixar) ORIGEM="$PONTO/imagens/$IMAGEM"; DESTINO="$LOCAL/imagens" ;;
esac
[ -d "$ORIGEM" ] || abortar "Imagem nao encontrada: $ORIGEM"

if [ -d "$DESTINO/$IMAGEM" ]; then
  aviso "Ja existe '$IMAGEM' no destino; os arquivos serao atualizados."
fi

echo
info "Imagem ...: $IMAGEM ($(du -sh "$ORIGEM" 2>/dev/null | cut -f1))"
info "De .......: $ORIGEM"
info "Para .....: $DESTINO/$IMAGEM"
[ "$APAGAR_DEPOIS" = "1" ] && aviso "A origem sera apagada depois da conferencia."
echo
confirmar_digitando "COPIAR"

OPCOES_RSYNC=(-a --partial --human-readable)
if rsync --help 2>/dev/null | grep -q -- '--info='; then
  OPCOES_RSYNC+=(--info=progress2)
else
  OPCOES_RSYNC+=(--progress)
fi
[ "$SIMULAR" = "1" ] && OPCOES_RSYNC+=(--dry-run)

rsync "${OPCOES_RSYNC[@]}" "$ORIGEM/" "$DESTINO/$IMAGEM/" \
  || abortar "Falha ao copiar a imagem."
sync

# Conferencia: rsync em modo verificacao nao pode apontar diferenca nenhuma.
info "Conferindo a copia..."
if rsync -rc --dry-run --itemize-changes "$ORIGEM/" "$DESTINO/$IMAGEM/" 2>/dev/null | grep -q '^[<>ch]'; then
  [ "$SIMULAR" = "1" ] || abortar "A copia nao confere com a origem. Nada foi apagado."
fi
ok "Copia conferida."

if [ "$APAGAR_DEPOIS" = "1" ]; then
  info "Apagando a origem: $ORIGEM"
  executar rm -rf "$ORIGEM"
fi
ok "Imagem '$IMAGEM' sincronizada."
