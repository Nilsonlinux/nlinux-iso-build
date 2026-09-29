#!/bin/bash
set -euo pipefail

source "$SHARE_DIR/chroot/helpers.sh"

require_env

# Cada etapa se anuncia com cstage (NLSTEP): o painel do instalador web mostra
# a lista de etapas na ordem em que o chroot realmente trabalha, e o progresso
# para de "pular" da cópia direto para o bootloader.
log "Configuração do sistema base"
cstage stage.chroot.system
"$SHARE_DIR/chroot/10-system.sh"

if [[ "${OFFLINE:-0}" == "1" ]]; then
  log "Modo RÁPIDO offline: pacotes AUR já estão no sistema copiado — pulando yay."
else
  cstage stage.chroot.aur
  log "Pacotes AUR (umbriel-git, noctalia-greeter) via yay"
  "$SHARE_DIR/chroot/20-aur.sh"
fi

cstage stage.chroot.desktop
log "greetd + noctalia-greeter"
cnote stage.note.greetd
"$SHARE_DIR/chroot/30-greetd.sh"

log "Configurações do usuário"
cnote stage.note.user
"$SHARE_DIR/chroot/40-user-config.sh"

log "Boas-vindas no primeiro login"
cnote stage.note.welcome
"$SHARE_DIR/chroot/41-welcome.sh"

log "Serviços do sistema"
cnote stage.note.services
"$SHARE_DIR/chroot/50-services.sh"

ok "Setup em chroot finalizado."
