#!/usr/bin/env bash
#
# montar-servidor.sh - Monta a pasta compartilhada de um servidor Windows
# (SMB/CIFS) como repositorio de imagens, para que clonar-maquina.sh e
# restaurar-maquina.sh gravem e leiam direto pela rede.
#
# Roda dentro do Clonezilla Live (Enter_shell) ou em qualquer Linux com
# cifs-utils instalado.
#
set -euo pipefail

DIR_SCRIPT="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=lib/comum.sh
source "$DIR_SCRIPT/lib/comum.sh"

SERVIDOR=""
COMPARTILHAMENTO=""
USUARIO=""
DOMINIO=""
PONTO="/home/partimag"
VERSAO="3.0"
SOMENTE_LEITURA=0
DESMONTAR=0

ajuda() {
  cat <<'AJUDA'
Uso: sudo ./montar-servidor.sh -s SERVIDOR -c COMPARTILHAMENTO -u USUARIO

Monta uma pasta compartilhada do Windows em /home/partimag. Depois disso,
clonar-maquina.sh e restaurar-maquina.sh funcionam sem nenhuma alteracao:
os dois detectam que o ponto ja esta montado e usam a rede no lugar do
pendrive.

A senha e perguntada na hora e vai para um arquivo temporario com permissao
600, nunca para a linha de comando (onde qualquer um veria com ps).

Opcoes:
  -s, --servidor HOST      Nome ou IP do servidor (ex.: 192.168.0.10).
  -c, --compartilhamento N Nome do compartilhamento (ex.: imagens).
  -u, --usuario NOME       Conta local do servidor com acesso a pasta.
  -d, --dominio NOME       Dominio, se houver. Padrao: nenhum.
  -p, --ponto DIR          Onde montar (padrao: /home/partimag).
      --versao N           Versao do SMB: 3.0 (padrao), 3.1.1, 2.1.
      --somente-leitura    Monta sem permissao de escrita (so restaurar).
      --desmontar          Desmonta o ponto e sai.
      --simular            Mostra o que faria sem montar nada.
  -h, --ajuda              Esta mensagem.

Exemplos:
  sudo ./montar-servidor.sh -s 192.168.0.10 -c imagens -u clonagem
  sudo ./montar-servidor.sh --desmontar
AJUDA
}

while [ $# -gt 0 ]; do
  case "$1" in
    -s|--servidor)         SERVIDOR="${2:-}"; shift 2 ;;
    -c|--compartilhamento) COMPARTILHAMENTO="${2:-}"; shift 2 ;;
    -u|--usuario)          USUARIO="${2:-}"; shift 2 ;;
    -d|--dominio)          DOMINIO="${2:-}"; shift 2 ;;
    -p|--ponto)            PONTO="${2:-}"; shift 2 ;;
    --versao)              VERSAO="${2:-}"; shift 2 ;;
    --somente-leitura)     SOMENTE_LEITURA=1; shift ;;
    --desmontar)           DESMONTAR=1; shift ;;
    --simular)             SIMULAR=1; shift ;;
    -h|--ajuda)            ajuda; exit 0 ;;
    *) erro "Opcao desconhecida: $1"; ajuda; exit 1 ;;
  esac
done
export SIMULAR

precisa_root

# ------------------------------------------------------------- desmontar
if [ "$DESMONTAR" = "1" ]; then
  if ! mountpoint -q "$PONTO" 2>/dev/null; then
    info "Nada montado em $PONTO."
    exit 0
  fi
  executar sync
  executar umount "$PONTO" || abortar "Nao consegui desmontar $PONTO (algum programa ainda usa a pasta?)."
  ok "Desmontado: $PONTO"
  exit 0
fi

# ------------------------------------------------------------- validacao
[ -n "$SERVIDOR" ]         || abortar "Informe o servidor com -s (veja --ajuda)."
[ -n "$COMPARTILHAMENTO" ] || abortar "Informe o compartilhamento com -c (veja --ajuda)."
[ -n "$USUARIO" ]          || abortar "Informe o usuario com -u (veja --ajuda)."

checar_dependencias mountpoint findmnt
if ! command -v mount.cifs >/dev/null 2>&1; then
  [ "$SIMULAR" = "1" ] || abortar "mount.cifs nao encontrado: instale cifs-utils (Debian/Ubuntu: sudo apt install cifs-utils). Dentro do Clonezilla Live ele ja vem."
  aviso "mount.cifs ausente (fora do Clonezilla Live); seguindo apenas em modo simulacao."
fi

if mountpoint -q "$PONTO" 2>/dev/null; then
  ORIGEM_ATUAL="$(findmnt -no SOURCE "$PONTO" 2>/dev/null || echo '?')"
  abortar "$PONTO ja esta montado ($ORIGEM_ATUAL). Use --desmontar antes."
fi

ORIGEM="//$SERVIDOR/$COMPARTILHAMENTO"

# ------------------------------------------------------------- montagem
SENHA=""
if [ "$SIMULAR" = "1" ]; then
  info "Modo simulacao: a senha nao sera pedida."
else
  printf 'Senha de %s%s%s em %s%s%s: ' \
    "$C_AMAR" "$USUARIO" "$C_RESET" "$C_AMAR" "$SERVIDOR" "$C_RESET"
  IFS= read -rs SENHA || true
  printf '\n'
  [ -n "$SENHA" ] || aviso "Senha vazia; a montagem provavelmente vai falhar."
fi

ARQ_CRED=""
limpar_credenciais() { [ -n "$ARQ_CRED" ] && rm -f "$ARQ_CRED"; }
trap limpar_credenciais EXIT

OPCOES="vers=$VERSAO,iocharset=utf8,file_mode=0644,dir_mode=0755"
[ "$SOMENTE_LEITURA" = "1" ] && OPCOES="$OPCOES,ro"

info "Servidor .....: $ORIGEM"
info "Usuario ......: $USUARIO${DOMINIO:+ (dominio $DOMINIO)}"
info "Ponto ........: $PONTO"
info "Opcoes .......: $OPCOES"

if [ "$SIMULAR" = "1" ]; then
  printf '%s[simular]%s mount -t cifs %s %s -o credentials=<arquivo temporario>,%s\n' \
    "$C_AMAR" "$C_RESET" "$ORIGEM" "$PONTO" "$OPCOES"
  exit 0
fi

ARQ_CRED="$(mktemp)"
chmod 600 "$ARQ_CRED"
{
  printf 'username=%s\n' "$USUARIO"
  printf 'password=%s\n' "$SENHA"
  [ -n "$DOMINIO" ] && printf 'domain=%s\n' "$DOMINIO"
} > "$ARQ_CRED"

mkdir -p "$PONTO"
if ! mount -t cifs "$ORIGEM" "$PONTO" -o "credentials=$ARQ_CRED,$OPCOES"; then
  erro "Falha ao montar $ORIGEM."
  erro "Confira: o servidor esta ligado e responde a ping; a pasta esta"
  erro "compartilhada; a conta '$USUARIO' e uma conta local do servidor com"
  erro "permissao de escrita; o Windows nao esta so com SMB1 (tente --versao 2.1)."
  exit 1
fi
limpar_credenciais
ARQ_CRED=""

# ------------------------------------------------------------- conferencia
if [ "$SOMENTE_LEITURA" = "1" ]; then
  info "Montado somente para leitura; escrita nao sera testada."
else
  TESTE="$PONTO/.teste-escrita-$$"
  if ! (: > "$TESTE") 2>/dev/null; then
    umount "$PONTO" || true
    abortar "Montou, mas nao consigo escrever em $PONTO. Ajuste a permissao do compartilhamento no Windows."
  fi
  rm -f "$TESTE"
  mkdir -p "$PONTO/imagens" "$PONTO/logs"
fi

LIVRE="$(df -h --output=avail "$PONTO" 2>/dev/null | tail -1 | tr -d ' ' || echo '?')"
ok "Montado: $ORIGEM em $PONTO (livre: $LIVRE)"
info "Agora rode normalmente:"
info "  sudo $DIR_SCRIPT/clonar-maquina.sh"
info "  sudo $DIR_SCRIPT/restaurar-maquina.sh --listar"
info "Ao terminar: sudo $DIR_SCRIPT/montar-servidor.sh --desmontar"
