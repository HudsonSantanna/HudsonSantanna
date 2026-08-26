#!/usr/bin/env bash
# comum.sh - funcoes compartilhadas pelos scripts do kit de clonagem.
# Uso: source "$(dirname "$0")/lib/comum.sh"

# Cores (desativadas quando a saida nao e um terminal).
if [ -t 1 ] && [ -z "${SEM_COR:-}" ]; then
  C_RESET=$'\033[0m'; C_VERM=$'\033[1;31m'; C_VERD=$'\033[1;32m'
  C_AMAR=$'\033[1;33m'; C_AZUL=$'\033[1;34m'
else
  C_RESET=''; C_VERM=''; C_VERD=''; C_AMAR=''; C_AZUL=''
fi

SIMULAR="${SIMULAR:-0}"

info()  { printf '%s[info]%s %s\n'  "$C_AZUL" "$C_RESET" "$*"; }
ok()    { printf '%s[ ok ]%s %s\n'  "$C_VERD" "$C_RESET" "$*"; }
aviso() { printf '%s[aviso]%s %s\n' "$C_AMAR" "$C_RESET" "$*" >&2; }
erro()  { printf '%s[erro]%s %s\n'  "$C_VERM" "$C_RESET" "$*" >&2; }

# Encerra com mensagem de erro.
abortar() { erro "$*"; exit 1; }

# Executa um comando respeitando o modo simulacao (--simular).
executar() {
  if [ "$SIMULAR" = "1" ]; then
    printf '%s[simular]%s %s\n' "$C_AMAR" "$C_RESET" "$*"
    return 0
  fi
  "$@"
}

precisa_root() {
  [ "$SIMULAR" = "1" ] && return 0
  [ "$(id -u)" -eq 0 ] || abortar "Execute como root (sudo $0 ...)."
}

# checar_dependencias cmd1 cmd2 ... -> aborta listando tudo que falta.
checar_dependencias() {
  local faltando=()
  local cmd
  for cmd in "$@"; do
    command -v "$cmd" >/dev/null 2>&1 || faltando+=("$cmd")
  done
  if [ "${#faltando[@]}" -gt 0 ]; then
    erro "Comandos ausentes: ${faltando[*]}"
    erro "Debian/Ubuntu: sudo apt install parted dosfstools gdisk syslinux-common unzip curl rsync exfatprogs ntfs-3g"
    erro "Fedora/RHEL:   sudo dnf install parted dosfstools gdisk syslinux unzip curl rsync exfatprogs ntfs-3g"
    exit 1
  fi
}

# Nome da particao N de um disco: /dev/sdb -> /dev/sdb1 ; /dev/nvme0n1 -> /dev/nvme0n1p1
nome_particao() {
  local disco="$1" numero="$2"
  if [[ "$disco" =~ [0-9]$ ]]; then
    printf '%sp%s\n' "$disco" "$numero"
  else
    printf '%s%s\n' "$disco" "$numero"
  fi
}

# Nome curto do dispositivo: /dev/sdb -> sdb
nome_curto() { basename "$1"; }

# Confirmacao forte: exige que o operador digite exatamente o texto esperado.
confirmar_digitando() {
  local esperado="$1" resposta=""
  if [ "${ASSUMIR_SIM:-0}" = "1" ]; then
    aviso "--sim informado: confirmacao automatica ('$esperado')."
    return 0
  fi
  printf 'Digite %s%s%s para confirmar (qualquer outra coisa cancela): ' \
    "$C_AMAR" "$esperado" "$C_RESET"
  IFS= read -r resposta || true
  [ "$resposta" = "$esperado" ] || abortar "Cancelado pelo operador."
}

# Desmonta todas as particoes montadas de um disco.
desmontar_disco() {
  local disco="$1" ponto
  while read -r ponto; do
    [ -n "$ponto" ] || continue
    info "Desmontando $ponto"
    executar umount "$ponto" || abortar "Nao consegui desmontar $ponto."
  done < <(lsblk -nrpo MOUNTPOINT "$disco" 2>/dev/null | grep -v '^$' || true)
  if command -v swapoff >/dev/null 2>&1; then
    while read -r parte tipo; do
      [ "$tipo" = "swap" ] || continue
      executar swapoff "$parte" || true
    done < <(lsblk -nrpo NAME,FSTYPE "$disco" 2>/dev/null || true)
  fi
}

# Aguarda o kernel reler a tabela de particoes.
reler_particoes() {
  local disco="$1"
  executar partprobe "$disco" || executar blockdev --rereadpt "$disco" || true
  if command -v udevadm >/dev/null 2>&1; then
    executar udevadm settle || true
  fi
  [ "$SIMULAR" = "1" ] || sleep 2
}

# Tamanho legivel de um disco (ex.: 57,3G).
tamanho_disco() { lsblk -ndo SIZE "$1" 2>/dev/null | tr -d ' '; }

# Caminho do dispositivo com um rotulo de sistema de arquivos, ou vazio.
dispositivo_por_rotulo() {
  local rotulo="$1"
  blkid -L "$rotulo" 2>/dev/null || true
}
