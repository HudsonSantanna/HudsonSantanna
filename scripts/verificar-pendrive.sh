#!/usr/bin/env bash
#
# verificar-pendrive.sh - Confere se um pendrive preparado esta consistente
# (particoes, arquivos de boot BIOS/UEFI, repositorio de imagens).
#
set -euo pipefail

DIR_SCRIPT="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=lib/comum.sh
source "$DIR_SCRIPT/lib/comum.sh"

DISPOSITIVO=""
ROTULO_BOOT="CLONEZILLA"
ROTULO_DADOS="IMAGENS"
FALHAS=0

ajuda() {
  cat <<'AJUDA'
Uso: sudo ./verificar-pendrive.sh [--dispositivo /dev/sdX]

Sem --dispositivo, procura as particoes pelos rotulos CLONEZILLA e IMAGENS.

Opcoes:
  -d, --dispositivo DEV   Disco a verificar.
      --rotulo-boot NOME  Padrao: CLONEZILLA
      --rotulo-dados NOME Padrao: IMAGENS
  -h, --ajuda             Esta mensagem.
AJUDA
}

while [ $# -gt 0 ]; do
  case "$1" in
    -d|--dispositivo) DISPOSITIVO="${2:-}"; shift 2 ;;
    --rotulo-boot)    ROTULO_BOOT="${2:-}"; shift 2 ;;
    --rotulo-dados)   ROTULO_DADOS="${2:-}"; shift 2 ;;
    -h|--ajuda)       ajuda; exit 0 ;;
    /dev/*)           DISPOSITIVO="$1"; shift ;;
    *) erro "Opcao desconhecida: $1"; ajuda; exit 1 ;;
  esac
done

precisa_root
checar_dependencias lsblk blkid

# conferir "descricao" comando... -> registra sucesso/falha sem abortar o script.
conferir() {
  local descricao="$1"; shift
  if "$@" 2>/dev/null; then
    ok "$descricao"
  else
    erro "$descricao"
    FALHAS=$((FALHAS + 1))
  fi
}

if [ -n "$DISPOSITIVO" ]; then
  [ -b "$DISPOSITIVO" ] || abortar "$DISPOSITIVO nao e um dispositivo de bloco."
  PART_BOOT="$(nome_particao "$DISPOSITIVO" 1)"
  PART_DADOS="$(nome_particao "$DISPOSITIVO" 2)"
else
  PART_BOOT="$(dispositivo_por_rotulo "$ROTULO_BOOT")"
  PART_DADOS="$(dispositivo_por_rotulo "$ROTULO_DADOS")"
fi

if [ -z "${PART_BOOT:-}" ] || [ ! -b "$PART_BOOT" ]; then
  abortar "Particao de boot nao encontrada (rotulo $ROTULO_BOOT)."
fi
info "Particao de boot .: $PART_BOOT"
info "Particao de dados : ${PART_DADOS:-nao encontrada}"
echo

fs_boot="$(blkid -s TYPE -o value "$PART_BOOT" 2>/dev/null || true)"
[ -n "$fs_boot" ] || fs_boot="$(lsblk -no FSTYPE "$PART_BOOT" | tr -d ' ')"
conferir "Particao de boot em FAT32 (encontrado: ${fs_boot:-vazio})" test "$fs_boot" = "vfat"

TMP_MNT="$(mktemp -d)"
limpar() { mountpoint -q "$TMP_MNT" && umount "$TMP_MNT"; rmdir "$TMP_MNT" 2>/dev/null || true; }
trap limpar EXIT

mount -o ro "$PART_BOOT" "$TMP_MNT" || abortar "Nao consegui montar $PART_BOOT."
conferir "kernel live/vmlinuz presente"        test -f "$TMP_MNT/live/vmlinuz"
conferir "live/filesystem.squashfs presente"   test -f "$TMP_MNT/live/filesystem.squashfs"
conferir "boot UEFI (EFI/boot/bootx64.efi)"    test -f "$TMP_MNT/EFI/boot/bootx64.efi"
# shellcheck disable=SC2016  # $1 e expandido pelo bash -c, nao aqui.
conferir "boot BIOS/legado (ldlinux.sys)" \
  bash -c '[ -f "$1/syslinux/ldlinux.sys" ] || [ -f "$1/ldlinux.sys" ]' _ "$TMP_MNT"
umount "$TMP_MNT"

if [ -n "${PART_DADOS:-}" ] && [ -b "$PART_DADOS" ]; then
  mount -o ro "$PART_DADOS" "$TMP_MNT" 2>/dev/null || mount "$PART_DADOS" "$TMP_MNT"
  conferir "pasta imagens/"                      test -d "$TMP_MNT/imagens"
  conferir "scripts/clonar-maquina.sh presente"  test -f "$TMP_MNT/scripts/clonar-maquina.sh"
  conferir "scripts/restaurar-maquina.sh presente" test -f "$TMP_MNT/scripts/restaurar-maquina.sh"
  conferir "scripts/lib/rede.sh presente"        test -f "$TMP_MNT/scripts/lib/rede.sh"
  if [ -f "$TMP_MNT/rede.conf" ]; then
    servidor="$(grep -iE '^[[:space:]]*SERVIDOR[[:space:]]*=' "$TMP_MNT/rede.conf" | tail -1 | cut -d= -f2- | tr -d '[:space:]')"
    ok "rede.conf presente (servidor: ${servidor:-nao informado})"
  else
    info "Sem rede.conf: as imagens ficam no proprio pendrive."
  fi
  livre="$(df -h --output=avail "$TMP_MNT" | tail -1 | tr -d ' ')"
  info "Espaco livre para imagens: $livre"
  n_imagens="$(find "$TMP_MNT/imagens" -maxdepth 1 -mindepth 1 -type d 2>/dev/null | wc -l)"
  info "Imagens armazenadas: $n_imagens"
  umount "$TMP_MNT"
else
  aviso "Particao de dados nao encontrada; o pendrive so servira para boot."
fi

echo
if [ "$FALHAS" -eq 0 ]; then
  ok "Pendrive verificado sem problemas."
else
  erro "$FALHAS verificacao(oes) falharam."
  exit 1
fi
