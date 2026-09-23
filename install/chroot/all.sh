#!/bin/bash
set -euo pipefail

source "$SHARE_DIR/chroot/helpers.sh"

require_env

log "Configuração do sistema base"
"$SHARE_DIR/chroot/10-system.sh"

if [[ "${OFFLINE:-0}" == "1" ]]; then
  log "Modo RÁPIDO offline: pacotes AUR já estão no sistema copiado — pulando yay."
else
  log "Pacotes AUR (umbriel-git, noctalia-greeter) via yay"
  "$SHARE_DIR/chroot/20-aur.sh"
fi

log "greetd + noctalia-greeter"
"$SHARE_DIR/chroot/30-greetd.sh"

log "Configurações do usuário"
"$SHARE_DIR/chroot/40-user-config.sh"

log "Boas-vindas no primeiro login"
"$SHARE_DIR/chroot/41-welcome.sh"

log "Serviços do sistema"
"$SHARE_DIR/chroot/50-services.sh"

ok "Setup em chroot finalizado."