#!/usr/bin/env bash
#
# verificar-rede.sh - Confere, antes de clonar ou restaurar, se a maquina
# alcanca o repositorio de imagens (o "cerebro") no servidor do escritorio.
#
set -euo pipefail

DIR_SCRIPT="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=lib/comum.sh
source "$DIR_SCRIPT/lib/comum.sh"
# shellcheck source=lib/rede.sh
source "$DIR_SCRIPT/lib/rede.sh"

ARQUIVO_CONFIG=""
PONTO="/mnt/cerebro"
MONTAR=1
FALHAS=0

CLI_SERVIDOR=""; CLI_PROTOCOLO=""; CLI_CAMINHO=""; CLI_USUARIO=""
CLI_PORTA=""; CLI_CREDENCIAIS=""; CLI_DOMINIO=""; CLI_OPCOES=""; CLI_INTERFACE=""

ajuda() {
  cat <<'AJUDA'
Uso: sudo ./verificar-rede.sh [opcoes]

Testa a rede do escritorio e o repositorio de imagens no servidor:
interface, endereco IP, resposta do servidor, montagem e permissao de escrita.

Opcoes:
  -s, --servidor HOST     Servidor das imagens (IP ou nome).
      --protocolo P       ssh (padrao), nfs ou smb.
      --caminho CAMINHO   Caminho exportado (ssh/nfs) ou compartilhamento (smb).
  -u, --usuario NOME      Usuario no servidor.
      --porta N           Porta, quando nao for a padrao (22/2049/445).
      --credenciais ARQ   Chave SSH ou arquivo de credenciais do smb.
      --dominio NOME      Dominio Windows (smb).
      --opcoes-montagem O Opcoes extras de montagem, separadas por virgula.
      --interface IFACE   Interface de rede a usar.
      --config ARQUIVO    rede.conf a usar.
      --ponto DIR         Onde montar para o teste (padrao: /mnt/cerebro).
      --sem-montar        So testa a conexao, sem montar o repositorio.
  -h, --ajuda             Esta mensagem.
AJUDA
}

# shellcheck disable=SC2034  # as CLI_* sao lidas por rede_aplicar_cli (lib/rede.sh).
while [ $# -gt 0 ]; do
  case "$1" in
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
    --ponto)          PONTO="${2:-}"; shift 2 ;;
    --sem-montar)     MONTAR=0; shift ;;
    -h|--ajuda)       ajuda; exit 0 ;;
    *) erro "Opcao desconhecida: $1"; ajuda; exit 1 ;;
  esac
done

precisa_root

falhar() { erro "$*"; FALHAS=$((FALHAS + 1)); }

rede_carregar_config "$ARQUIVO_CONFIG" || aviso "Nenhum rede.conf encontrado; usando so as opcoes da linha de comando."
rede_aplicar_cli
rede_configurada || abortar "Nenhum servidor configurado. Informe --servidor ou crie um rede.conf."

echo
info "Servidor ...: $REDE_SERVIDOR"
info "Protocolo ..: $REDE_PROTOCOLO"
info "Repositorio : $(rede_alvo)"
[ -n "$REDE_CONFIG_USADA" ] && info "Config .....: $REDE_CONFIG_USADA"
echo

# 1. Interface e endereco
if iface="$(rede_interface)"; then
  ok "Interface com cabo conectado: $iface"
else
  falhar "Nenhuma interface com cabo conectado."
fi

if rede_tem_ip; then
  ok "Endereco IP: $(rede_resumo)"
else
  aviso "Sem endereco IP; tentando configurar a rede."
  rede_subir || falhar "Nao consegui colocar a maquina na rede."
fi

# 2. Rota e DNS
if command -v ip >/dev/null 2>&1; then
  if ip route show default 2>/dev/null | grep -q .; then
    ok "Rota padrao: $(ip route show default | head -1)"
  else
    aviso "Sem rota padrao (so funciona se o servidor estiver na mesma rede)."
  fi
fi

case "$REDE_SERVIDOR" in
  *[a-zA-Z]*)
    if getent hosts "$REDE_SERVIDOR" >/dev/null 2>&1; then
      ok "Nome $REDE_SERVIDOR resolve para $(getent hosts "$REDE_SERVIDOR" | awk '{print $1}' | head -1)"
    else
      falhar "Nome $REDE_SERVIDOR nao resolve. Use o IP do servidor no rede.conf."
    fi
    ;;
esac

# 3. Servidor respondendo na porta do protocolo
if rede_testar_servidor; then
  ok "Servidor alcancavel."
else
  falhar "Servidor $REDE_SERVIDOR nao responde na porta ${REDE_PORTA:-$(rede_porta_padrao)}."
fi

# 4. Montagem de verdade
if [ "$MONTAR" = "1" ] && [ "$FALHAS" -eq 0 ]; then
  limpar() { rede_desmontar "$PONTO"; rmdir "$PONTO" 2>/dev/null || true; }
  trap limpar EXIT
  if rede_montar_repositorio "$PONTO" rw; then
    ok "Montagem funcionou em $PONTO"
    if [ -d "$PONTO/imagens" ]; then
      n="$(find "$PONTO/imagens" -maxdepth 1 -mindepth 1 -type d 2>/dev/null | wc -l)"
      ok "Imagens no servidor: $n"
      find "$PONTO/imagens" -maxdepth 1 -mindepth 1 -type d -printf '  %f\n' 2>/dev/null | sort | head -20
    else
      aviso "Pasta imagens/ ainda nao existe no servidor (sera criada na primeira captura)."
    fi
    if rede_conferir_repositorio "$PONTO" rw; then
      ok "Permissao de escrita confirmada."
    else
      falhar "Sem permissao de escrita no repositorio do servidor."
    fi
    livre="$(df -h --output=avail "$PONTO" 2>/dev/null | tail -1 | tr -d ' ' || true)"
    [ -n "$livre" ] && info "Espaco livre no servidor: $livre"
  else
    falhar "Nao consegui montar o repositorio do servidor."
  fi
elif [ "$MONTAR" = "1" ]; then
  aviso "Montagem nao testada porque a conexao ja falhou."
fi

echo
if [ "$FALHAS" -eq 0 ]; then
  ok "Rede do escritorio pronta para clonar e restaurar."
else
  erro "$FALHAS verificacao(oes) falharam."
  exit 1
fi
