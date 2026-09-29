#!/bin/bash
set -euo pipefail

COLOR_RESET='\e[0m'
COLOR_CYAN='\e[36m'
COLOR_YELLOW='\e[33m'
COLOR_RED='\e[31m'
COLOR_GREEN='\e[32m'

log()  { echo -e "${COLOR_CYAN}[chroot]${COLOR_RESET} $*"; }
warn() { echo -e "${COLOR_YELLOW}[chroot][atenção]${COLOR_RESET} $*"; }
die()  { echo -e "${COLOR_RED}[chroot][erro]${COLOR_RESET} $*" >&2; exit 1; }
ok()   { echo -e "${COLOR_GREEN}[chroot][ok]${COLOR_RESET} $*"; }

require_env() {
  local var
  for var in INSTALL_USER INSTALL_USER_PASS ROOT_PASS HOSTNAME LOCALE KEYMAP ZONEINFO FS_TYPE USE_LUKS GPU MICROCODE SHARE_DIR; do
    [[ -n "${!var:-}" ]] || die "Variável $var não definida (execute via install.sh)."
  done
}

as_user() {
  local user=$1
  shift
  runuser -u "$user" -- "$@"
}

# Etapa atual para o painel do instalador web. A porcentagem NÃO vem aqui: ela
# está no plano que o install.sh enviou (NLSTEPS) e o web/server.py a aplica.
# Atividade temporária (não muda a etapa da lista) é cnote.
cstage() {
  [[ "${GUI_DRIVEN:-0}" == "1" ]] || return 0
  printf 'NLSTEP|%s\n' "$1"
}

cnote() {
  [[ "${GUI_DRIVEN:-0}" == "1" ]] || return 0
  printf 'NLNOTE|%s\n' "$1"
}

# Atividade com nome, junto da etapa no painel: "Compilando umbriel-git".
# <item> entra no %s da tradução — por isso o texto sai traduzido e não cru.
cact() {
  [[ "${GUI_DRIVEN:-0}" == "1" ]] || return 0
  printf 'NLACT|%s|%s\n' "$1" "$2"
}
