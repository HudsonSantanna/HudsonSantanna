#!/usr/bin/env bash
# rede.sh - funcoes para usar o repositorio de imagens (o "cerebro") em um
# servidor da rede do escritorio, no lugar do proprio pendrive.
# Uso: source "$(dirname "$0")/lib/comum.sh"; source ".../lib/rede.sh"

# Parametros da rede do escritorio. Vem, nesta ordem, de:
#   1. opcoes de linha de comando (CLI_*)
#   2. arquivo de configuracao (rede.conf)
#   3. os padroes abaixo
REDE_SERVIDOR="${REDE_SERVIDOR:-}"        # IP ou nome do servidor
REDE_PROTOCOLO="${REDE_PROTOCOLO:-ssh}"   # ssh | nfs | smb
REDE_CAMINHO="${REDE_CAMINHO:-}"          # caminho exportado / compartilhamento
REDE_USUARIO="${REDE_USUARIO:-}"
REDE_PORTA="${REDE_PORTA:-}"
REDE_CREDENCIAIS="${REDE_CREDENCIAIS:-}"  # chave ssh ou arquivo de credenciais smb
REDE_DOMINIO="${REDE_DOMINIO:-}"          # dominio Windows (smb)
REDE_OPCOES="${REDE_OPCOES:-}"            # opcoes extras de montagem, separadas por virgula
REDE_INTERFACE="${REDE_INTERFACE:-}"      # ex.: enp3s0 (vazio = detectar)
REDE_IP="${REDE_IP:-}"                    # ex.: 192.168.0.50/24 (vazio = DHCP)
REDE_GATEWAY="${REDE_GATEWAY:-}"
REDE_DNS="${REDE_DNS:-}"
REDE_CONFIG_USADA=""

# Chaves aceitas no rede.conf (viram REDE_<CHAVE>).
REDE_CHAVES=(SERVIDOR PROTOCOLO CAMINHO USUARIO PORTA CREDENCIAIS DOMINIO \
             OPCOES INTERFACE IP GATEWAY DNS)

# ------------------------------------------------------------- configuracao
# rede_carregar_config [arquivo] -> le o primeiro rede.conf encontrado.
rede_carregar_config() {
  local pedido="${1:-}" arquivo linha chave valor
  local candidatos=()
  if [ -n "$pedido" ]; then
    [ -f "$pedido" ] || abortar "Arquivo de configuracao nao encontrado: $pedido"
    candidatos=("$pedido")
  else
    candidatos=(
      "${KIT_CONFIG:-}"
      "${DIR_SCRIPT:-.}/rede.conf"
      "/home/partimag/rede.conf"
      "/etc/kit-clonagem/rede.conf"
    )
  fi

  local nome
  for arquivo in "${candidatos[@]}"; do
    [ -n "$arquivo" ] || continue
    [ -f "$arquivo" ] || continue
    nome="$(basename "$arquivo")"
    while IFS= read -r linha || [ -n "$linha" ]; do
      linha="${linha%%#*}"
      linha="${linha#"${linha%%[![:space:]]*}"}"
      linha="${linha%"${linha##*[![:space:]]}"}"
      [ -n "$linha" ] || continue
      case "$linha" in *=*) ;; *) continue ;; esac
      chave="${linha%%=*}"; valor="${linha#*=}"
      chave="$(printf '%s' "$chave" | tr -d '[:space:]' | tr '[:lower:]' '[:upper:]')"
      valor="${valor#"${valor%%[![:space:]]*}"}"
      valor="${valor%\"}"; valor="${valor#\"}"
      valor="${valor%\'}"; valor="${valor#\'}"
      if rede_chave_valida "$chave"; then
        printf -v "REDE_$chave" '%s' "$valor"
      else
        aviso "Chave ignorada em $nome: $chave"
      fi
    done < "$arquivo"
    # shellcheck disable=SC2034  # usada pelos scripts que carregam esta lib.
    REDE_CONFIG_USADA="$arquivo"
    info "Configuracao da rede lida de $arquivo"
    return 0
  done
  return 1
}

rede_chave_valida() {
  local alvo="$1" chave
  for chave in "${REDE_CHAVES[@]}"; do
    [ "$chave" = "$alvo" ] && return 0
  done
  return 1
}

# rede_aplicar_cli -> opcoes de linha de comando (CLI_SERVIDOR, CLI_PORTA, ...)
# vencem o que veio do arquivo de configuracao.
rede_aplicar_cli() {
  local chave nome_cli
  for chave in "${REDE_CHAVES[@]}"; do
    nome_cli="CLI_$chave"
    [ -n "${!nome_cli:-}" ] && printf -v "REDE_$chave" '%s' "${!nome_cli}"
  done
  REDE_PROTOCOLO="$(printf '%s' "$REDE_PROTOCOLO" | tr '[:upper:]' '[:lower:]')"
  case "$REDE_PROTOCOLO" in
    ssh|sshfs) REDE_PROTOCOLO="ssh" ;;
    nfs) ;;
    smb|cifs|samba|windows) REDE_PROTOCOLO="smb" ;;
    *) abortar "Protocolo desconhecido: $REDE_PROTOCOLO (use ssh, nfs ou smb)." ;;
  esac
}

# Verdadeiro quando ha um servidor configurado.
rede_configurada() { [ -n "$REDE_SERVIDOR" ]; }

# Endereco legivel do repositorio remoto.
rede_alvo() {
  case "$REDE_PROTOCOLO" in
    ssh) printf '%s%s:%s\n' "${REDE_USUARIO:+$REDE_USUARIO@}" "$REDE_SERVIDOR" "$REDE_CAMINHO" ;;
    nfs) printf '%s:%s\n' "$REDE_SERVIDOR" "$REDE_CAMINHO" ;;
    smb) printf '//%s/%s\n' "$REDE_SERVIDOR" "${REDE_CAMINHO#/}" ;;
  esac
}

# Cada protocolo precisa do seu utilitario de montagem.
rede_checar_dependencias() {
  local faltando=() cmd
  case "$REDE_PROTOCOLO" in
    ssh) for cmd in sshfs ssh; do command -v "$cmd" >/dev/null 2>&1 || faltando+=("$cmd"); done ;;
    nfs) command -v mount.nfs >/dev/null 2>&1 || faltando+=(mount.nfs) ;;
    smb) command -v mount.cifs >/dev/null 2>&1 || faltando+=(mount.cifs) ;;
  esac
  [ "${#faltando[@]}" -eq 0 ] && return 0
  erro "Comandos ausentes para o protocolo $REDE_PROTOCOLO: ${faltando[*]}"
  case "$REDE_PROTOCOLO" in
    ssh) erro "Debian/Ubuntu: sudo apt install sshfs openssh-client" ;;
    nfs) erro "Debian/Ubuntu: sudo apt install nfs-common" ;;
    smb) erro "Debian/Ubuntu: sudo apt install cifs-utils" ;;
  esac
  erro "No Clonezilla Live sem internet, prefira o protocolo ja disponivel na imagem."
  exit 1
}

# ------------------------------------------------------------------ enlace
rede_tem_ip() {
  if command -v ip >/dev/null 2>&1; then
    ip -4 -o addr show scope global 2>/dev/null | grep -q 'inet '
  elif command -v hostname >/dev/null 2>&1; then
    [ -n "$(hostname -I 2>/dev/null | tr -d '[:space:]')" ]
  else
    return 1
  fi
}

rede_resumo() {
  if command -v ip >/dev/null 2>&1; then
    ip -4 -o addr show scope global 2>/dev/null \
      | awk '{printf "%s %s ", $2, $4}' | sed 's/[[:space:]]*$//'
  else
    hostname -I 2>/dev/null | sed 's/[[:space:]]*$//'
  fi
}

# Primeira interface cabeada com link ativo (ou a informada em REDE_INTERFACE).
rede_interface() {
  local caminho nome
  if [ -n "$REDE_INTERFACE" ]; then printf '%s\n' "$REDE_INTERFACE"; return 0; fi
  for caminho in /sys/class/net/*; do
    nome="$(basename "$caminho")"
    [ "$nome" = "lo" ] && continue
    [ -e "$caminho/device" ] || continue
    if [ "$(cat "$caminho/carrier" 2>/dev/null || echo 0)" = "1" ]; then
      printf '%s\n' "$nome"; return 0
    fi
  done
  return 1
}

rede_pedir_dhcp() {
  local iface="$1"
  if command -v dhclient >/dev/null 2>&1; then
    executar dhclient -v "$iface" || return 1
  elif command -v udhcpc >/dev/null 2>&1; then
    executar udhcpc -i "$iface" -n -q || return 1
  elif command -v dhcpcd >/dev/null 2>&1; then
    executar dhcpcd -w "$iface" || return 1
  else
    return 1
  fi
}

# Deixa a maquina na rede do escritorio (DHCP por padrao, ou IP fixo).
rede_subir() {
  local iface tentativas=0
  if rede_tem_ip; then
    info "Rede ja ativa: $(rede_resumo)"
    return 0
  fi
  if ! iface="$(rede_interface)"; then
    abortar "Nenhuma interface de rede com cabo conectado. Ligue o cabo ou use --interface."
  fi
  command -v ip >/dev/null 2>&1 \
    || abortar "Comando 'ip' (iproute2) ausente: configure a rede a mao antes de rodar este script."
  info "Configurando a interface $iface"
  executar ip link set "$iface" up || true

  if [ -n "$REDE_IP" ]; then
    executar ip addr add "$REDE_IP" dev "$iface" || aviso "IP $REDE_IP ja configurado?"
    if [ -n "$REDE_GATEWAY" ]; then
      executar ip route add default via "$REDE_GATEWAY" || aviso "Rota padrao ja existe?"
    fi
    if [ -n "$REDE_DNS" ] && [ "$SIMULAR" != "1" ]; then
      printf 'nameserver %s\n' "$REDE_DNS" > /etc/resolv.conf
    fi
  else
    info "Pedindo endereco por DHCP em $iface"
    rede_pedir_dhcp "$iface" || aviso "Cliente DHCP falhou ou nao esta instalado."
  fi

  [ "$SIMULAR" = "1" ] && return 0
  while [ "$tentativas" -lt 15 ]; do
    rede_tem_ip && { ok "Rede ativa: $(rede_resumo)"; return 0; }
    sleep 2
    tentativas=$((tentativas + 1))
  done
  abortar "A maquina nao recebeu endereco IP em $iface."
}

# Porta padrao de cada protocolo.
rede_porta_padrao() {
  case "$REDE_PROTOCOLO" in
    ssh) printf '22\n' ;;
    nfs) printf '2049\n' ;;
    smb) printf '445\n' ;;
  esac
}

# Testa se o servidor responde na porta do protocolo escolhido.
rede_testar_servidor() {
  local porta="${REDE_PORTA:-$(rede_porta_padrao)}"
  [ "$SIMULAR" = "1" ] && { info "[simular] teste de conexao com $REDE_SERVIDOR:$porta"; return 0; }

  if command -v ping >/dev/null 2>&1; then
    if ping -c 1 -W 2 "$REDE_SERVIDOR" >/dev/null 2>&1; then
      ok "Servidor $REDE_SERVIDOR responde ao ping."
    else
      aviso "Servidor $REDE_SERVIDOR nao responde ao ping (pode ser firewall)."
    fi
  fi

  if command -v nc >/dev/null 2>&1; then
    nc -z -w 4 "$REDE_SERVIDOR" "$porta" >/dev/null 2>&1 || return 1
  else
    (exec 3<>"/dev/tcp/$REDE_SERVIDOR/$porta") >/dev/null 2>&1 || return 1
  fi
  ok "Porta $porta aberta em $REDE_SERVIDOR."
}

# --------------------------------------------------------------- montagem
# rede_montar_repositorio PONTO [ro] -> monta o cerebro do servidor em PONTO.
rede_montar_repositorio() {
  local ponto="$1" modo="${2:-rw}" porta opcoes=() extras=()
  rede_configurada || abortar "Nenhum servidor configurado (use --servidor ou rede.conf)."
  [ -n "$REDE_CAMINHO" ] || abortar "Caminho do repositorio no servidor nao informado (--caminho)."
  rede_checar_dependencias

  if mountpoint -q "$ponto" 2>/dev/null; then
    info "Ja existe algo montado em $ponto"
    return 0
  fi
  executar mkdir -p "$ponto"

  if [ -n "$REDE_OPCOES" ]; then
    IFS=',' read -r -a extras <<< "$REDE_OPCOES"
  fi

  info "Montando $(rede_alvo) em $ponto ($modo)"
  case "$REDE_PROTOCOLO" in
    ssh)
      local destino="${REDE_USUARIO:+$REDE_USUARIO@}$REDE_SERVIDOR:$REDE_CAMINHO"
      opcoes=(reconnect ServerAliveInterval=15 ServerAliveCountMax=3
              StrictHostKeyChecking=accept-new allow_other)
      [ "$modo" = "ro" ] && opcoes+=(ro)
      [ -n "$REDE_CREDENCIAIS" ] && opcoes+=("IdentityFile=$REDE_CREDENCIAIS")
      [ "${#extras[@]}" -gt 0 ] && opcoes+=("${extras[@]}")
      porta="${REDE_PORTA:-22}"
      executar sshfs -p "$porta" -o "$(IFS=,; printf '%s' "${opcoes[*]}")" \
        "$destino" "$ponto" || abortar "Falha ao montar por SSH. Confira usuario, chave e permissoes."
      ;;
    nfs)
      opcoes=(hard timeo=150 retrans=3)
      [ "$modo" = "ro" ] && opcoes+=(ro) || opcoes+=(rw)
      [ -n "$REDE_PORTA" ] && opcoes+=("port=$REDE_PORTA")
      [ "${#extras[@]}" -gt 0 ] && opcoes+=("${extras[@]}")
      executar mount -t nfs -o "$(IFS=,; printf '%s' "${opcoes[*]}")" \
        "$REDE_SERVIDOR:$REDE_CAMINHO" "$ponto" \
        || abortar "Falha ao montar por NFS. Confira o export no servidor."
      ;;
    smb)
      opcoes=(vers=3.0 iocharset=utf8 uid=0 gid=0)
      [ "$modo" = "ro" ] && opcoes+=(ro) || opcoes+=(rw)
      [ -n "$REDE_PORTA" ] && opcoes+=("port=$REDE_PORTA")
      [ -n "$REDE_DOMINIO" ] && opcoes+=("domain=$REDE_DOMINIO")
      if [ -n "$REDE_CREDENCIAIS" ]; then
        [ -f "$REDE_CREDENCIAIS" ] || abortar "Arquivo de credenciais nao encontrado: $REDE_CREDENCIAIS"
        opcoes+=("credentials=$REDE_CREDENCIAIS")
      elif [ -n "$REDE_USUARIO" ]; then
        # A senha e pedida pelo mount.cifs; nunca passe senha na linha de comando.
        opcoes+=("username=$REDE_USUARIO")
      else
        opcoes+=(guest)
      fi
      [ "${#extras[@]}" -gt 0 ] && opcoes+=("${extras[@]}")
      executar mount -t cifs -o "$(IFS=,; printf '%s' "${opcoes[*]}")" \
        "//$REDE_SERVIDOR/${REDE_CAMINHO#/}" "$ponto" \
        || abortar "Falha ao montar o compartilhamento. Confira usuario, senha e permissoes."
      ;;
  esac
  ok "Repositorio do servidor montado em $ponto"
}

# rede_desmontar PONTO -> desmonta sem derrubar o script se ja estiver solto.
rede_desmontar() {
  local ponto="$1"
  mountpoint -q "$ponto" 2>/dev/null || return 0
  info "Desmontando $ponto"
  if [ "$REDE_PROTOCOLO" = "ssh" ] && command -v fusermount >/dev/null 2>&1; then
    fusermount -u "$ponto" 2>/dev/null && return 0
  fi
  umount "$ponto" 2>/dev/null || umount -l "$ponto" 2>/dev/null || \
    aviso "Nao consegui desmontar $ponto."
}

# Confere se o repositorio remoto tem a estrutura esperada e e gravavel.
rede_conferir_repositorio() {
  local ponto="$1" modo="${2:-rw}" teste
  [ -d "$ponto/imagens" ] || aviso "Pasta imagens/ ainda nao existe em $ponto (sera criada)."
  [ "$modo" = "ro" ] && return 0
  [ "$SIMULAR" = "1" ] && return 0
  teste="$ponto/.escrita-$$"
  if ! (: > "$teste") 2>/dev/null; then
    erro "Sem permissao de escrita em $ponto. Confira o usuario no servidor."
    return 1
  fi
  rm -f "$teste"
}
