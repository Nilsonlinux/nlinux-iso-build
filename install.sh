#!/bin/bash
set -euo pipefail

INSTALL_BASE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
CHROOT_DIR="$INSTALL_BASE/install/chroot"
CONFIG_DIR="$INSTALL_BASE/config"
PACKAGES_DIR="$INSTALL_BASE/packages"
SHARE_DIR="/opt/noctalia-installer"
MNT="/mnt"

COLOR_RESET='\e[0m'
COLOR_CYAN='\e[36m'
COLOR_YELLOW='\e[33m'
COLOR_RED='\e[31m'
COLOR_GREEN='\e[32m'

info()  { echo -e "${COLOR_CYAN}[instalador]${COLOR_RESET} $*"; }
warn()  { echo -e "${COLOR_YELLOW}[atenção]${COLOR_RESET} $*"; }
die()   { echo -e "${COLOR_RED}[erro]${COLOR_RESET} $*" >&2; exit 1; }
ok()    { echo -e "${COLOR_GREEN}[ok]${COLOR_RESET} $*"; }

GUI_DRIVEN="${GUI_DRIVEN:-0}"
# Sinais de progresso do instalador web (lidos pelo web/server.py):
#   NLSTEPS|<pct>:<chave>,…   plano completo das etapas, enviado uma vez
#   NLPROGRESS|<pct>|<chave>  etapa atual com a porcentagem
#   NLSTEP|<chave>            etapa atual; a porcentagem vem do plano
#   NLNOTE|<chave>            atividade temporária (não muda a etapa)
#   NLACT|<chave>|<item>      atividade com nome ("Compilando <pacote>")
#   NLRESULT|<rc>             resultado final (trap EXIT)
# <chave> é uma chave de tradução (o <item> entra no %s dela); o
# web/server.py traduz para o NLLANG. Tudo só é emitido quando dirigido pela
# web, para não poluir o modo standalone.
progress() {
  [[ "$GUI_DRIVEN" == "1" ]] || return 0
  printf 'NLPROGRESS|%s|%s\n' "$1" "$2"
}
note() {
  [[ "$GUI_DRIVEN" == "1" ]] || return 0
  printf 'NLNOTE|%s\n' "$1"
}
# Atividade com argumento: o texto final é a tradução da chave com %s trocado
# pelo item ("Compilando umbriel-git"). É o que aparece junto da etapa no
# painel, e é emitido pelo que realmente está acontecendo agora.
act() {
  [[ "$GUI_DRIVEN" == "1" ]] || return 0
  printf 'NLACT|%s|%s\n' "$1" "$2"
}

# ---------------------------------------------------------------------------
# Plano de etapas do instalador web
# ---------------------------------------------------------------------------
# Lista ordenada das etapas NA ORDEM em que o instalador realmente executa, e
# diferentes entre o modo offline (cópia do pendrive) e o online (pacstrap +
# AUR). É a fonte única: o plano é enviado ao navegador e a porcentagem de
# cada etapa sai dele — assim a lista da tela não pode divergir do que o script
# está fazendo.
#
# O número de cada etapa é o PONTO EM QUE ELA COMEÇA, e a distância entre duas
# etapas é o PESO dela: quanto da instalação inteira aquela etapa deve ocupar.
# O web/server.py usa essa distância para desenhar o progresso real da etapa
# (bytes do cache, % do rsync) e o ritmo do anel entre uma etapa e outra — por
# isso o anel anda o tempo todo e chega a 100%. Os pesos abaixo vieram de uma
# instalação real: no online, a AUR é a etapa mais longa (compilar o yay em
# Rust + os pacotes da AUR), e no offline a cópia do pendrive é quase tudo.
PLAN=()
plan_add() { PLAN+=("$1|$2"); }   # <chave>|<começo da etapa, em %>

build_plan() {
  PLAN=()
  plan_add stage.lang_key 0       # 0 -> 2    teclado e idioma
  plan_add stage.mirror 2         # 2 -> 4    espelho
  plan_add stage.disk 4           # 4 -> 9    particionamento
  plan_add stage.fs 9             # 9 -> 13   formatação
  if (( OFFLINE )); then
    plan_add stage.copy.offline 13  # 13 -> 72  cópia do pendrive (59)
    plan_add stage.chroot.system 72 # 72 -> 85  boot, initramfs, usuário (13)
    plan_add stage.chroot.desktop 85  # 85 -> 96  desktop e serviços (11)
  else
    plan_add stage.pac.download 13  # 13 -> 38  pacstrap: baixar e instalar (25)
    plan_add stage.chroot.system 38 # 38 -> 54  boot, initramfs, usuário (16)
    plan_add stage.chroot.aur 54    # 54 -> 85  yay e pacotes da AUR (31)
    plan_add stage.chroot.desktop 85  # 85 -> 96  desktop e serviços (11)
  fi
  plan_add stage.boot 96          # 96 -> 99   bootloader
  plan_add stage.final 99         # 99 -> 100  finalizando
  local item out=""
  for item in "${PLAN[@]}"; do
    out+="${out:+,}${item#*|}:${item%%|*}"
  done
  [[ "$GUI_DRIVEN" == "1" ]] && printf 'NLSTEPS|%s\n' "$out"
  return 0
}

# Anuncia a etapa atual: a porcentagem vem do plano (fonte única). Vai pelo
# NLPROGRESS (e não NLSTEP) de propósito — se a linha NLSTEPS se perder no
# log (execução antiga reanexada), a etapa ainda chega com a % certa.
stage() {
  local key=$1 item pct=""
  for item in "${PLAN[@]}"; do
    if [[ "${item%%|*}" == "$key" ]]; then
      pct="${item#*|}"
      break
    fi
  done
  progress "${pct:-0}" "$key"
}

# ---------------------------------------------------------------------------
# Valores padrão. Sobrescreva exportando variáveis antes de executar:
#   INSTALL_USER=foo INSTALL_DISK=/dev/sda ./install.sh
# ---------------------------------------------------------------------------
INSTALL_USER="${INSTALL_USER:-nlinux}"
INSTALL_USER_PASS="${INSTALL_USER_PASS:-nlinux}"
ROOT_PASS="${ROOT_PASS:-nlinux}"
LUKS_PASS="${LUKS_PASS:-nlinux}"
HOSTNAME="${HOSTNAME:-nlinux}"
LOCALE="${LOCALE:-pt_BR.UTF-8}"
KEYMAP="${KEYMAP:-br-abnt2}"
ZONEINFO="${ZONEINFO:-America/Sao_Paulo}"
MIRROR="${MIRROR:-}"
OFFLINE="${OFFLINE:-1}"
DISK="${INSTALL_DISK:-}"
FS_TYPE="${FS_TYPE:-}"
INSTALL_MODE="${INSTALL_MODE:-wipe}"
DUAL_RESIZE_PARTITION="${DUAL_RESIZE_PARTITION:-}"
DUAL_RESIZE_BYTES="${DUAL_RESIZE_BYTES:-0}"
DUAL_ROOT_START_SECTOR=""
DUAL_ROOT_END_SECTOR=""
USE_LUKS="${USE_LUKS:-}"
GPU="${GPU:-}"
MICROCODE="${MICROCODE:-}"

# Idioma da interface do instalador (escolhido no menu pelo país). É distinto de
# LANG, que é o locale do sistema instalado.
NLLANG="${NLLANG:-pt}"
NLLANG="${NLLANG%%_*}"
case "$NLLANG" in pt|en|es|fr|de|it|ja) ;; *) NLLANG=pt ;; esac

# Traduções do modo standalone/terminal (exibidas no resumo/saída).
declare -A _si18n_pt _si18n_en _si18n_es _si18n_fr _si18n_de _si18n_it _si18n_ja
_si18n_pt["summary"]="Resumo da instalação:"
_si18n_pt["sum.disk"]="Disco:"
_si18n_pt["sum.part"]="Partição:"
_si18n_pt["part.wipe"]="Apagar disco inteiro"
_si18n_pt["part.dual"]="Dual boot"
_si18n_pt["sum.fs"]="FS:"
_si18n_pt["sum.luks"]="LUKS:"
_si18n_pt["sum.yes"]="Sim"
_si18n_pt["sum.no"]="Não"
_si18n_pt["sum.user"]="Usuário:"
_si18n_pt["sum.hostname"]="Hostname:"
_si18n_pt["sum.locale"]="Locale:"
_si18n_pt["sum.keymap"]="Keymap:"
_si18n_pt["sum.zone"]="Zona:"
_si18n_pt["sum.mirror"]="Espelho:"
_si18n_pt["sum.mirror.auto"]="Auto (padrão)"
_si18n_pt["sum.mode"]="Modo:"
_si18n_pt["sum.mode.offline"]="Rápido offline (cópia do pendrive)"
_si18n_pt["sum.mode.online"]="Completo online (pacstrap)"
_si18n_pt["sum.gpu"]="GPU:"
_si18n_pt["sum.microcode"]="Microcode:"
_si18n_en["summary"]="Installation summary:"
_si18n_en["sum.disk"]="Disk:"
_si18n_en["sum.part"]="Partition:"
_si18n_en["part.wipe"]="Wipe entire disk"
_si18n_en["part.dual"]="Dual boot"
_si18n_en["sum.fs"]="FS:"
_si18n_en["sum.luks"]="LUKS:"
_si18n_en["sum.yes"]="Yes"
_si18n_en["sum.no"]="No"
_si18n_en["sum.user"]="User:"
_si18n_en["sum.hostname"]="Hostname:"
_si18n_en["sum.locale"]="Locale:"
_si18n_en["sum.keymap"]="Keymap:"
_si18n_en["sum.zone"]="Zone:"
_si18n_en["sum.mirror"]="Mirror:"
_si18n_en["sum.mirror.auto"]="Auto (default)"
_si18n_en["sum.mode"]="Mode:"
_si18n_en["sum.mode.offline"]="Quick offline (copy from USB)"
_si18n_en["sum.mode.online"]="Full online (pacstrap)"
_si18n_en["sum.gpu"]="GPU:"
_si18n_en["sum.microcode"]="Microcode:"
_si18n_es["summary"]="Resumen de la instalación:"
_si18n_es["sum.disk"]="Disco:"
_si18n_es["sum.part"]="Partición:"
_si18n_es["part.wipe"]="Borrar disco entero"
_si18n_es["part.dual"]="Dual boot"
_si18n_es["sum.fs"]="FS:"
_si18n_es["sum.luks"]="LUKS:"
_si18n_es["sum.yes"]="Sí"
_si18n_es["sum.no"]="No"
_si18n_es["sum.user"]="Usuario:"
_si18n_es["sum.hostname"]="Hostname:"
_si18n_es["sum.locale"]="Locale:"
_si18n_es["sum.keymap"]="Keymap:"
_si18n_es["sum.zone"]="Zona:"
_si18n_es["sum.mirror"]="Espejo:"
_si18n_es["sum.mirror.auto"]="Auto (predeterminado)"
_si18n_es["sum.mode"]="Modo:"
_si18n_es["sum.mode.offline"]="Rápido offline (copia desde USB)"
_si18n_es["sum.mode.online"]="Completo online (pacstrap)"
_si18n_es["sum.gpu"]="GPU:"
_si18n_es["sum.microcode"]="Microcódigo:"
_si18n_fr["summary"]="Résumé de l'installation :"
_si18n_fr["sum.disk"]="Disque :"
_si18n_fr["sum.part"]="Partition :"
_si18n_fr["part.wipe"]="Effacer le disque"
_si18n_fr["part.dual"]="Dual boot"
_si18n_fr["sum.fs"]="FS :"
_si18n_fr["sum.luks"]="LUKS :"
_si18n_fr["sum.yes"]="Oui"
_si18n_fr["sum.no"]="Non"
_si18n_fr["sum.user"]="Utilisateur :"
_si18n_fr["sum.hostname"]="Nom d'hôte :"
_si18n_fr["sum.locale"]="Locale :"
_si18n_fr["sum.keymap"]="Keymap :"
_si18n_fr["sum.zone"]="Zone :"
_si18n_fr["sum.mirror"]="Miroir :"
_si18n_fr["sum.mirror.auto"]="Auto (par défaut)"
_si18n_fr["sum.mode"]="Mode :"
_si18n_fr["sum.mode.offline"]="Rapide hors ligne (copie depuis la clé USB)"
_si18n_fr["sum.mode.online"]="Complète en ligne (pacstrap)"
_si18n_fr["sum.gpu"]="GPU :"
_si18n_fr["sum.microcode"]="Microcode :"
_si18n_de["summary"]="Installationsübersicht:"
_si18n_de["sum.disk"]="Festplatte:"
_si18n_de["sum.part"]="Partition:"
_si18n_de["part.wipe"]="Festplatte löschen"
_si18n_de["part.dual"]="Dualboot"
_si18n_de["sum.fs"]="FS:"
_si18n_de["sum.luks"]="LUKS:"
_si18n_de["sum.yes"]="Ja"
_si18n_de["sum.no"]="Nein"
_si18n_de["sum.user"]="Benutzer:"
_si18n_de["sum.hostname"]="Hostname:"
_si18n_de["sum.locale"]="Locale:"
_si18n_de["sum.keymap"]="Keymap:"
_si18n_de["sum.zone"]="Zone:"
_si18n_de["sum.mirror"]="Spiegel:"
_si18n_de["sum.mirror.auto"]="Auto (Standard)"
_si18n_de["sum.mode"]="Modus:"
_si18n_de["sum.mode.offline"]="Schnell offline (Kopie vom USB)"
_si18n_de["sum.mode.online"]="Vollständig online (pacstrap)"
_si18n_de["sum.gpu"]="GPU:"
_si18n_de["sum.microcode"]="Mikrocode:"
_si18n_it["summary"]="Riepilogo dell'installazione:"
_si18n_it["sum.disk"]="Disco:"
_si18n_it["sum.part"]="Partizione:"
_si18n_it["part.wipe"]="Cancella disco"
_si18n_it["part.dual"]="Dual boot"
_si18n_it["sum.fs"]="FS:"
_si18n_it["sum.luks"]="LUKS:"
_si18n_it["sum.yes"]="Sì"
_si18n_it["sum.no"]="No"
_si18n_it["sum.user"]="Utente:"
_si18n_it["sum.hostname"]="Hostname:"
_si18n_it["sum.locale"]="Locale:"
_si18n_it["sum.keymap"]="Keymap:"
_si18n_it["sum.zone"]="Zona:"
_si18n_it["sum.mirror"]="Mirror:"
_si18n_it["sum.mirror.auto"]="Auto (predefinito)"
_si18n_it["sum.mode"]="Modalità:"
_si18n_it["sum.mode.offline"]="Rapida offline (copia dalla USB)"
_si18n_it["sum.mode.online"]="Completa online (pacstrap)"
_si18n_it["sum.gpu"]="GPU:"
_si18n_it["sum.microcode"]="Microcodice:"
_si18n_ja["summary"]="インストールの要約:"
_si18n_ja["sum.disk"]="ディスク:"
_si18n_ja["sum.part"]="パーティション:"
_si18n_ja["part.wipe"]="ディスク全体を消去"
_si18n_ja["part.dual"]="デュアルブート"
_si18n_ja["sum.fs"]="FS:"
_si18n_ja["sum.luks"]="LUKS:"
_si18n_ja["sum.yes"]="はい"
_si18n_ja["sum.no"]="いいえ"
_si18n_ja["sum.user"]="ユーザー:"
_si18n_ja["sum.hostname"]="ホスト名:"
_si18n_ja["sum.locale"]="ロケール:"
_si18n_ja["sum.keymap"]="キーマップ:"
_si18n_ja["sum.zone"]="ゾーン:"
_si18n_ja["sum.mirror"]="ミラー:"
_si18n_ja["sum.mirror.auto"]="自動 (既定)"
_si18n_ja["sum.mode"]="モード:"
_si18n_ja["sum.mode.offline"]="高速オフライン (USBからコピー)"
_si18n_ja["sum.mode.online"]="完全オンライン (pacstrap)"
_si18n_ja["sum.gpu"]="GPU:"
_si18n_ja["sum.microcode"]="マイクロコード:"

T() {
  # t <chave>: string no idioma NLLANG, com fallback para o português.
  local key=$1
  local -n _tbl="_si18n_${NLLANG}"
  if [[ -n "${_tbl[$key]:-}" ]]; then
    printf '%s' "${_tbl[$key]}"
  else
    local -n _pt="_si18n_pt"
    printf '%s' "${_pt[$key]:-$key}"
  fi
}


# ---------------------------------------------------------------------------
# Coleta de opções
# ---------------------------------------------------------------------------
collect_options() {
  if [[ "$GUI_DRIVEN" == "1" ]]; then
    # Opções fornecidas pela interface web (env). Não refaz perguntas.
    info "Opções fornecidas pela interface web; validando..."
    validate_options
    print_summary
    return 0
  fi
  # Modo standalone: apenas prompts de texto no terminal (sem curses; a
  # única interface gráfica do instalador é a web — nlinux-installer).
  info "Coletando opções de instalação."
  collect_options_prompt
  validate_options
  print_summary
  is_prompt_y "Confirmar e iniciar a instalação? ** ESTE DISCO SERÁ APAGADO **" || die "Cancelado pelo usuário."
}

collect_options_prompt() {
  info "Coletando opções via prompts (fallback)."
  if [[ -z "$ROOT_PASS" ]]; then
    read_secret ROOT_PASS "Senha do usuário root"
  fi
  if [[ -z "$INSTALL_USER" ]]; then
    read_val INSTALL_USER "Nome do usuário (sem espaços, minúsculo)" ""
  fi
  if [[ -z "$INSTALL_USER_PASS" ]]; then
    read_secret INSTALL_USER_PASS "Senha do usuário $INSTALL_USER"
  fi

  read_val HOSTNAME "Hostname da máquina" "$HOSTNAME"
  read_val LOCALE "Locale (ex.: pt_BR.UTF-8, en_US.UTF-8)" "$LOCALE"
  read_val KEYMAP "Layout de teclado (ex.: br-abnt2, us, de)" "$KEYMAP"
  read_val ZONEINFO "Fuso horário (ex.: America/Sao_Paulo)" "$ZONEINFO"

  if [[ -z "$MIRROR" ]]; then
    read -r -p "Espelho de repositórios (URL base, vazio = padrão): " MIRROR
  fi
  local _ans
  read -r -p "Instalação rápida OFFLINE (copia o sistema do pendrive, sem internet)? (S/n): " _ans
  if [[ -z "$_ans" || "${_ans,,}" == "s" || "${_ans,,}" == "y" ]]; then
    OFFLINE=1
  else
    OFFLINE=0
  fi

  if [[ -z "$GPU" ]]; then
    read_val GPU "GPU (intel | amd | nvidia | vm)" ""
  fi
  if [[ -z "$MICROCODE" ]]; then
    if grep -qi "GenuineIntel" /proc/cpuinfo; then MICROCODE=intel; fi
    if grep -qi "AuthenticAMD" /proc/cpuinfo; then MICROCODE=amd; fi
    MICROCODE="${MICROCODE:-none}"
    info "Microcódigo detectado: $MICROCODE."
  fi

  if [[ -z "$DISK" ]]; then
    info "Discos disponíveis:"
    lsblk -dplno NAME,SIZE,MODEL | grep -E '^/dev/(sd|nvme|vd)' || die "Nenhum disco encontrado."
    read -r -p "Disco de destino (ex.: /dev/nvme0n1): " DISK
  fi
  if [[ -z "$INSTALL_MODE" ]]; then
    read -r -p "Modo (wipe=apagar disco inteiro | dual=instalar ao lado de outro sistema) [wipe]: " INSTALL_MODE
    INSTALL_MODE="${INSTALL_MODE:-wipe}"
  fi
  if [[ -z "$FS_TYPE" ]]; then
    read -r -p "Sistema de arquivos (ext4 | btrfs) [ext4]: " FS_TYPE
    FS_TYPE="${FS_TYPE:-ext4}"
  fi
  if [[ -z "$USE_LUKS" ]]; then
    if is_prompt_y "Criptografar o disco com LUKS2?"; then
      USE_LUKS=1
    else
      USE_LUKS=0
    fi
  fi
  if (( USE_LUKS )) && [[ -z "$LUKS_PASS" ]]; then
    read_secret LUKS_PASS "Senha da criptografia (LUKS)"
  fi
}

validate_options() {
  [[ "$INSTALL_USER" =~ ^[a-z_][a-z0-9_-]*$ ]] || die "Usuário inválido: $INSTALL_USER"
  [[ -b "$DISK" ]] || die "Nenhum disco válido selecionado: $DISK (use INSTALL_DISK ou escolha no menu)."
  INSTALL_MODE="${INSTALL_MODE:-wipe}"
  [[ "$INSTALL_MODE" =~ ^(wipe|dual)$ ]] || die "Modo de instalação inválido: $INSTALL_MODE"
  [[ "$DUAL_RESIZE_BYTES" =~ ^[0-9]+$ ]] || die "Tamanho de redimensionamento inválido."
  ((${#DUAL_RESIZE_BYTES} <= 18)) || die "Tamanho de redimensionamento fora do limite."
  if (( DUAL_RESIZE_BYTES > 0 )); then
    [[ "$INSTALL_MODE" == "dual" && -n "$DUAL_RESIZE_PARTITION" ]] \
      || die "O redimensionamento NTFS só pode ser usado no modo dual boot."
  elif [[ -n "$DUAL_RESIZE_PARTITION" ]]; then
    die "Partição NTFS selecionada sem tamanho de redimensionamento."
  fi
  FS_TYPE="${FS_TYPE:-ext4}"
  [[ "$FS_TYPE" =~ ^(ext4|btrfs)$ ]] || die "Sistema de arquivos inválido: $FS_TYPE"
  USE_LUKS="${USE_LUKS:-0}"
  [[ "$USE_LUKS" =~ ^(0|1)$ ]] || USE_LUKS=0
  GPU="${GPU:-vm}"
  if [[ "$GPU" == "auto" ]]; then
    GPU="vm"   # "Automático" = drivers genéricos/default (sem módulo específico)
  fi
  [[ "$GPU" =~ ^(intel|amd|nvidia|vm)$ ]] || die "GPU inválida: $GPU"
  if [[ -z "$MICROCODE" ]]; then
    if grep -qi "GenuineIntel" /proc/cpuinfo; then MICROCODE=intel; fi
    if grep -qi "AuthenticAMD" /proc/cpuinfo; then MICROCODE=amd; fi
    MICROCODE="${MICROCODE:-none}"
    info "Microcódigo detectado: $MICROCODE."
  fi
  [[ -n "$ROOT_PASS" ]] || ROOT_PASS="$INSTALL_USER_PASS"
  [[ -n "$INSTALL_USER_PASS" ]] || INSTALL_USER_PASS="$ROOT_PASS"
  [[ -n "$LUKS_PASS" ]] || LUKS_PASS="$ROOT_PASS"
  OFFLINE="${OFFLINE:-1}"
  [[ "$OFFLINE" =~ ^[01]$ ]] || OFFLINE=1
  if [[ -n "$MIRROR" && "$MIRROR" != http* ]]; then
    die "Espelho inválido: $MIRROR (use URL completa, ex.: https://mirror.ufscar.br/archlinux)"
  fi
}

print_summary() {
  info "$(T summary)"
  echo "  $(T sum.disk):      $DISK"
  if [[ "$INSTALL_MODE" == "dual" ]]; then echo "  $(T sum.part):      $(T part.dual)"; else echo "  $(T sum.part):      $(T part.wipe)"; fi
  echo "  $(T sum.fs):        $FS_TYPE"
  if (( USE_LUKS )); then echo "  $(T sum.luks):      $(T sum.yes)"; else echo "  $(T sum.luks):      $(T sum.no)"; fi
  echo "  $(T sum.user):      $INSTALL_USER"
  echo "  $(T sum.hostname):  $HOSTNAME"
  echo "  $(T sum.locale):    $LOCALE"
  echo "  $(T sum.keymap):    $KEYMAP"
  echo "  $(T sum.zone):      $ZONEINFO"
  echo "  $(T sum.mirror):    ${MIRROR:-$(T sum.mirror.auto)}"
  if (( OFFLINE )); then echo "  $(T sum.mode):      $(T sum.mode.offline)"; else echo "  $(T sum.mode):      $(T sum.mode.online)"; fi
  echo "  $(T sum.gpu):       $GPU"
  echo "  $(T sum.microcode): $MICROCODE"
}

read_val() {
  local -n _out=$1
  local _msg=$2
  local _def=$3
  local _v
  read -r -p "$_msg [$_def]: " _v
  _out="${_v:-$_def}"
}

read_secret() {
  local -n _out=$1
  local _msg=$2
  local _confirm
  while :; do
    read -r -s -p "$_msg: " _out; echo
    read -r -s -p "Confirme novamente: " _confirm; echo
    if [[ -z "$_out" ]]; then
      warn "Senha vazia não é permitida."
      continue
    fi
    if [[ "$_out" != "$_confirm" ]]; then
      warn "As senhas não conferem, tente de novo."
      continue
    fi
    break
  done
}

part_path() {
  local d=$1 n=$2
  if [[ $d =~ [0-9]$ ]]; then echo "${d}p${n}"; else echo "${d}${n}"; fi
}

is_prompt_y() {
  local _msg=$1
  local _v
  read -r -p "$_msg (s/N): " _v
  [[ "${_v,,}" == "s" || "${_v,,}" == "y" ]]
}

# ---------------------------------------------------------------------------
# Pré-requisitos
# ---------------------------------------------------------------------------
preflight() {
  (( EUID == 0 )) || die "Execute como root (o ISO do Arch já inicia como root)."
  [[ -d /sys/firmware/efi ]] || die "Este instalador suporta apenas UEFI."
  command -v pacstrap >/dev/null 2>&1 || die "Execute a partir do ISO oficial do Arch Linux (arch-install-scripts)."
  # Checagem de rede rápida e sem DNS (evita travar em ambientes offline).
  if [[ "${OFFLINE:-1}" != "1" ]]; then
    timeout 3 ping -c 1 -W 2 1.1.1.1 >/dev/null 2>&1 \
      || timeout 3 ping -c 1 -W 2 8.8.8.8 >/dev/null 2>&1 \
      || warn "Sem rede aparente; o modo completo (online) pode falhar. Prefira o modo rápido offline."
  else
    info "Modo offline selecionado; rede não é necessária."
  fi
  command -v sgdisk >/dev/null 2>&1 || { info "Instalando gdisk no ambiente live..."; pacman -Sy --noconfirm gdisk >/dev/null 2>&1 || die "Não foi possível instalar o gdisk."; }
  command -v cryptsetup >/dev/null 2>&1 || die "cryptsetup ausente no ambiente live."
  timedatectl set-ntp true >/dev/null 2>&1 || true
}

# ---------------------------------------------------------------------------
# Particionamento
# ---------------------------------------------------------------------------
resize_ntfs_for_dual_boot() {
  (( DUAL_RESIZE_BYTES > 0 )) || return 0
  command -v ntfsresize >/dev/null 2>&1 \
    || die "ntfsresize não está disponível; não foi feita nenhuma alteração."
  [[ -b "$DUAL_RESIZE_PARTITION" ]] \
    || die "A partição NTFS escolhida não está disponível; não foi feita nenhuma alteração."

  local parent part_number fs_type part_size min_size target_fs_bytes
  local start_sector old_sectors new_sectors end_sector root_sectors base
  parent="$(lsblk -ndo PKNAME "$DUAL_RESIZE_PARTITION" 2>/dev/null | head -n1)"
  [[ "$parent" == /dev/* ]] || parent="/dev/$parent"
  [[ -n "$parent" && "$(readlink -f "$parent")" == "$(readlink -f "$DISK")" ]] \
    || die "A partição NTFS escolhida não pertence ao disco selecionado."
  part_number="$(lsblk -ndo PARTN "$DUAL_RESIZE_PARTITION" 2>/dev/null | head -n1)"
  [[ "$part_number" =~ ^[0-9]+$ ]] || die "Não foi possível validar a partição NTFS escolhida."
  fs_type="$(blkid -s TYPE -o value "$DUAL_RESIZE_PARTITION" 2>/dev/null || true)"
  [[ "$fs_type" == "ntfs" ]] || die "A partição selecionada não contém NTFS."
  if lsblk -nrpo MOUNTPOINTS "$DUAL_RESIZE_PARTITION" | grep -q '[^[:space:]]'; then
    die "Desmonte a partição NTFS antes de redimensioná-la."
  fi

  part_size="$(blockdev --getsize64 "$DUAL_RESIZE_PARTITION")"
  local info_output
  info_output="$(LC_ALL=C ntfsresize --info --no-progress-bar "$DUAL_RESIZE_PARTITION" 2>&1)" \
    || die "O NTFS não passou na verificação de segurança. Execute chkdsk no Windows e tente novamente: $info_output"
  min_size="$(printf '%s\n' "$info_output" | sed -nE 's/.*You might resize at ([0-9,]+) bytes.*/\1/p' | tr -d ',' | head -n1)"
  [[ "$min_size" =~ ^[0-9]+$ ]] || die "Não foi possível determinar o menor tamanho NTFS seguro."
  (( DUAL_RESIZE_BYTES > 0 && DUAL_RESIZE_BYTES <= part_size )) \
    || die "O tamanho selecionado para liberar espaço é inválido."
  target_fs_bytes=$((part_size - DUAL_RESIZE_BYTES))
  (( target_fs_bytes >= min_size + 1024**3 )) \
    || die "O tamanho deixaria o Windows abaixo do mínimo seguro informado pelo NTFS."
  (( DUAL_RESIZE_BYTES > 2 * 1024**3 && DUAL_RESIZE_BYTES % 512 == 0 )) \
    || die "O espaço escolhido para a partição NLinux é insuficiente ou inválido."

  base="${DUAL_RESIZE_PARTITION##*/}"
  [[ -r "/sys/class/block/$base/start" && -r "/sys/class/block/$base/size" ]] \
    || die "Não foi possível ler os limites da partição NTFS."
  start_sector="$(<"/sys/class/block/$base/start")"
  old_sectors="$(<"/sys/class/block/$base/size")"
  new_sectors=$(((target_fs_bytes + 1024**2 + 511) / 512))
  root_sectors=$(((DUAL_RESIZE_BYTES - 2 * 1024**2) / 512))
  (( new_sectors < old_sectors && root_sectors > 5 * 1024**3 / 512 )) \
    || die "Os tamanhos escolhidos não deixam espaço contínuo suficiente para o NLinux."
  info "Testando o redimensionamento NTFS sem alterar a partição."
  if ! ntfsresize --no-action --size "$target_fs_bytes" --no-progress-bar "$DUAL_RESIZE_PARTITION"; then
    die "O NTFS não passou no teste de redimensionamento. Execute chkdsk no Windows; nenhuma alteração foi feita."
  fi
  info "Reduzindo o sistema de arquivos NTFS em $DUAL_RESIZE_PARTITION; os dados existentes serão preservados."
  if ! ntfsresize --size "$target_fs_bytes" --force "$DUAL_RESIZE_PARTITION"; then
    die "O redimensionamento NTFS falhou. A tabela de partições não foi alterada."
  fi

  end_sector=$((start_sector + new_sectors - 1))
  if (( new_sectors >= old_sectors )) || ! parted -s "$DISK" unit s resizepart "$part_number" "${end_sector}s"; then
    die "O sistema de arquivos NTFS foi reduzido, mas a partição não pôde ser ajustada. O Windows continua dentro da partição original."
  fi
  DUAL_ROOT_START_SECTOR=$((end_sector + 1))
  DUAL_ROOT_END_SECTOR=$((DUAL_ROOT_START_SECTOR + root_sectors - 1))
  partprobe "$DISK" >/dev/null 2>&1 || true
  udevadm settle 2>/dev/null || true
  info "Partição NTFS ajustada com segurança. Espaço livre criado para o NLinux."
}

partition_disk() {
  local p_efi p_root
  p_efi="$(part_path "$DISK" 1)"
  p_root="$(part_path "$DISK" 2)"

  # O ambiente live pode ter auto-montado o disco-alvo (udisks), deixando a
  # tabela de partição ocupada: sempartprobe não consegue reler e o mount
  # seguinte falha com "superbloco inválido". Desmonta antes.
  info "Desmontando partições auto-montadas de $DISK (se houver)"
  while read -r mp; do
    [[ -n "$mp" ]] && umount "$mp" 2>/dev/null || true
  done < <(lsblk -lnlo MOUNTPOINT "$DISK" 2>/dev/null | grep -v '^$')
  udevadm settle 2>/dev/null || true

  if [[ "$INSTALL_MODE" == "dual" ]]; then
    # -------------------------------------------------------------------
    # DUAL BOOT: preserva o sistema existente (ex.: Windows). Reutiliza a
    # ESP (partição EFI System FAT32) que já existe e cria a raiz NLinux no
    # MAIOR espaço livre contínuo do disco, exceto quando a interface pediu
    # explicitamente a criação do root no espaço liberado do NTFS.
    # -------------------------------------------------------------------
    info "Modo dual boot: procurando partição EFI (ESP) existente em $DISK"
    resize_ntfs_for_dual_boot
    p_efi="$(lsblk -lnpo NAME,PARTTYPE "$DISK" 2>/dev/null | awk '$2 == "c12a7328-f81f-11d2-ba4b-00a0c93ec93b" {print $1}' | head -n1)"
    if [[ -z "$p_efi" || ! -b "$p_efi" ]]; then
      die "Dual boot: não encontrei partição EFI (ESP) em $DISK. Escolha o modo 'wipe' ou um disco com Windows/ESP."
    fi
    [[ "$(blkid -s TYPE -o value "$p_efi" 2>/dev/null)" == "vfat" ]] \
      || die "Dual boot: a partição EFI $p_efi não é FAT32. Não é seguro instalar ao lado."

    info "Reutilizando ESP existente $p_efi (não será formatada)"
    note "stage.dual.esp"

    local free_num=1
    while (( free_num <= 128 )) && lsblk -nrno PARTN "$DISK" | grep -Fxq "$free_num"; do
      free_num=$((free_num + 1))
    done
    (( free_num <= 128 )) || die "Dual boot: não há número de partição GPT disponível em $DISK."
    info "Criando partição raiz NLinux em $DISK"
    if (( DUAL_RESIZE_BYTES > 0 )); then
      if ! sgdisk --new="$free_num:$DUAL_ROOT_START_SECTOR:$DUAL_ROOT_END_SECTOR" \
        --typecode="$free_num:8304" --change-name="$free_num:NLinux" "$DISK" >/dev/null 2>&1; then
        die "Não foi possível criar a partição NLinux no espaço NTFS liberado."
      fi
    elif ! sgdisk --largest-new="$free_num" --typecode="$free_num:8304" --change-name="$free_num:NLinux" "$DISK" >/dev/null 2>&1; then
      die "Dual boot: sem espaço livre suficiente em $DISK para a raiz NLinux."
    fi
    p_root="$(part_path "$DISK" "$free_num")"
    note "stage.dual.create"
    partprobe "$DISK" >/dev/null 2>&1 || true
    udevadm trigger --subsystem-match=block 2>/dev/null || true
    udevadm settle 2>/dev/null || true
    sleep 1

    local i
    for i in 1 2 3 4 5 6 7 8 9 10; do
      if [[ -b "$p_root" ]]; then
        break
      fi
      udevadm settle 2>/dev/null || true
      sleep 1
    done
    [[ -b "$p_root" ]] || die "Kernel não reconheceu a partição nova $p_root (dmesg?)."

    echo "$p_efi" > "$INSTALL_BASE/.part_efi"
    echo "$p_root" > "$INSTALL_BASE/.part_root"
    return 0
  fi

  info "Apagando tabela de partições de $DISK"
  sgdisk --zap-all "$DISK" >/dev/null || die "Não foi possível apagar a tabela de $DISK (partição em uso?)."
  sgdisk -o "$DISK" >/dev/null
  partprobe "$DISK" >/dev/null 2>&1 || true
  udevadm settle 2>/dev/null || true
  sleep 1

  info "Criando partição EFI (1G) e raiz (restante)"
  sgdisk --new=1:0:+1G --typecode=1:ef00 --change-name=1:EFI "$DISK" >/dev/null
  if (( USE_LUKS )); then
    sgdisk --new=2:0:0 --typecode=2:8309 --change-name=2:NLinux "$DISK" >/dev/null
  else
    sgdisk --new=2:0:0 --typecode=2:8304 --change-name=2:NLinux "$DISK" >/dev/null
  fi
  partprobe "$DISK" >/dev/null 2>&1 || true
  udevadm trigger --subsystem-match=block 2>/dev/null || true
  udevadm settle 2>/dev/null || true
  sleep 1

  # Garante que o kernel enxergou as partições novas antes de formatar.
  local base="${DISK##*/}"
  local i
  for i in 1 2 3 4 5 6 7 8 9 10; do
    if [[ -b "/dev/${base}1" && -b "/dev/${base}2" ]]; then
      break
    fi
    udevadm settle 2>/dev/null || true
    sleep 1
  done
  [[ -b "$p_efi" && -b "$p_root" ]] || die "Kernel não reconheceu as partições de $DISK (dmesg?)."

  echo "$p_efi" > "$INSTALL_BASE/.part_efi"
  echo "$p_root" > "$INSTALL_BASE/.part_root"
}

setup_filesystem() {
  local p_efi p_root
  p_efi="$(cat "$INSTALL_BASE/.part_efi")"
  p_root="$(cat "$INSTALL_BASE/.part_root")"

  local root_dev="$p_root"
  if (( USE_LUKS )); then
    info "Formatando LUKS2 em $p_root"
    echo -n "$LUKS_PASS" | cryptsetup -q luksFormat --type luks2 --key-file=- "$p_root"
    echo -n "$LUKS_PASS" | cryptsetup -q open --key-file=- "$p_root" cryptroot
    root_dev="/dev/mapper/cryptroot"
  fi

if [[ "$FS_TYPE" == "btrfs" ]]; then
    info "Formatando btrfs em $root_dev"
    mkfs.btrfs -f -L NLinux "$root_dev" >/dev/null
    sync
    udevadm settle 2>/dev/null || true
    blkid -s UUID -o value "$root_dev" >/dev/null 2>&1 \
      || die "mkfs.btrfs não produziu superbloco legível em $root_dev — kernel ainda vê a tabela antiga?"
    mount "$root_dev" "$MNT"
    info "Criando subvolumes @, @home, @log, @pkg"
    btrfs subvolume create "$MNT/@"
    btrfs subvolume create "$MNT/@home"
    btrfs subvolume create "$MNT/@log"
    btrfs subvolume create "$MNT/@pkg"
    umount "$MNT"
    mount -o subvol=@ "$root_dev" "$MNT"
    mkdir -p "$MNT/home" "$MNT/var/log" "$MNT/var/cache/pacman/pkg"
    mount -o subvol=@home "$root_dev" "$MNT/home"
    mount -o subvol=@log "$root_dev" "$MNT/var/log"
    mount -o subvol=@pkg "$root_dev" "$MNT/var/cache/pacman/pkg"
  else
    info "Formatando ext4 em $root_dev"
    mkfs.ext4 -F -L NLinux "$root_dev" >/dev/null
    sync
    udevadm settle 2>/dev/null || true
    blkid -s UUID -o value "$root_dev" >/dev/null 2>&1 \
      || die "mkfs.ext4 não produziu superbloco legível em $root_dev — kernel ainda vê a tabela antiga?"
    mount "$root_dev" "$MNT"
  fi

  if [[ "$INSTALL_MODE" == "dual" ]]; then
    # ESP preservada (Windows continua intacto): só valida e monta.
    info "Montando ESP existente $p_efi em /boot (dual boot)"
  else
    info "Formatando partição EFI (FAT32)"
    mkfs.fat -F32 -n EFI "$p_efi" >/dev/null
    sync
    udevadm settle 2>/dev/null || true
  fi
  blkid -s UUID -o value "$p_efi" >/dev/null 2>&1 \
    || die "Não foi possível ler a partição EFI $p_efi (formato inesperado?)."
  mkdir -p "$MNT/boot"
  mount "$p_efi" "$MNT/boot"
}

# ---------------------------------------------------------------------------
# pacstrap + instalação em chroot
# ---------------------------------------------------------------------------
# Cópia offline via rsync. A raiz de um live é "viva" (arquivos mudam/somem
# enquanto copia) e pontos montados (ESP FAT, etc.) geram avisos de atributos;
# rc 23/24 são normais nesse cenário. Por isso o rsync NÃO pode rodar no set -e
# cego: capturamos o rc, retomamos em caso de interrupção e só abortamos em
# erros fatais (sem espaço, I/O, permissão, read-only). O log fica em
# /tmp/offline-rsync.log e é copiado para /var/log no sistema instalado.
offline_clone() {
  if ! command -v rsync >/dev/null 2>&1; then
    info "Instalando rsync no ambiente live..."
    pacman -Sy --noconfirm rsync >/dev/null 2>&1 || die "Não foi possível instalar o rsync."
  fi

  local log="/tmp/offline-rsync.log"
  local rc="" attempt=1
  local max_attempts=4
  local extra=()

  info "Modo RÁPIDO offline: copiando o sistema do pendrive para o disco (sem internet)..."
  # Diretórios que o live continua gravando DURANTE a cópia. Se não forem
  # excluídos, o rsync fica num ciclo de re-transferência do último arquivo em
  # fluxo e congela nos 99% (sintoma: log parado em to-chk=0). São tudo estado
  # de execução que o sistema instalado regenera sozinho no primeiro boot.
  local excludes=(
    --exclude='/proc' --exclude='/sys' --exclude='/dev' --exclude='/run'
    --exclude='/tmp' --exclude='/mnt' --exclude='/bootmnt'
    --exclude='/home'
    --exclude='/var/cache/pacman/pkg'
    --exclude='/var/log/journal'
    --exclude='/var/cache/app-info'
    --exclude='/var/lib/bluetooth' --exclude='/var/lib/NetworkManager'
    --exclude='/var/lib/systemd' --exclude='/var/lib/dhcpcd'
    --exclude='/root/.cache'
    --exclude='/etc/fstab' --exclude='/etc/machine-id'
    --exclude='/root/.bash_profile' --exclude='/root/.zprofile'
  )

  while :; do
    rm -f "$log"; umask 022
    { echo "# NLinux - cópia offline em $(date -Is)  rsync $(rsync --version 2>/dev/null | awk 'NR==1{print $3}')"; echo "# Fonte: /  Alvo: $MNT"; echo; } >> "$log"
    extra=()
    (( attempt > 1 )) && extra+=(--partial)   # retoma os arquivos já copiados

    # --no-inc-recursive: evita o "generator hang" do rsync (varredura
    # incremental + árvore do live mudando em tempo real). --timeout=60
    # transforma um I/O travado em erro limpo (rc 30) em vez de bloqueio
    # eterno. `timeout` é o watchdog final: mata um rsync congelado (rc 124)
    # e o laço abaixo retoma de onde parou.
    set +e   # pipestatus tem prioridade aqui; sem -e/pipefail ativos agora
    timeout --foreground --kill-after=15 2400 \
    rsync -aHAXx --numeric-ids --info=progress2 --no-inc-recursive --timeout=60 \
      "${extra[@]}" "${excludes[@]}" \
      / "$MNT"/ 2>&1 | tee "$log"
    rc=${PIPESTATUS[0]}
    set -e

    if (( rc == 0 )); then
      break
    fi

    if (( rc == 24 )); then
      # Arquivos que "sumiram" enquanto o live copia (pacman/locks/logs).
      warn "rsync: arquivos mudaram/sumiram durante a cópia (normal no live). Prosseguindo."
      break
    fi

    # Trava no final da cópia (timeout matou o rsync: 124/137): retoma com
    # --partial — os arquivos já copiados são preservados. Esgotadas as
    # tentativas no MESMO ponto, o sistema estaria incompleto: aborta.
    if (( rc == 124 || rc == 137 )); then
      if (( attempt >= max_attempts )); then
        cp -f "$log" "$MNT/var/log/offline-rsync.log" 2>/dev/null || true
        die "O rsync travou repetidamente ao final da cópia (rc=$rc). Sistema ficaria incompleto; abortado.\n  Log: /tmp/offline-rsync.log\n  Disco-alvo: $MNT/var/log/offline-rsync.log\n\nÚltimas linhas:\n$(tail -n 15 "$log")"
      fi
      warn "rsync travou ao final da cópia (rc=$rc); retomando de onde parou (tentativa $attempt de $max_attempts)..."
      attempt=$((attempt + 1))
      continue
    fi

    # Interrupção/estouro de protocolo: retoma do ponto onde parou.
    if (( attempt < max_attempts )) && [[ "$rc" =~ ^(10|11|12|13|30)$ ]]; then
      warn "rsync interrompido (rc=$rc); tentando retomar de onde parou (tentativa $attempt de $max_attempts)..."
      attempt=$((attempt + 1))
      continue
    fi

    if grep -qiE 'No space left on device|Read-only file system|Permission denied|Input/output error|mkstemp failed|Invalid argument|File name too long' "$log"; then
      # Salva o log no próprio disco-alvo para diagnóstico após o reboot.
      cp -f "$log" "$MNT/var/log/offline-rsync.log" 2>/dev/null || true
      die "Falha ao copiar o sistema para o disco ($rc). O erro exato está gravado no log:\n  no pendrive/live: /tmp/offline-rsync.log\n  no disco-alvo:    $MNT/var/log/offline-rsync.log\n\nÚltimas linhas:\n$(tail -n 15 "$log")"
    fi

    # Demais casos (atributos/times/xattr em FAT, casos sem padrão fatal): avisa.
    warn "rsync reportou avisos não fatais (rc=$rc); continuando a instalação. Log: /tmp/offline-rsync.log"
    break
  done

  cp -f "$log" "$MNT/var/log/offline-rsync.log" 2>/dev/null || true

  info "Removendo resíduos específicos do live (archiso, autologin, auto-run, usuário nlinux)"
  # /etc/mkinitcpio.conf.d/archiso.conf injeta hooks archiso_loop_mnt/archiso_pxe_*
  # no initramfs instalado (referem /run/archiso, inexistente). Sem ele o
  # mkinitcpio -P do chroot (10-system.sh) gera um initramfs limpo.
  rm -f "$MNT/etc/mkinitcpio.conf.d/archiso.conf"
  rm -rf "$MNT/var/lib/archiso" 2>/dev/null || true
  rm -rf "$MNT/etc/systemd/system/getty@tty1.service.d" 2>/dev/null || true
  rm -f "$MNT/root/.bash_profile" "$MNT/root/.zprofile" 2>/dev/null || true
  sed -i '/^nlinux:/d' "$MNT/etc/passwd" "$MNT/etc/shadow" 2>/dev/null || true
  sed -i '/^nlinux:/d' "$MNT/etc/group" "$MNT/etc/gshadow" 2>/dev/null || true
  rm -f "$MNT/etc/sudoers.d/10-nlinux-user" 2>/dev/null || true
  : > "$MNT/etc/machine-id"
  ok "Sistema copiado para o disco."
}

stage_packages() {
  local pkgs
  pkgs="$(grep -hvE '^\s*(#|$)' "$PACKAGES_DIR/base.packages" "$PACKAGES_DIR/desktop.packages" | awk '{print $NF}')"

  case "$GPU" in
    intel) pkgs="$pkgs mesa vulkan-intel intel-media-driver intel-gpu-tools" ;;
    amd)   pkgs="$pkgs mesa vulkan-radeon libva-mesa-driver radeontop" ;;
    nvidia) pkgs="$pkgs nvidia nvidia-utils" ;;
    vm)    pkgs="$pkgs mesa" ;;
  esac

  case "$MICROCODE" in
    intel) pkgs="$pkgs intel-ucode" ;;
    amd)   pkgs="$pkgs amd-ucode" ;;
  esac

  # Não passa --noconfirm: o getopts do pacstrap (`':C:cDGiKMNPU'`) aborta em
  # opção desconhecida. Sem -i ele já acrescenta --noconfirm sozinho.
  info "Instalando sistema base e pacotes (pacstrap), isso pode demorar..."
  # O pacstrap baixa centenas de MB e falha por motivo de rede com frequência
  # (espelho lento, DNS, 502). Como o pacman reaproveita o cache já baixado,
  # repetir a tentativa é barato — e abortar na primeira falha joga fora a
  # partição já formatada. Até 3 tentativas antes de desistir.
  local attempt=1 max_attempts=3 rc=0
  while (( attempt <= max_attempts )); do
    set +e
    pacstrap -K "$MNT" $pkgs
    rc=$?
    set -e
    if (( rc == 0 )); then
      break
    fi
    if (( attempt < max_attempts )); then
      warn "pacstrap falhou (rc=$rc); repetindo em 15s (tentativa $((attempt + 1)) de $max_attempts)..."
      sleep 15
      attempt=$((attempt + 1))
      continue
    fi
    die "O pacstrap falhou $max_attempts vezes (rc=$rc).\n  Verifique a conexão e o espelho escolhido em /etc/pacman.d/mirrorlist e rode a instalação novamente."
  done
}

# ---------------------------------------------------------------------------
# Aplicar escolhas do menu no ambiente live (locale/keymap) e no mirror
# ---------------------------------------------------------------------------
apply_live_options() {
  [[ -n "$LOCALE" ]] || return 0
  info "Aplicando idioma no ambiente live: $LOCALE"
  if grep -q "^#$LOCALE UTF-8" /etc/locale.gen; then
    sed -i "s|^#$LOCALE UTF-8|$LOCALE UTF-8|" /etc/locale.gen
  elif ! grep -q "^$LOCALE UTF-8" /etc/locale.gen; then
    echo "$LOCALE UTF-8" >> /etc/locale.gen
  fi
  locale-gen >/dev/null 2>&1 || true
  echo "LANG=$LOCALE" > /etc/locale.conf
  umask 022
  mkdir -p /etc/profile.d
  echo "export LANG=$LOCALE" > /etc/profile.d/nlinux-lang.sh
  export LANG="$LOCALE"

  if [[ -n "$KEYMAP" ]]; then
    info "Aplicando layout de teclado no live: $KEYMAP"
    echo "KEYMAP=$KEYMAP" > /etc/vconsole.conf
    loadkeys "$KEYMAP" >/dev/null 2>&1 || true
  fi
}

apply_mirror() {
  local mlist=/etc/pacman.d/mirrorlist
  if [[ -n "$MIRROR" ]]; then
    info "Definindo espelho de repositórios: $MIRROR"
    {
      echo "# NLinux - espelho escolhido no instalador"
      echo "Server = $MIRROR/\$repo/os/\$arch"
      cat "$mlist"
    } > "${mlist}.tmp" && mv "${mlist}.tmp" "$mlist"
  fi
  if ! grep -q '^[[:space:]]*\[options\][[:space:]]*$' /etc/pacman.conf; then
    die "A seção [options] não foi encontrada em /etc/pacman.conf."
  fi
  sed -i \
    -e '/^[[:space:]]*DisableDownloadTimeout[[:space:]]*$/d' \
    -e '/^[[:space:]]*\[options\][[:space:]]*$/a DisableDownloadTimeout' \
    /etc/pacman.conf
  info "Desabilitando timeout de baixa velocidade do pacman (evita 'Operation too slow')."
}

run_chroot_setup() {
  info "Copiando scripts de instalação para dentro do sistema"
  mkdir -p "$MNT$SHARE_DIR"
  cp -a "$CHROOT_DIR" "$MNT$SHARE_DIR/"
  cp -a "$CONFIG_DIR" "$MNT$SHARE_DIR/"
  cp -a "$PACKAGES_DIR" "$MNT$SHARE_DIR/"
  chmod -R +x "$MNT$SHARE_DIR/chroot"

  genfstab -U "$MNT" > "$MNT/etc/fstab"
  # O rsync copiou /etc/resolv.conf do live (que é um symlink para
  # /run/systemd/...). Preservar esse symlink deixa o sistema instalado sem DNS
  # quando systemd-resolved não está ativo. Prefere os servidores upstream do
  # resolved; o NetworkManager passa a manter o arquivo regular após o primeiro boot.
  rm -f "$MNT/etc/resolv.conf"
  local resolver_source="" candidate
  for candidate in /run/systemd/resolve/resolv.conf /etc/resolv.conf; do
    if [[ -r "$candidate" ]] &&
      grep -qE '^[[:space:]]*nameserver[[:space:]]+' "$candidate" &&
      ! grep -qE '^[[:space:]]*nameserver[[:space:]]+(127\.|::1([[:space:]]|$))' "$candidate"; then
      resolver_source="$candidate"
      break
    fi
  done
  if [[ -n "$resolver_source" ]]; then
    cp -L "$resolver_source" "$MNT/etc/resolv.conf"
  else
    printf '# NLinux: o NetworkManager configurará o DNS após a primeira conexão.\n' \
      > "$MNT/etc/resolv.conf"
  fi
  chmod 0644 "$MNT/etc/resolv.conf"
  # Chroot herda espelho + pacman.conf escolhidos no ambiente live.
  [[ -f /etc/pacman.d/mirrorlist ]] && cp /etc/pacman.d/mirrorlist "$MNT/etc/pacman.d/mirrorlist"
  cp -a /etc/pacman.conf "$MNT/etc/pacman.conf"

  info "Executando configuração dentro do chroot"
  # O rsync exclui /proc,/sys,/dev,/run,/tmp — o sistema copiado não tem esses
  # diretórios. O arch-chroot vivo (arch-install-scripts 31+) NÃO os cria mais
  # (monta direto nos pontos); sem eles ele falha na primeira montagem com
  # "mount: $MNT/proc: o ponto de montagem não existe.". Cria antes:
  install -d "$MNT"/proc "$MNT"/sys "$MNT"/dev "$MNT"/run "$MNT"/tmp \
    "$MNT"/dev/pts "$MNT"/dev/shm
  local luks_uuid=""
  if (( USE_LUKS )); then
    luks_uuid="$(cryptsetup luksUUID "$(cat "$INSTALL_BASE/.part_root")")"
  fi

  arch-chroot "$MNT" env \
    INSTALL_USER="$INSTALL_USER" \
    INSTALL_USER_PASS="$INSTALL_USER_PASS" \
    ROOT_PASS="$ROOT_PASS" \
    HOSTNAME="$HOSTNAME" \
    LOCALE="$LOCALE" \
    KEYMAP="$KEYMAP" \
    ZONEINFO="$ZONEINFO" \
    FS_TYPE="$FS_TYPE" \
    USE_LUKS="$USE_LUKS" \
    LUKS_UUID="${luks_uuid:-}" \
    GPU="$GPU" \
    MICROCODE="${MICROCODE:-none}" \
    OFFLINE="$OFFLINE" \
    SHARE_DIR="$SHARE_DIR" \
    GUI_DRIVEN="$GUI_DRIVEN" \
    /bin/bash "$SHARE_DIR/chroot/all.sh"
}

# ---------------------------------------------------------------------------
# Loja de software (nlinux-software): copia o app + atalho + ícone para o
# sistema instalado. No offline o rsync do live já traz /opt/nlinux-software;
# aqui garante o arquivo igual no modo online (pacstrap) e os demais arquivos
# de integração (menu, ícone, wrapper) nos dois modos.
# ---------------------------------------------------------------------------
stage_software_store() {
  [[ -d /opt/nlinux-software ]] || { warn "Loja de software ausente no live; ignorando."; return 0; }
  info "Incluindo a loja de software nlinux-software no sistema instalado"
  if [[ ! -e "$MNT/opt/nlinux-software/nlinux-software" ]]; then
    cp -a /opt/nlinux-software "$MNT/opt/nlinux-software"
  fi
  rm -rf "$MNT/opt/nlinux-software/src/nlinux/__pycache__" 2>/dev/null || true
  if [[ -f /usr/share/applications/nlinuxstore.desktop ]]; then
    install -Dm644 /usr/share/applications/nlinuxstore.desktop \
      "$MNT/usr/share/applications/nlinuxstore.desktop"
  fi
  install -Dm755 /usr/local/bin/nlinux-software "$MNT/usr/local/bin/nlinux-software"
  chmod 0755 "$MNT/opt/nlinux-software/nlinux-software" 2>/dev/null || true
  if [[ -f /usr/share/pixmaps/nlinux-software.png ]]; then
    install -Dm644 /usr/share/pixmaps/nlinux-software.png \
      "$MNT/usr/share/pixmaps/nlinux-software.png"
  fi
}

# Despeja a NVRAM no log. Sem isso não há como descobrir, depois do reboot,
# por que a entrada não ficou com o rótulo NLinux — o efibootmgr só fala o
# erro no stderr, e stderr sumia em /dev/null.
_efivars_dump() {
  local quando="$1" saida
  command -v efibootmgr >/dev/null 2>&1 || return 0
  saida="$(efibootmgr -v 2>&1)"
  info "NVRAM $quando:"
  while IFS= read -r linha; do
    [[ -n "$linha" ]] && info "  | $linha"
  done <<< "$saida"
}

# Números (em hexadecimal, sem o "Boot") de todas as entradas de boot.
_efiboot_numeros() {
  efibootmgr -v 2>/dev/null | awk '/^Boot[0-9A-Fa-f]/ {
    n = $1; sub(/^Boot/, "", n); sub(/\*$/, "", n); print n }'
}

# Lista as entradas em três colunas: número, rótulo e device path.
#
# O separador entre o rótulo e o device path é um TAB, não dois espaços —
# show_var_path() no fonte do efibootmgr faz printf("\t%s", ...). Por isso as
# colunas não podem ser separadas com '[[:space:]][[:space:]]+', que nunca casa
# e acaba engolindo o device path dentro do rótulo.
_efiboot_listar() {
  efibootmgr -v 2>/dev/null | awk '
    /^Boot[0-9A-Fa-f]/ {
      n = $1; sub(/^Boot/, "", n); sub(/\*$/, "", n);
      r = substr($0, length($1) + 1)
      sub(/^[ \t]+/, "", r)
      i = index(r, "\t")
      if (i) print n "\t" substr(r, 1, i - 1) "\t" substr(r, i + 1)
      else   print n "\t" r "\t"
    }'
}

# Rótulo de uma entrada, lido direto do efibootmgr. show_vars() imprime
# "Boot0060" + um marcador de ativa/inativa + um espaço, e só depois o rótulo.
_efiboot_rotulo() {
  efibootmgr -v 2>/dev/null | awk -v alvo="Boot$1" '
    index($0, alvo) == 1 {
      r = substr($0, length(alvo) + 1); sub(/^[* \t]+/, "", r)
      i = index(r, "\t"); print (i ? substr(r, 1, i - 1) : r); exit
    }'
}

# Reescreve o rótulo de uma entrada de boot que JÁ EXISTE.
#
# Nada aqui usa o efibootmgr para renomear porque ele não sabe: o -L/--label
# só é lido por --create e por --delete, então o `efibootmgr -b 0001 -L "NLinux"`
# que circula em wiki é um no-op nesta versão (e no main do upstream também).
#
# E também não vale criar uma entrada nova com --create: ele grava uma variável
# que ainda não existe, e o kernel do live exige EFI_VARIABLE_APPEND_WRITE
# nesse caso — flag que só o systemd passa, por meio do retry de
# efi_set_variable_platform(). Daí o bootctl conseguir criar a entrada e o
# efibootmgr falhar com ENOENT ("Could not prepare Boot variable"). Reescrever
# uma variável que já existe não passa por esse caminho.
#
# O rótulo é localizado procurando a string antiga em UTF-16LE dentro do
# arquivo, e não por offset: em parte dos kernels o efivarfs prefixa o
# EFI_LOAD_OPTION com 4 bytes de atributos, então a posição do rótulo muda
# conforme o kernel.
_efiboot_renomear() {
  local num="$1" novo="$2"
  local efivars="${EFIVARS:-/sys/firmware/efi/efivars}"
  local guid=8be4df61-93ca-11d2-aa0d-00e098032b8c          # EFI_GLOBAL_GUID
  local var="$efivars/Boot${num}-${guid}"
  local antigo off tam work lido

  if [[ ! -r $var ]]; then
    warn "a entrada Boot$num não existe em $efivars; nada foi alterado"
    return 1
  fi

  antigo="$(_efiboot_rotulo "$num")"
  if [[ -z "$antigo" ]]; then
    warn "não consegui ler o rótulo de Boot$num; nada foi alterado"
    return 1
  fi
  if [[ "$antigo" == "$novo" ]]; then
    info "Boot$num já se chama '$novo'"
    return 0
  fi

  work="$(mktemp -d)"
  printf '%s' "$antigo" | iconv -f UTF-8 -t UTF-16LE > "$work/antigo.bin"
  off="$(grep -aobFf "$work/antigo.bin" "$var" 2>/dev/null | head -n1 | cut -d: -f1)"
  if [[ -z "$off" ]]; then
    warn "o rótulo '$antigo' não apareceu nos bytes de $var; nada foi alterado"
    rm -rf "$work"
    return 1
  fi
  tam="$(stat -c%s "$work/antigo.bin")"

  {
    head -c "$off" "$var"
    printf '%s' "$novo" | iconv -f UTF-8 -t UTF-16LE
    printf '\0\0'
    tail -c "+$(( off + tam + 2 + 1 ))" "$var"
  } > "$work/novo.bin"

  if ! cat "$work/novo.bin" > "$var"; then
    warn "a gravação de Boot$num falhou; o conteúdo antigo foi preservado"
    rm -rf "$work"
    return 1
  fi
  rm -rf "$work"

  lido="$(_efiboot_rotulo "$num")"
  if [[ "$lido" == "$novo" ]]; then
    ok "Boot$num renomeada de '$antigo' para '$novo' ($tam bytes de rótulo antigo)"
    return 0
  fi
  warn "Boot$num deveria se chamar '$novo' e está como '${lido:-vazio}'"
  return 1
}

# Entradas que apontam para o systemd-boot desta ESP. É o que separa a entrada
# do NLinux das entradas de outras distribuições — e das sobras de instalações
# antigas do próprio NLinux, que precisam sair.
_efiboot_esta_esp() {
  local guid="$1"
  _efiboot_listar | awk -F'\t' -v guid="$guid" '
    { d = tolower($3) }
    guid != "" && index(d, tolower(guid)) && d ~ /systemd-boot/ { print $1 "\t" $2 }'
}

# ---------------------------------------------------------------------------
# Boot UEFI: instala o systemd-boot, garante o fallback /EFI/BOOT e deixa
# exatamente UMA entrada systemd-boot na ESP do NLinux, com o rótulo "NLinux".
#
# O `bootctl install` já cria a entrada, e ele cria com o rótulo fixo
# "Linux Boot Manager". Como o efibootmgr não sabe renomear e o --create dele
# falha neste kernel (ver _efiboot_renomear), o caminho é deixar o bootctl criar
# e reescrever só o rótulo da variável que ele gravou.
#
# Instalações antigas do próprio NLinux deixam entradas a mais na mesma ESP,
# então as outras são removidas. Só nesta ESP: entrada de outra distribuição é
# problema dela, e a do Windows nunca aparece aqui porque não é systemd-boot.
# ---------------------------------------------------------------------------
register_uefi() {
  info "Instalando systemd-boot na ESP e registrando 'NLinux' na lista UEFI"

  # Entradas que já existiam antes do bootctl. Serve para o log e, quando o
  # bootctl cria algo novo em vez de reaproveitar, para saber qual é.
  local antes=""
  if command -v efibootmgr >/dev/null 2>&1; then
    antes="$(_efiboot_numeros)"
    _efivars_dump "antes do bootctl install"
  fi

  bootctl --esp-path="$MNT/boot" install >/dev/null 2>&1 || true

  mkdir -p "$MNT/boot/EFI/BOOT"
  cp -f "$MNT/boot/EFI/systemd/systemd-bootx64.efi" "$MNT/boot/EFI/BOOT/BOOTX64.EFI" 2>/dev/null || true

  if ! command -v efibootmgr >/dev/null 2>&1; then
    warn "efibootmgr ausente; a firmware mostrará 'Linux Boot Manager' (entrada do bootctl)."
    return 0
  fi

  # A NVRAM não guarda o disco e a partição, e sim o PARTUUID da ESP. É por ele
  # que a entrada do NLinux é distinguida das entradas de outras distribuições.
  local efi_part esp_guid
  efi_part="$(cat "$INSTALL_BASE/.part_efi")"
  esp_guid="$(lsblk -no PARTUUID "$efi_part" 2>/dev/null | head -n1 | tr 'A-Z' 'a-z')"
  if [[ -z "$esp_guid" ]]; then
    warn "Não consegui o PARTUUID da ESP ($efi_part); a firmware mostrará 'Linux Boot Manager'."
    return 0
  fi

  local nesta_esp total meu
  nesta_esp="$(_efiboot_esta_esp "$esp_guid")"
  total="$(printf '%s\n' "$nesta_esp" | grep -c . || true)"
  info "Entradas systemd-boot nesta ESP ($esp_guid): $total"
  if [[ -n "$nesta_esp" ]]; then
    local n r
    while IFS=$'\t' read -r n r; do
      info "  | Boot$n — ${r:-(sem rótulo)}"
    done <<< "$nesta_esp"
  fi

  if [[ "$total" -eq 0 ]]; then
    warn "Nenhuma entrada systemd-boot na ESP; a firmware vai mostrar 'UEFI: <disco>'."
    warn "A NVRAM completa está no log: /var/log/nlinux-install.log no sistema instalado."
    return 0
  fi

  # Qual é a nossa? O 10-system.sh já rodou `bootctl install` dentro do chroot,
  # então normalmente a entrada já existe e é reaproveitada — nesse caso o diff
  # com "antes" vem vazio e sobra escolher entre as candidatas. O bootctl
  # reutiliza uma entrada compatível quando encontra, então em ESP limpa é uma
  # só; havendo mais de uma, a mais alta é a criação mais recente.
  local novos
  novos="$(printf '%s\n' "$nesta_esp" | cut -f1 \
    | { grep -Fxv -f <(printf '%s\n' "$antes") || true; })"
  if [[ -n "$novos" ]]; then
    meu="$(printf '%s\n' "$novos" | sort | tail -n1)"
  else
    meu="$(printf '%s\n' "$nesta_esp" | cut -f1 | sort | tail -n1)"
  fi
  if [[ "$total" -gt 1 ]]; then
    info "Usando a Boot$meu e removendo as outras $(( total - 1 )) desta ESP."
  fi

  # Falha aqui não é motivo para apagar nada: a entrada do bootctl continua
  # funcionando, e é melhor "Linux Boot Manager" do que deixar a máquina sem
  # entrada além do fallback /EFI/BOOT.
  _efiboot_renomear "$meu" NLinux || \
    warn "A firmware vai mostrar 'Linux Boot Manager'; o NLinux continua na partição."

  _efivars_dump "depois de renomear a entrada"

  # Apaga as sobras do systemd-boot nesta mesma ESP (instalações antigas).
  local num rotulo
  while IFS=$'\t' read -r num rotulo; do
    [[ -n "$num" && "$num" != "$meu" ]] || continue
    if efibootmgr -b "$num" -B >/dev/null 2>&1; then
      info "Entrada duplicada removida: Boot$num (${rotulo:-sem rótulo})"
    else
      warn "Não consegui remover a duplicada Boot$num (${rotulo:-sem rótulo})."
    fi
  done < <(_efiboot_esta_esp "$esp_guid")

  _efivars_dump "final (depois de remover as duplicatas)"
  return 0
}

# ---------------------------------------------------------------------------
# Desmontagem
# ---------------------------------------------------------------------------
# Em caso de falha, grava o erro NO DISCO-ALVO antes de desmontar, para ser
# lido depois sem a VM (ex.: /run/media/<user>/NLinux/@log/install-error.log).
_save_error_marker() {
  local rc=$1
  mkdir -p "$MNT/var/log" 2>/dev/null || true
  { echo "=== INSTALAÇÃO FALHOU (rc=$rc) em $(date -Is) ==="; echo; } \
    > "$MNT/var/log/install-error.log" 2>/dev/null || true
  [[ -f /tmp/nlinux-install.log ]] \
    && tail -n 150 /tmp/nlinux-install.log >> "$MNT/var/log/install-error.log" 2>/dev/null || true
  warn "Erro da instalação salvo em: $MNT/var/log/install-error.log"
}

# O log vive em /tmp do live, que é tmpfs: morre no reboot. Só a falha era
# copiada, o que impedia investigar uma instalação que deu certo no painel mas
# ficou errada no boot (o rótulo da entrada UEFI, por exemplo).
_save_install_log() {
  [[ -f /tmp/nlinux-install.log ]] || return 0
  mkdir -p "$MNT/var/log" 2>/dev/null || return 0
  cp -f /tmp/nlinux-install.log "$MNT/var/log/nlinux-install.log" 2>/dev/null || return 0
  ok "Log da instalação em /var/log/nlinux-install.log"
}

umount_all() {
  info "Desmontando sistemas de arquivos"
  umount -R "$MNT" 2>/dev/null || true
  if ls /dev/mapper/cryptroot >/dev/null 2>&1; then
    cryptsetup close cryptroot 2>/dev/null || true
  fi

  rm -f "$INSTALL_BASE/.part_efi" "$INSTALL_BASE/.part_root"
}

# ---------------------------------------------------------------------------
# Main
# ---------------------------------------------------------------------------
# ---------------------------------------------------------------------------
# O instalador (binários, /opt/noctalia-installer, atalhos e ícone) é só do
# live. Após o chroot terminar, remove qualquer vestígio do disco instalado.
# ---------------------------------------------------------------------------
remove_installer_artifacts() {
  info "Removendo o instalador do sistema instalado (menu, ícone e binários)"
  rm -rf "$MNT/opt/noctalia-installer"
  rm -f "$MNT/usr/local/bin/nlinux-installer" "$MNT/usr/local/bin/nlinux-installer-gui"
  rm -f "$MNT/usr/share/applications/nlinux-installer.desktop"
  rm -f "$MNT/usr/share/pixmaps/nlinux-installer.png"
  rm -f "$MNT/home/$INSTALL_USER/Desktop/nlinux-installer.desktop" 2>/dev/null || true
  rm -f "$MNT/root/.automated_script.sh" 2>/dev/null || true
  rm -f "$MNT/etc/sudoers.d/10-nlinux-builder" 2>/dev/null || true
}

main() {
  # Sentinela de resultado NLRESULT|<rc> como ÚLTIMA linha do log: é o que
  # permite ao painel (web/server.py) saber o código de saída mesmo quando a
  # execução foi reanexada de outro processo do servidor. O `if` (em vez de
  # `&&`) evita que o set -e mate o trap antes de o sentinela ser escrito, e o
  # `rc` original é preservado como status de saída do script.
  trap 'rc=$?; if (( rc != 0 )); then _save_error_marker "$rc"; fi; note "stage.note.unmount"; umount_all || true; printf "NLRESULT|%s\n" "$rc"' EXIT

  info "Instalador Arch Linux + Noctalia (Umbriel, greetd, noctalia-greeter)"
  preflight
  collect_options
  apply_live_options
  # O plano precisa de OFFLINE definitivo (collect_options) e vem antes de
  # qualquer NLPROGRESS, para o painel já ter a lista completa de etapas.
  build_plan
  stage stage.lang_key
  apply_mirror
  stage stage.mirror
  stage stage.disk
  partition_disk
  setup_filesystem
  stage stage.fs
  if (( OFFLINE )); then
    stage stage.copy.offline
    offline_clone
    note "stage.copy.done"
  else
    stage stage.pac.download
    stage_packages
    note "stage.pac.done"
  fi
  note "stage.note.store"
  stage_software_store
  # As etapas dentro do chroot se anunciam sozinhas (NLSTEP, via all.sh).
  run_chroot_setup
  stage stage.boot
  remove_installer_artifacts

  if [[ -d /sys/firmware/efi/efivars ]]; then
    register_uefi
  else
    warn "Ambiente sem efivars; apenas o fallback /EFI/BOOT será gravado."
  fi

  stage stage.final
  _save_install_log
  ok "Instalação concluída com sucesso. Desmonte é feito automaticamente."
  ok "Remova o pendrive e reinicie: reboot"
}

main "$@"