#!/usr/bin/env bash
#
# preparar-pendrive.sh - Grava um pendrive inicializavel com Clonezilla Live
# (BIOS + UEFI) e cria uma segunda particao para guardar as imagens.
#
# ATENCAO: o script APAGA todo o conteudo do dispositivo informado.
#
set -euo pipefail

DIR_SCRIPT="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
DIR_RAIZ="$(dirname "$DIR_SCRIPT")"
# shellcheck source=lib/comum.sh
source "$DIR_SCRIPT/lib/comum.sh"

# ---------------------------------------------------------------- parametros
DISPOSITIVO=""
ZIP_LOCAL=""
VERSAO=""
VERSAO_FALLBACK="3.2.0-5"
ARQUITETURA="amd64"
TAMANHO_BOOT="2GiB"
FS_DADOS="ext4"
ROTULO_BOOT="CLONEZILLA"
ROTULO_DADOS="IMAGENS"
ESQUEMA="mbr"
VERIFICAR=1
PERMITIR_NAO_REMOVIVEL=0
ASSUMIR_SIM=0
CFG_SERVIDOR=""
CFG_PROTOCOLO="ssh"
CFG_CAMINHO=""
CFG_USUARIO=""
MIRROR="https://free.nchc.org.tw/clonezilla-live/stable"

ajuda() {
  cat <<'AJUDA'
Uso: sudo ./preparar-pendrive.sh --dispositivo /dev/sdX [opcoes]

Cria no pendrive:
  particao 1  FAT32  rotulo CLONEZILLA  -> Clonezilla Live (BIOS + UEFI)
  particao 2  ext4   rotulo IMAGENS     -> repositorio das imagens + scripts

Opcoes:
  -d, --dispositivo DEV   Disco de destino (ex.: /dev/sdb). Obrigatorio.
  -z, --zip ARQUIVO       Usa um clonezilla-live-*.zip ja baixado.
  -v, --versao X.Y.Z-N    Versao do Clonezilla a baixar (padrao: ultima estavel).
  -a, --arquitetura ARCH  amd64 (padrao) ou i686.
  -b, --tamanho-boot TAM  Tamanho da particao de boot (padrao: 2GiB).
  -f, --fs-dados FS       ext4 (padrao), ntfs, exfat ou vfat.
  -e, --esquema ESQ       mbr (padrao, BIOS+UEFI) ou gpt (UEFI).
      --rotulo-dados NOME Rotulo da particao de imagens (padrao: IMAGENS).
      --servidor HOST     Grava rede.conf apontando para o servidor de imagens.
      --protocolo P       ssh (padrao), nfs ou smb, para o rede.conf.
      --caminho CAMINHO   Caminho/compartilhamento das imagens no servidor.
      --usuario NOME      Usuario no servidor, para o rede.conf.
      --sem-verificacao   Nao conferir o SHA256 do download.
      --permitir-nao-removivel  Aceita discos que nao sejam USB removivel.
      --simular           Mostra o que seria feito, sem escrever nada.
      --sim               Nao pergunta nada (uso em automacao). PERIGOSO.
  -h, --ajuda             Esta mensagem.

Exemplos:
  sudo ./preparar-pendrive.sh -d /dev/sdb
  sudo ./preparar-pendrive.sh -d /dev/sdb -z ~/Downloads/clonezilla-live-3.2.0-5-amd64.zip
  sudo ./preparar-pendrive.sh -d /dev/sdb -f ntfs -b 4GiB
  sudo ./preparar-pendrive.sh -d /dev/sdb --servidor 192.168.0.10 \
       --caminho /srv/clonagem --usuario clonagem
AJUDA
}

while [ $# -gt 0 ]; do
  case "$1" in
    -d|--dispositivo) DISPOSITIVO="${2:-}"; shift 2 ;;
    -z|--zip)         ZIP_LOCAL="${2:-}"; shift 2 ;;
    -v|--versao)      VERSAO="${2:-}"; shift 2 ;;
    -a|--arquitetura) ARQUITETURA="${2:-}"; shift 2 ;;
    -b|--tamanho-boot) TAMANHO_BOOT="${2:-}"; shift 2 ;;
    -f|--fs-dados)    FS_DADOS="${2:-}"; shift 2 ;;
    -e|--esquema)     ESQUEMA="${2:-}"; shift 2 ;;
    --rotulo-dados)   ROTULO_DADOS="${2:-}"; shift 2 ;;
    --servidor)       CFG_SERVIDOR="${2:-}"; shift 2 ;;
    --protocolo)      CFG_PROTOCOLO="${2:-}"; shift 2 ;;
    --caminho)        CFG_CAMINHO="${2:-}"; shift 2 ;;
    --usuario)        CFG_USUARIO="${2:-}"; shift 2 ;;
    --sem-verificacao) VERIFICAR=0; shift ;;
    --permitir-nao-removivel) PERMITIR_NAO_REMOVIVEL=1; shift ;;
    --simular)        SIMULAR=1; shift ;;
    --sim)            ASSUMIR_SIM=1; shift ;;
    -h|--ajuda)       ajuda; exit 0 ;;
    /dev/*)           DISPOSITIVO="$1"; shift ;;
    *)                erro "Opcao desconhecida: $1"; ajuda; exit 1 ;;
  esac
done
export SIMULAR ASSUMIR_SIM

[ -n "$DISPOSITIVO" ] || { erro "Informe o dispositivo com --dispositivo."; ajuda; exit 1; }

case "$FS_DADOS" in
  ext4|ntfs|exfat|vfat) ;;
  *) abortar "Sistema de arquivos invalido: $FS_DADOS (use ext4, ntfs, exfat ou vfat)." ;;
esac
case "$ESQUEMA" in
  mbr|gpt) ;;
  *) abortar "Esquema invalido: $ESQUEMA (use mbr ou gpt)." ;;
esac
case "$CFG_PROTOCOLO" in
  ssh|nfs|smb) ;;
  *) abortar "Protocolo invalido: $CFG_PROTOCOLO (use ssh, nfs ou smb)." ;;
esac
if [ -n "$CFG_SERVIDOR" ] && [ -z "$CFG_CAMINHO" ]; then
  abortar "Com --servidor informe tambem --caminho (onde ficam as imagens no servidor)."
fi

# ------------------------------------------------------------- dependencias
DEPS=(lsblk blkid wipefs parted mkfs.vfat unzip rsync partprobe)
case "$FS_DADOS" in
  ext4)  DEPS+=(mkfs.ext4) ;;
  ntfs)  DEPS+=(mkfs.ntfs) ;;
  exfat) DEPS+=(mkfs.exfat) ;;
esac
[ "$ESQUEMA" = "gpt" ] && DEPS+=(sgdisk)
[ -n "$ZIP_LOCAL" ] || DEPS+=(curl)
[ "$VERIFICAR" = "1" ] && DEPS+=(sha256sum)
checar_dependencias "${DEPS[@]}"
precisa_root

# --------------------------------------------------------------- validacoes
validar_dispositivo() {
  local dev="$1" curto tran removivel montado
  [ -b "$dev" ] || abortar "$dev nao e um dispositivo de bloco."
  curto="$(nome_curto "$dev")"
  [ -d "/sys/block/$curto" ] || abortar "$dev parece ser uma particao. Informe o disco inteiro (ex.: /dev/sdb)."

  # Nunca tocar no disco que hospeda a raiz do sistema.
  local disco_raiz
  disco_raiz="$(lsblk -nrpo PKNAME "$(findmnt -no SOURCE / 2>/dev/null || true)" 2>/dev/null | head -1 || true)"
  if [ -n "$disco_raiz" ] && [ "$disco_raiz" = "$dev" ]; then
    abortar "$dev hospeda o sistema em execucao. Recusando."
  fi

  tran="$(lsblk -ndo TRAN "$dev" 2>/dev/null | tr -d ' ')"
  removivel="$(cat "/sys/block/$curto/removable" 2>/dev/null || echo 0)"
  if [ "$tran" != "usb" ] || [ "$removivel" != "1" ]; then
    aviso "$dev nao aparenta ser um pendrive USB removivel (transporte='$tran', removable=$removivel)."
    [ "$PERMITIR_NAO_REMOVIVEL" = "1" ] || \
      abortar "Use --permitir-nao-removivel se tiver certeza absoluta do destino."
  fi

  montado="$(lsblk -nrpo MOUNTPOINT "$dev" 2>/dev/null | grep -c . || true)"
  [ "$montado" -gt 0 ] && aviso "$dev possui $montado particao(oes) montada(s); serao desmontadas."
  return 0
}
validar_dispositivo "$DISPOSITIVO"

echo
info "Destino: $DISPOSITIVO ($(tamanho_disco "$DISPOSITIVO"))"
lsblk -o NAME,SIZE,TYPE,FSTYPE,LABEL,MOUNTPOINT "$DISPOSITIVO" || true
echo
aviso "TODO o conteudo de $DISPOSITIVO sera APAGADO de forma irreversivel."
confirmar_digitando "$DISPOSITIVO"

# ----------------------------------------------------------------- download
TMPDIR_TRABALHO=""
limpar() {
  local ponto
  for ponto in "${MNT_BOOT:-}" "${MNT_DADOS:-}"; do
    if [ -n "$ponto" ] && mountpoint -q "$ponto" 2>/dev/null; then
      umount "$ponto" 2>/dev/null || true
    fi
  done
  if [ -n "$TMPDIR_TRABALHO" ] && [ -d "$TMPDIR_TRABALHO" ]; then
    rm -rf "$TMPDIR_TRABALHO"
  fi
}
trap limpar EXIT

descobrir_versao() {
  local html
  html="$(curl -fsSL --max-time 30 "$MIRROR/" 2>/dev/null || true)"
  printf '%s' "$html" \
    | grep -oE "clonezilla-live-[0-9]+\.[0-9]+\.[0-9]+-[0-9]+-${ARQUITETURA}\.zip" \
    | sed -E "s/clonezilla-live-(.*)-${ARQUITETURA}\.zip/\1/" \
    | sort -V | tail -1
}

baixar_zip() {
  local versao="$1" destino="$2" arquivo url
  arquivo="clonezilla-live-${versao}-${ARQUITETURA}.zip"
  url="$MIRROR/$arquivo"
  info "Baixando $arquivo"
  executar curl -fL --retry 4 --retry-delay 2 --progress-bar -o "$destino/$arquivo" "$url" \
    || abortar "Falha ao baixar $url (use --zip com um arquivo local)."
  if [ "$VERIFICAR" = "1" ] && [ "$SIMULAR" != "1" ]; then
    local esperado
    esperado="$(curl -fsSL --max-time 30 "$MIRROR/CHECKSUMS.TXT" 2>/dev/null \
      | grep -F "$arquivo" | grep -oE '^[0-9a-f]{64}' | head -1 || true)"
    if [ -n "$esperado" ]; then
      local obtido
      obtido="$(sha256sum "$destino/$arquivo" | cut -d' ' -f1)"
      [ "$obtido" = "$esperado" ] || abortar "SHA256 divergente! esperado=$esperado obtido=$obtido"
      ok "SHA256 conferido."
    else
      aviso "Nao foi possivel obter o SHA256 oficial; seguindo sem verificacao."
    fi
  fi
  printf '%s/%s\n' "$destino" "$arquivo"
}

TMPDIR_TRABALHO="$(mktemp -d -t preparar-pendrive.XXXXXX)"
if [ -n "$ZIP_LOCAL" ]; then
  [ -f "$ZIP_LOCAL" ] || abortar "Arquivo nao encontrado: $ZIP_LOCAL"
  ARQUIVO_ZIP="$ZIP_LOCAL"
  info "Usando imagem local: $ARQUIVO_ZIP"
else
  if [ -z "$VERSAO" ]; then
    VERSAO="$(descobrir_versao)"
    if [ -z "$VERSAO" ]; then
      VERSAO="$VERSAO_FALLBACK"
      aviso "Nao consegui listar o espelho; usando versao fixa $VERSAO."
    else
      info "Ultima versao estavel encontrada: $VERSAO"
    fi
  fi
  ARQUIVO_ZIP="$(baixar_zip "$VERSAO" "$TMPDIR_TRABALHO")"
fi

# --------------------------------------------------------------- particionar
PART_BOOT="$(nome_particao "$DISPOSITIVO" 1)"
PART_DADOS="$(nome_particao "$DISPOSITIVO" 2)"

desmontar_disco "$DISPOSITIVO"
info "Limpando assinaturas antigas de $DISPOSITIVO"
executar wipefs -a "$DISPOSITIVO" >/dev/null

if [ "$ESQUEMA" = "mbr" ]; then
  info "Criando tabela MBR (BIOS + UEFI)"
  executar parted -s "$DISPOSITIVO" mklabel msdos
  executar parted -s "$DISPOSITIVO" mkpart primary fat32 1MiB "$TAMANHO_BOOT"
  executar parted -s "$DISPOSITIVO" set 1 boot on
  executar parted -s "$DISPOSITIVO" set 1 lba on
  executar parted -s "$DISPOSITIVO" mkpart primary "$TAMANHO_BOOT" 100%
else
  info "Criando tabela GPT (UEFI)"
  executar sgdisk -o "$DISPOSITIVO" >/dev/null
  executar sgdisk -n "1:1MiB:+$TAMANHO_BOOT" -t 1:EF00 -c 1:"$ROTULO_BOOT" "$DISPOSITIVO" >/dev/null
  executar sgdisk -n 2:0:0 -t 2:8300 -c 2:"$ROTULO_DADOS" "$DISPOSITIVO" >/dev/null
  executar sgdisk -A 1:set:2 "$DISPOSITIVO" >/dev/null   # legacy BIOS bootable
fi
reler_particoes "$DISPOSITIVO"

info "Formatando $PART_BOOT (FAT32, rotulo $ROTULO_BOOT)"
executar mkfs.vfat -F 32 -n "$ROTULO_BOOT" "$PART_BOOT" >/dev/null

info "Formatando $PART_DADOS ($FS_DADOS, rotulo $ROTULO_DADOS)"
case "$FS_DADOS" in
  ext4)  executar mkfs.ext4 -F -q -L "$ROTULO_DADOS" -m 0 "$PART_DADOS" ;;
  ntfs)  executar mkfs.ntfs -f -L "$ROTULO_DADOS" "$PART_DADOS" >/dev/null ;;
  exfat) executar mkfs.exfat -n "$ROTULO_DADOS" "$PART_DADOS" >/dev/null ;;
  vfat)  executar mkfs.vfat -F 32 -n "$ROTULO_DADOS" "$PART_DADOS" >/dev/null
         aviso "vfat limita cada arquivo a 4 GiB; use -i 4096 ao salvar imagens." ;;
esac
reler_particoes "$DISPOSITIVO"

# ------------------------------------------------------ copiar clonezilla
MNT_BOOT="$TMPDIR_TRABALHO/boot"
MNT_DADOS="$TMPDIR_TRABALHO/dados"
mkdir -p "$MNT_BOOT" "$MNT_DADOS"

info "Extraindo Clonezilla Live em $PART_BOOT"
executar mount "$PART_BOOT" "$MNT_BOOT"
executar unzip -q -o "$ARQUIVO_ZIP" -d "$MNT_BOOT"
executar sync

instalar_boot_bios() {
  local makeboot="$MNT_BOOT/utils/linux/makeboot.sh"
  if [ "$SIMULAR" = "1" ]; then
    printf '%s[simular]%s makeboot.sh %s\n' "$C_AMAR" "$C_RESET" "$PART_BOOT"
    return 0
  fi
  if [ -f "$makeboot" ]; then
    info "Instalando o carregador de boot legado (syslinux)"
    if ( cd "$MNT_BOOT/utils/linux" && printf 'y\ny\n' | bash makeboot.sh "$PART_BOOT" >/dev/null 2>&1 ); then
      ok "Boot BIOS/legado configurado."
      return 0
    fi
    aviso "makeboot.sh falhou; tentando syslinux manualmente."
  fi
  if command -v syslinux >/dev/null 2>&1; then
    umount "$MNT_BOOT"
    syslinux --install --directory /syslinux "$PART_BOOT" >/dev/null 2>&1 || \
      aviso "syslinux --install falhou."
    mount "$PART_BOOT" "$MNT_BOOT"
    local mbrbin
    for mbrbin in /usr/lib/syslinux/mbr/mbr.bin /usr/lib/SYSLINUX/mbr.bin \
                  /usr/share/syslinux/mbr.bin /usr/lib/syslinux/mbr.bin; do
      if [ -f "$mbrbin" ] && [ "$ESQUEMA" = "mbr" ]; then
        dd if="$mbrbin" of="$DISPOSITIVO" bs=440 count=1 conv=notrunc status=none && \
          ok "Codigo de boot MBR gravado ($mbrbin)"
        break
      fi
    done
  else
    aviso "syslinux nao encontrado: o pendrive vai inicializar apenas em modo UEFI."
  fi
}
instalar_boot_bios

if [ "$SIMULAR" != "1" ]; then
  [ -f "$MNT_BOOT/EFI/boot/bootx64.efi" ] || aviso "bootx64.efi nao encontrado - boot UEFI pode falhar."
  [ -f "$MNT_BOOT/live/vmlinuz" ] || aviso "live/vmlinuz nao encontrado - conteudo do zip parece incompleto."
fi
executar sync
executar umount "$MNT_BOOT"

# ----------------------------------------------- preparar particao de dados
info "Preparando o repositorio de imagens em $PART_DADOS"
executar mount "$PART_DADOS" "$MNT_DADOS"
executar mkdir -p "$MNT_DADOS/imagens" "$MNT_DADOS/scripts" "$MNT_DADOS/docs" "$MNT_DADOS/logs"

if [ "$SIMULAR" != "1" ]; then
  rsync -a --delete "$DIR_SCRIPT/" "$MNT_DADOS/scripts/"
  [ -d "$DIR_RAIZ/docs" ] && rsync -a --delete "$DIR_RAIZ/docs/" "$MNT_DADOS/docs/"
  [ -f "$DIR_RAIZ/README.md" ] && cp "$DIR_RAIZ/README.md" "$MNT_DADOS/docs/"
  chmod +x "$MNT_DADOS"/scripts/*.sh 2>/dev/null || true
  if [ -n "$CFG_SERVIDOR" ]; then
    cat > "$MNT_DADOS/rede.conf" <<CONF
# Repositorio de imagens na rede do escritorio.
# Gerado por preparar-pendrive.sh em $(date '+%d/%m/%Y %H:%M').
# Modelo completo em scripts/rede.conf.exemplo.
SERVIDOR=$CFG_SERVIDOR
PROTOCOLO=$CFG_PROTOCOLO
CAMINHO=$CFG_CAMINHO
USUARIO=$CFG_USUARIO
CONF
    chmod 600 "$MNT_DADOS/rede.conf"
  fi
  cat > "$MNT_DADOS/LEIAME.txt" <<LEIAME
Pendrive de clonagem - Clonezilla Live
Preparado em: $(date '+%d/%m/%Y %H:%M')
Versao Clonezilla: ${VERSAO:-$(basename "$ARQUIVO_ZIP")}
Esquema: $ESQUEMA | Boot: $ROTULO_BOOT (FAT32) | Dados: $ROTULO_DADOS ($FS_DADOS)

Pastas:
  imagens/  -> imagens do Clonezilla (repositorio /home/partimag)
  scripts/  -> clonar-maquina.sh, restaurar-maquina.sh, sincronizar-imagens.sh
  logs/     -> logs das operacoes
  docs/     -> guias de uso
  rede.conf -> servidor de imagens do escritorio (quando configurado)

Repositorio de imagens: ${CFG_SERVIDOR:-somente o pendrive}

No Clonezilla Live, escolha "Enter_shell" e execute:
  sudo mkdir -p /home/partimag
  sudo mount -L $ROTULO_DADOS /home/partimag
  sudo /home/partimag/scripts/verificar-rede.sh      # conferir o servidor
  sudo /home/partimag/scripts/clonar-maquina.sh      # capturar imagem
  sudo /home/partimag/scripts/restaurar-maquina.sh   # gravar imagem

Sem rede, acrescente --local para usar as imagens do proprio pendrive.
LEIAME
fi
executar sync
executar umount "$MNT_DADOS"

echo
ok "Pendrive pronto."
lsblk -o NAME,SIZE,TYPE,FSTYPE,LABEL "$DISPOSITIVO" || true
cat <<FIM

Proximos passos:
  1. Inicialize a maquina modelo pelo pendrive (BIOS/UEFI, Secure Boot desligado).
  2. Escolha "Clonezilla live" no menu e depois "Enter_shell" para usar os scripts,
     ou siga o assistente padrao salvando em /home/partimag.
  3. No shell: sudo mount -L $ROTULO_DADOS /home/partimag
     Conferir a rede:  sudo /home/partimag/scripts/verificar-rede.sh
     Capturar imagem:  sudo /home/partimag/scripts/clonar-maquina.sh
     Restaurar imagem: sudo /home/partimag/scripts/restaurar-maquina.sh
  Repositorio de imagens: ${CFG_SERVIDOR:-pendrive (nenhum servidor configurado)}
  Para configurar o servidor depois, copie scripts/rede.conf.exemplo para
  a raiz da particao $ROTULO_DADOS como rede.conf e ajuste os valores.
  Detalhes em docs/02-criar-imagem-mestre.md, docs/03-restaurar-em-lote.md
  e docs/07-imagens-no-servidor.md
FIM
