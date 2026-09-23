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